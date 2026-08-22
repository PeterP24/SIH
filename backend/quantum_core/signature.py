"""Teleportation-based Quantum Digital Signature (QDS) protocol.

Protocol overview
-----------------
Setup
    Alice (signer) and the verifier (Bob / Charlie) share ``2n`` EPR pairs.
    Measuring them yields a shared secret key (:mod:`quantum_core.entanglement`).
    Two key bits per position select the Pauli basis ``b_i in {X, Y, Z}`` used
    at position ``i`` (:func:`quantum_core.pauli.basis_schedule`).

Signing a message ``m``
    1. ``d = SHA-256(m)`` is truncated to ``n`` bits ``v_1..v_n`` (the digest).
    2. For every ``i`` Alice prepares the eigenstate of ``b_i`` encoding ``v_i``
       and *teleports* it to the verifier, publishing the Bell-measurement bits
       ``(m1, m0)_i``.  Those classical bits are uniformly random and leak
       nothing about the state, so they form the public part of the signature.
    3. The signature is ``(digest, {(m1, m0)_i}, {correction_i}, {v_i})``
       together with a nonce and timestamp.

Verifying
    The verifier repeats the teleportation using *its own* key-derived basis
    schedule, applies the Pauli corrections and performs a projective
    measurement of every qubit.  Each outcome is compared with the digest bit of
    the *presented* message.  The empirical mismatch rate is fed to the purely
    statistical decision engine (:mod:`quantum_core.threshold`).

Why it detects attacks
    * A forger/impersonator has no key, so its basis schedule agrees with the
      verifier's only 1/3 of the time; mutually unbiased bases then randomise
      the outcome, driving the mismatch rate to ~1/3.
    * A replayed signature carries the digest of the *old* message, so roughly
      half the positions disagree with the new digest.
    * An eavesdropper cannot clone the travelling qubit (no-cloning theorem);
      intercept-resend collapses the state and inflates both the mismatch rate
      and the QBER of the key-distribution round.
"""

from __future__ import annotations

import hashlib
import random
import time
import uuid
from dataclasses import asdict, dataclass, field
from typing import Dict, List, Optional

from .entanglement import distribute_key
from .measurement import MeasurementStats
from .pauli import PAULI_BASES, basis_schedule
from .teleportation import teleport_bit
from .threshold import DEFAULT_QBER_THRESHOLD, DEFAULT_THRESHOLD, Decision, evaluate

#: Number of signature qubits per message (kept small so the demo is fast).
DEFAULT_SIGNATURE_LENGTH = 24


def digest_bits(message: str, length: int) -> List[int]:
    """Return the first ``length`` bits of ``SHA-256(message)``.

    The hash binds the signature to the message content: changing a single
    character changes ~50% of the digest bits (avalanche effect), which is what
    makes replay attacks statistically visible.
    """
    h = hashlib.sha256(message.encode("utf-8")).digest()
    bits: List[int] = []
    for byte in h:
        for k in range(8):
            bits.append((byte >> (7 - k)) & 1)
            if len(bits) == length:
                return bits
    return bits


@dataclass
class Signature:
    """A quantum digital signature (classical transcript of the quantum run)."""

    signature_id: str
    message: str
    message_hash: str
    signer: str
    key_id: str
    length: int
    declared_bits: List[int]
    encoding_bases: List[str]
    bell_bits: List[List[int]]
    corrections: List[str]
    nonce: str
    created_at: float
    steps: List[Dict[str, object]] = field(default_factory=list)

    def as_dict(self) -> Dict[str, object]:
        return asdict(self)


@dataclass
class VerificationResult:
    """Verifier-side result: measurement statistics plus the threshold decision."""

    signature_id: str
    verifier: str
    message: str
    decision: Decision
    stats: MeasurementStats
    verifier_bases: List[str]
    measured_bits: List[int]
    expected_bits: List[int]
    anomalies: List[str]
    elapsed_ms: float

    def as_dict(self) -> Dict[str, object]:
        return {
            "signature_id": self.signature_id,
            "verifier": self.verifier,
            "message": self.message,
            "verdict": self.decision.verdict,
            "accepted": self.decision.accepted,
            "decision": self.decision.as_dict(),
            "stats": self.stats.as_dict(),
            "verifier_bases": self.verifier_bases,
            "measured_bits": self.measured_bits,
            "expected_bits": self.expected_bits,
            "anomalies": self.anomalies,
            "elapsed_ms": round(self.elapsed_ms, 3),
        }


class QDSProtocol:
    """Stateless-by-design driver for signing and verifying.

    Key material is handed in/out explicitly so the API layer can persist it in
    SQLite and so attack modules can deliberately supply *wrong* keys.
    """

    def __init__(
        self,
        signature_length: int = DEFAULT_SIGNATURE_LENGTH,
        threshold: float = DEFAULT_THRESHOLD,
        qber_threshold: float = DEFAULT_QBER_THRESHOLD,
        seed: Optional[int] = None,
    ) -> None:
        self.signature_length = signature_length
        self.threshold = threshold
        self.qber_threshold = qber_threshold
        self.rng = random.Random(seed)

    # ------------------------------------------------------------------ keys
    def generate_key(self) -> Dict[str, object]:
        """Distribute entanglement and distil a shared key.

        Returns a dict with the key id, the sifted key bits and the QBER of the
        distribution round (0 for an undisturbed channel).
        """
        key = distribute_key(2 * self.signature_length)
        return {
            "key_id": f"key-{uuid.uuid4().hex[:12]}",
            "bits": key.bits,
            "qber": key.qber,
        }

    def random_key(self) -> Dict[str, object]:
        """Fabricate key material an attacker might guess (no entanglement)."""
        return {
            "key_id": f"key-forged-{uuid.uuid4().hex[:8]}",
            "bits": [self.rng.randint(0, 1) for _ in range(2 * self.signature_length)],
            "qber": 0.0,
        }

    # ------------------------------------------------------------------ sign
    def sign(
        self,
        message: str,
        key_bits: List[int],
        key_id: str,
        signer: str = "Alice",
        *,
        declared_bits: Optional[List[int]] = None,
        channel_error_rate: float = 0.0,
    ) -> Signature:
        """Sign ``message`` by teleporting its digest qubits to the verifier.

        ``declared_bits`` lets an attack module inject bits that do *not* match
        the message digest (e.g. a replayed transcript).
        """
        n = self.signature_length
        bits = declared_bits if declared_bits is not None else digest_bits(message, n)
        bases = basis_schedule(key_bits, n)

        bell: List[List[int]] = []
        corrections: List[str] = []
        steps: List[Dict[str, object]] = []
        for i in range(n):
            outcome = teleport_bit(
                bits[i],
                bases[i],
                bases[i],
                channel_error_rate=channel_error_rate,
                rng=self.rng,
            )
            bell.append([outcome.bell_bits[0], outcome.bell_bits[1]])
            corrections.append(outcome.correction)
            if i < 8:  # keep the UI walkthrough short
                steps.append(
                    {
                        "index": i,
                        "digest_bit": bits[i],
                        "basis": bases[i],
                        "prepared_state": _state_label(bases[i], bits[i]),
                        "bell_measurement": f"{outcome.bell_bits[0]}{outcome.bell_bits[1]}",
                        "pauli_correction": outcome.correction,
                        "description": (
                            f"Encoded digest bit {bits[i]} as {_state_label(bases[i], bits[i])} "
                            f"in the {bases[i]} basis, teleported it through |Phi+>, "
                            f"Bell outcome {outcome.bell_bits[0]}{outcome.bell_bits[1]} "
                            f"-> verifier applies {outcome.correction}."
                        ),
                    }
                )

        return Signature(
            signature_id=f"sig-{uuid.uuid4().hex[:12]}",
            message=message,
            message_hash=hashlib.sha256(message.encode("utf-8")).hexdigest(),
            signer=signer,
            key_id=key_id,
            length=n,
            declared_bits=bits,
            encoding_bases=bases,
            bell_bits=bell,
            corrections=corrections,
            nonce=uuid.uuid4().hex[:16],
            created_at=time.time(),
            steps=steps,
        )

    # ---------------------------------------------------------------- verify
    def verify(
        self,
        signature: Signature,
        message: str,
        verifier_key_bits: List[int],
        verifier: str = "Bob",
        *,
        channel_error_rate: float = 0.0,
        intercept: bool = False,
        key_qber: float = 0.0,
        extra_anomalies: Optional[List[str]] = None,
    ) -> VerificationResult:
        """Re-run the teleportation and apply the statistical threshold test."""
        start = time.perf_counter()
        n = signature.length
        expected = digest_bits(message, n)
        verifier_bases = basis_schedule(verifier_key_bits, n)

        stats = MeasurementStats()
        measured: List[int] = []
        for i in range(n):
            outcome = teleport_bit(
                signature.declared_bits[i],
                signature.encoding_bases[i],
                verifier_bases[i],
                channel_error_rate=channel_error_rate,
                intercept=intercept,
                rng=self.rng,
            )
            measured.append(outcome.measured_bit)
            stats.record(verifier_bases[i], expected[i], outcome.measured_bit)

        anomalies = list(extra_anomalies or [])
        if signature.message_hash != hashlib.sha256(message.encode("utf-8")).hexdigest():
            anomalies.append(
                "message hash bound to the signature differs from the presented message"
            )
        if key_qber > self.qber_threshold:
            anomalies.append(f"key-distribution QBER {key_qber:.3f} above tolerance")

        decision = evaluate(
            stats.mismatch_rate,
            n,
            qber=key_qber,
            threshold=self.threshold,
            qber_threshold=self.qber_threshold,
        )
        return VerificationResult(
            signature_id=signature.signature_id,
            verifier=verifier,
            message=message,
            decision=decision,
            stats=stats,
            verifier_bases=verifier_bases,
            measured_bits=measured,
            expected_bits=expected,
            anomalies=anomalies,
            elapsed_ms=(time.perf_counter() - start) * 1000.0,
        )


def _state_label(basis: str, bit: int) -> str:
    """Human-readable ket for the Pauli eigenstate encoding ``bit``."""
    labels = {
        "Z": ("|0>", "|1>"),
        "X": ("|+>", "|->"),
        "Y": ("|+i>", "|-i>"),
    }
    return labels[basis.upper()][int(bit) & 1]


__all__ = [
    "PAULI_BASES",
    "QDSProtocol",
    "Signature",
    "VerificationResult",
    "digest_bits",
    "DEFAULT_SIGNATURE_LENGTH",
]
