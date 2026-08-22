"""FastAPI application exposing the QDS protocol and threat-detection engine.

Endpoints
---------
POST /sign             sign a message (teleportation-based QDS)
POST /verify           verify a signature (projective measurement + threshold)
POST /simulate-attack  run a simulated attack and report whether it was caught
GET  /metrics          security + performance metrics
GET  /logs             history of sign / verify / attack events
GET  /signatures       recent signatures
GET  /attack-types     attack catalogue for the UI
GET  /health           liveness probe + active configuration
"""

from __future__ import annotations

import os
import time
from pathlib import Path
from typing import List, Optional

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from attacks import ATTACK_DESCRIPTIONS, ATTACK_TYPES, AttackSimulator
from quantum_core.signature import (
    DEFAULT_SIGNATURE_LENGTH,
    QDSProtocol,
    Signature,
)
from quantum_core.threshold import DEFAULT_QBER_THRESHOLD, DEFAULT_THRESHOLD

from .metrics import compute_metrics
from .schemas import (
    AttackRequest,
    AttackResponse,
    AttackTypeInfo,
    SignRequest,
    SignResponse,
    VerifyRequest,
    VerifyResponse,
)
from .storage import Storage

SIGNATURE_LENGTH = int(os.getenv("QDS_SIGNATURE_LENGTH", DEFAULT_SIGNATURE_LENGTH))
THRESHOLD = float(os.getenv("QDS_THRESHOLD", DEFAULT_THRESHOLD))
QBER_THRESHOLD = float(os.getenv("QDS_QBER_THRESHOLD", DEFAULT_QBER_THRESHOLD))
DB_PATH = os.getenv("QDS_DB_PATH")

app = FastAPI(
    title="Quantum-Inspired Cyber Threat Detection for Digital Signature Security",
    description=(
        "Simulation of a teleportation-based Quantum Digital Signature protocol "
        "with purely statistical (non-ML) threat detection. SIH PS 26141."
    ),
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

protocol = QDSProtocol(
    signature_length=SIGNATURE_LENGTH,
    threshold=THRESHOLD,
    qber_threshold=QBER_THRESHOLD,
)
simulator = AttackSimulator(protocol)
storage = Storage(Path(DB_PATH) if DB_PATH else None)


def get_storage() -> Storage:
    return storage


def _load_signature(signature_id: str, store: Storage) -> tuple[Signature, List[int]]:
    """Fetch a stored signature and its key material, or raise 404."""
    record = store.get_signature(signature_id)
    if record is None:
        raise HTTPException(status_code=404, detail=f"unknown signature {signature_id}")
    key_bits = record.pop("_key_bits")
    return Signature(**record), key_bits


@app.get("/health")
def health() -> dict:
    """Liveness probe plus the active protocol configuration."""
    return {
        "status": "ok",
        "signature_length": SIGNATURE_LENGTH,
        "threshold": THRESHOLD,
        "qber_threshold": QBER_THRESHOLD,
        "detection": "quantum measurement statistics + threshold rules (no ML)",
    }


@app.post("/sign", response_model=SignResponse)
def sign(request: SignRequest, store: Storage = Depends(get_storage)) -> SignResponse:
    """Sign a message by teleporting its digest qubits to the verifier."""
    start = time.perf_counter()
    key = protocol.generate_key()
    signature = protocol.sign(
        request.message, key["bits"], key["key_id"], signer=request.signer
    )
    elapsed = (time.perf_counter() - start) * 1000.0

    payload = signature.as_dict()
    store.save_signature(payload, key["bits"])
    store.log_event(
        "sign",
        {**payload, "key_qber": key["qber"]},
        signature_id=signature.signature_id,
        subject=request.signer,
        verdict="SIGNED",
        qber=key["qber"],
        elapsed_ms=elapsed,
    )
    return SignResponse(
        **payload, elapsed_ms=round(elapsed, 3), key_qber=float(key["qber"])
    )


@app.post("/verify", response_model=VerifyResponse)
def verify(request: VerifyRequest, store: Storage = Depends(get_storage)) -> VerifyResponse:
    """Verify a signature with projective measurements and the threshold rule."""
    signature, key_bits = _load_signature(request.signature_id, store)
    message = request.message if request.message is not None else signature.message

    # Replay registry: the same transcript presented for a different message.
    seen = store.verified_messages_for(signature.signature_id)
    anomalies: List[str] = []
    if message != signature.message:
        anomalies.append("presented message differs from the signed message")
    if message in seen and message != signature.message:
        anomalies.append("signature transcript already used for this message (nonce reuse)")

    result = protocol.verify(
        signature, message, key_bits, verifier=request.verifier, extra_anomalies=anomalies
    )
    payload = result.as_dict()
    store.log_event(
        "verify",
        payload,
        signature_id=signature.signature_id,
        subject=request.verifier,
        verdict=result.decision.verdict,
        detected=not result.decision.accepted,
        expected_detection=message != signature.message,
        mismatch_rate=result.stats.mismatch_rate,
        qber=result.decision.qber,
        threshold=result.decision.threshold,
        forgery_probability=result.decision.forgery_probability,
        elapsed_ms=result.elapsed_ms,
    )
    return VerifyResponse(**payload)


@app.post("/simulate-attack", response_model=AttackResponse)
def simulate_attack(
    request: AttackRequest, store: Storage = Depends(get_storage)
) -> AttackResponse:
    """Mount a simulated attack against a signature and report the detection."""
    if request.attack_type not in ATTACK_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"unknown attack type {request.attack_type!r}; expected one of {list(ATTACK_TYPES)}",
        )
    signature_id = request.signature_id or store.latest_signature_id()
    if signature_id is None:
        raise HTTPException(status_code=400, detail="no signature available; sign a message first")
    signature, key_bits = _load_signature(signature_id, store)

    report = simulator.run(
        request.attack_type,
        signature,
        key_bits,
        tampered_message=request.tampered_message,
        channel_error_rate=request.channel_error_rate,
    )
    payload = report.as_dict()
    store.log_event(
        "attack",
        payload,
        signature_id=signature.signature_id,
        subject=report.attack_type,
        verdict=report.verification.decision.verdict,
        detected=report.detected,
        expected_detection=report.expected_detection,
        mismatch_rate=report.verification.stats.mismatch_rate,
        qber=report.verification.decision.qber,
        threshold=report.verification.decision.threshold,
        forgery_probability=report.verification.decision.forgery_probability,
        elapsed_ms=report.elapsed_ms,
    )
    return AttackResponse(**payload)


@app.get("/metrics")
def metrics(store: Storage = Depends(get_storage)) -> dict:
    """Detection accuracy, false accept/reject rates and timing statistics."""
    return compute_metrics(store.metric_rows(), SIGNATURE_LENGTH, THRESHOLD)


@app.get("/logs")
def logs(
    limit: int = Query(100, ge=1, le=1000),
    event_type: Optional[str] = Query(None, pattern="^(sign|verify|attack)$"),
    store: Storage = Depends(get_storage),
) -> dict:
    """History of signing, verification and attack events (most recent first)."""
    return {"events": store.list_events(limit=limit, event_type=event_type)}


@app.get("/signatures")
def signatures(
    limit: int = Query(50, ge=1, le=500), store: Storage = Depends(get_storage)
) -> dict:
    """Recently issued signatures."""
    return {"signatures": store.list_signatures(limit=limit)}


@app.get("/attack-types", response_model=List[AttackTypeInfo])
def attack_types() -> List[AttackTypeInfo]:
    """Catalogue of simulated attacks for the UI dropdown."""
    return [
        AttackTypeInfo(attack_type=name, description=ATTACK_DESCRIPTIONS[name])
        for name in ATTACK_TYPES
    ]


def _web_dir() -> Optional[Path]:
    """Locate a compiled Flutter web bundle to serve as the demo UI."""
    configured = os.getenv("QDS_WEB_DIR")
    root = Path(__file__).resolve().parents[2]
    candidates = [Path(configured)] if configured else []
    candidates += [root / "webapp", root / "frontend" / "build" / "web"]
    return next((c for c in candidates if (c / "index.html").is_file()), None)


# Serving the web bundle from the API origin means the browser demo needs no
# separate web server and no backend-URL configuration: http://localhost:8000/
WEB_DIR = _web_dir()
if WEB_DIR is not None:
    app.mount("/", StaticFiles(directory=str(WEB_DIR), html=True), name="webapp")
