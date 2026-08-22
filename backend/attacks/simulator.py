"""Attack simulation module.

Threat model
------------
The adversary (Eve) may:

* **forgery** -- craft a signature for a message without holding the shared
  entanglement-derived key.  She must guess the Pauli basis at every position;
  she is right only 1/3 of the time, and a wrong basis yields a uniformly random
  measurement outcome, so the verifier sees ``E[mismatch] = 1/3``.
* **replay** -- take a transcript that was valid for message ``m1`` and present
  it for a different message ``m2``.  Because SHA-256 has the avalanche
  property, ``m2``'s digest differs from ``m1``'s in ~50% of the bits, so
  ``E[mismatch] ~ 1/2``.  The signature-id/nonce registry catches it too.
* **impersonation** -- claim to be Alice (or a legitimate verifier) using a key
  she generated herself.  Statistically identical to forgery, but the identity
  mismatch is additionally logged.
* **channel_manipulation** -- intercept the travelling qubit, measure it in a
  random basis and resend (intercept-resend), and/or inject channel noise.  The
  no-cloning theorem forbids copying the qubit, so this collapses the state and
  raises both the mismatch rate and the QBER of the key-distribution round.

A **baseline** (honest) run is also available so the metrics module can measure
false-rejection rate alongside false-acceptance rate.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from quantum_core.signature import QDSProtocol, Signature, VerificationResult, digest_bits

#: Attack identifiers accepted by the API.
ATTACK_TYPES = (
    "forgery",
    "replay",
    "impersonation",
    "channel_manipulation",
    "baseline",
)

#: Human-readable descriptions surfaced in the UI.
ATTACK_DESCRIPTIONS: Dict[str, str] = {
    "forgery": "Adversary without the shared key fabricates a signature by guessing Pauli bases.",
    "replay": "A previously valid signature transcript is replayed against a different message.",
    "impersonation": "Adversary claims Alice's identity using self-generated key material.",
    "channel_manipulation": "Intercept-resend eavesdropping plus injected noise on the quantum channel.",
    "baseline": "Honest signer and verifier -- control run used for false-rejection statistics.",
}


@dataclass
class AttackReport:
    """Outcome of one simulated attack."""

    attack_id: str
    attack_type: str
    description: str
    target_signature_id: str
    presented_message: str
    attacker: str
    detected: bool
    expected_detection: bool
    verification: VerificationResult
    indicators: List[str] = field(default_factory=list)
    elapsed_ms: float = 0.0

    def as_dict(self) -> Dict[str, object]:
        return {
            "attack_id": self.attack_id,
            "attack_type": self.attack_type,
            "description": self.description,
            "target_signature_id": self.target_signature_id,
            "presented_message": self.presented_message,
            "attacker": self.attacker,
            "detected": self.detected,
            "expected_detection": self.expected_detection,
            "correct_decision": self.detected == self.expected_detection,
            "indicators": self.indicators,
            "verification": self.verification.as_dict(),
            "elapsed_ms": round(self.elapsed_ms, 3),
        }


class AttackSimulator:
    """Runs the simulated attacks against a genuine signature."""

    def __init__(self, protocol: QDSProtocol) -> None:
        self.protocol = protocol

    def run(
        self,
        attack_type: str,
        genuine_signature: Signature,
        honest_key_bits: List[int],
        *,
        tampered_message: Optional[str] = None,
        channel_error_rate: float = 0.25,
    ) -> AttackReport:
        """Dispatch to the requested attack simulation."""
        if attack_type not in ATTACK_TYPES:
            raise ValueError(f"unknown attack type: {attack_type}")
        start = time.perf_counter()
        handler = getattr(self, f"_{attack_type}")
        report: AttackReport = handler(
            genuine_signature,
            honest_key_bits,
            tampered_message=tampered_message,
            channel_error_rate=channel_error_rate,
        )
        report.elapsed_ms = (time.perf_counter() - start) * 1000.0
        return report

    # ------------------------------------------------------------- attacks
    def _forgery(
        self,
        signature: Signature,
        honest_key_bits: List[int],
        *,
        tampered_message: Optional[str],
        channel_error_rate: float,
    ) -> AttackReport:
        message = tampered_message or signature.message
        forged_key = self.protocol.random_key()
        forged = self.protocol.sign(
            message, forged_key["bits"], forged_key["key_id"], signer="Eve"
        )
        result = self.protocol.verify(
            forged,
            message,
            honest_key_bits,
            verifier="Bob",
            extra_anomalies=["signature produced with key material unknown to the verifier"],
        )
        return self._report(
            "forgery", signature, message, "Eve", result,
            indicators=[
                "basis schedule disagrees with the verifier's key-derived schedule",
                f"observed mismatch rate {result.stats.mismatch_rate:.3f} vs expected 0.333 for a key-less forger",
            ],
        )

    def _replay(
        self,
        signature: Signature,
        honest_key_bits: List[int],
        *,
        tampered_message: Optional[str],
        channel_error_rate: float,
    ) -> AttackReport:
        message = tampered_message or (signature.message + " [amount: 10000]")
        result = self.protocol.verify(
            signature,
            message,
            honest_key_bits,
            verifier="Bob",
            extra_anomalies=[
                "signature nonce already consumed for a different message (replay registry hit)"
            ],
        )
        old = digest_bits(signature.message, signature.length)
        new = digest_bits(message, signature.length)
        drift = sum(a != b for a, b in zip(old, new)) / signature.length
        return self._report(
            "replay", signature, message, "Eve", result,
            indicators=[
                f"digest drift between original and presented message: {drift:.3f}",
                "signature transcript reused with a stale nonce",
            ],
        )

    def _impersonation(
        self,
        signature: Signature,
        honest_key_bits: List[int],
        *,
        tampered_message: Optional[str],
        channel_error_rate: float,
    ) -> AttackReport:
        message = tampered_message or signature.message
        rogue_key = self.protocol.random_key()
        rogue = self.protocol.sign(
            message, rogue_key["bits"], rogue_key["key_id"], signer="Alice"
        )
        result = self.protocol.verify(
            rogue,
            message,
            honest_key_bits,
            verifier="Bob",
            extra_anomalies=[
                f"claimed signer 'Alice' presented unknown key id {rogue_key['key_id']}"
            ],
        )
        return self._report(
            "impersonation", signature, message, "Eve (as Alice)", result,
            indicators=[
                "claimed identity is not bound to the entangled key registered for Alice",
                f"observed mismatch rate {result.stats.mismatch_rate:.3f}",
            ],
        )

    def _channel_manipulation(
        self,
        signature: Signature,
        honest_key_bits: List[int],
        *,
        tampered_message: Optional[str],
        channel_error_rate: float,
    ) -> AttackReport:
        message = tampered_message or signature.message
        # Eve's intercept-resend also corrupts the entanglement-distribution
        # round, which shows up as a raised QBER.
        eve_key = self.protocol.generate_key()
        disturbed_qber = _intercept_resend_qber(honest_key_bits, eve_key["bits"])
        result = self.protocol.verify(
            signature,
            message,
            honest_key_bits,
            verifier="Bob",
            channel_error_rate=channel_error_rate,
            intercept=True,
            key_qber=disturbed_qber,
            extra_anomalies=["intercept-resend detected on the quantum channel"],
        )
        return self._report(
            "channel_manipulation", signature, message, "Eve (channel)", result,
            indicators=[
                f"key-distribution QBER rose to {disturbed_qber:.3f} (tolerance {self.protocol.qber_threshold})",
                "no-cloning theorem: intercepted qubits cannot be copied, only disturbed",
            ],
        )

    def _baseline(
        self,
        signature: Signature,
        honest_key_bits: List[int],
        *,
        tampered_message: Optional[str],
        channel_error_rate: float,
    ) -> AttackReport:
        message = tampered_message or signature.message
        result = self.protocol.verify(signature, message, honest_key_bits, verifier="Bob")
        report = self._report(
            "baseline", signature, message, "Alice (honest)", result,
            indicators=["control run: honest signer, undisturbed channel"],
        )
        report.expected_detection = False
        report.detected = not result.decision.accepted
        return report

    # -------------------------------------------------------------- helpers
    def _report(
        self,
        attack_type: str,
        signature: Signature,
        message: str,
        attacker: str,
        result: VerificationResult,
        indicators: List[str],
    ) -> AttackReport:
        return AttackReport(
            attack_id=f"atk-{uuid.uuid4().hex[:12]}",
            attack_type=attack_type,
            description=ATTACK_DESCRIPTIONS[attack_type],
            target_signature_id=signature.signature_id,
            presented_message=message,
            attacker=attacker,
            detected=not result.decision.accepted,
            expected_detection=attack_type != "baseline",
            verification=result,
            indicators=indicators,
        )


def _intercept_resend_qber(honest_bits: List[int], eve_bits: List[int]) -> float:
    """QBER induced when Eve measures and resends half of every EPR pair.

    Eve picks the right basis half the time; when she is wrong the resent qubit
    is uncorrelated, so Bob disagrees with Alice with probability 1/2.  The
    theoretical QBER is therefore 25%; this helper derives the empirical value
    from Eve's own (random) measurement record:

        QBER = 1/2 * (fraction of positions Eve disturbed)
    """
    n = min(len(honest_bits), len(eve_bits))
    if n == 0:
        return 0.0
    disturbed = sum(1 for i in range(n) if honest_bits[i] != eve_bits[i])
    return round(0.5 * disturbed / n, 4)
