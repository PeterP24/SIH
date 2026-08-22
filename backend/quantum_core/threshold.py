"""Statistical accept/reject decision engine.

**No machine learning is used anywhere.**  The decision is a closed-form
statistical test on quantum measurement statistics.

Decision rule
-------------
Let ``n`` be the number of signature qubits and ``k`` the number of mismatches
observed by the verifier.  The empirical mismatch rate is ``r = k / n``.

* Honest party, noiseless channel: ``r = 0``.
* Honest party, channel error rate ``e``: ``E[r] = e``.
* Attacker with no valid key: each qubit is measured/encoded in the wrong Pauli
  basis with probability 2/3, and a wrong basis gives a uniformly random
  outcome, so ``E[r] = 1/3``.

We therefore accept iff ``r <= tau`` with a threshold ``tau`` chosen strictly
between the honest noise floor and 1/3 (default ``tau = 0.15``).

Forgery probability
-------------------
Under the attacker model the number of mismatches is ``k ~ Binomial(n, 1/3)``.
The probability that a forgery slips through (false acceptance) is the lower
tail

    P_forge(n, tau) = sum_{k=0}^{floor(tau*n)} C(n, k) (1/3)^k (2/3)^(n-k)

which decays exponentially in ``n`` -- see ``SECURITY_ANALYSIS.md``.  With the
defaults (``n = 24``, ``tau = 0.15``) this is on the order of 1e-3.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import comb
from typing import Literal

#: Expected per-qubit mismatch rate for a party without the shared key:
#: wrong basis with probability 2/3, random outcome then mismatches half the time.
ATTACKER_MISMATCH_RATE: float = 1.0 / 3.0

#: Default statistical threshold on the mismatch rate.
DEFAULT_THRESHOLD: float = 0.15

#: Default threshold on the Quantum Bit Error Rate of the key-distribution round.
DEFAULT_QBER_THRESHOLD: float = 0.11


@dataclass
class Decision:
    """Outcome of the threshold test."""

    verdict: Literal["ACCEPT", "REJECT"]
    mismatch_rate: float
    threshold: float
    qber: float
    qber_threshold: float
    forgery_probability: float
    reason: str

    @property
    def accepted(self) -> bool:
        return self.verdict == "ACCEPT"

    def as_dict(self) -> dict:
        return {
            "verdict": self.verdict,
            "accepted": self.accepted,
            "mismatch_rate": round(self.mismatch_rate, 6),
            "threshold": self.threshold,
            "qber": round(self.qber, 6),
            "qber_threshold": self.qber_threshold,
            "forgery_probability": self.forgery_probability,
            "reason": self.reason,
        }


def forgery_probability(
    num_qubits: int,
    threshold: float = DEFAULT_THRESHOLD,
    attacker_rate: float = ATTACKER_MISMATCH_RATE,
) -> float:
    """Binomial lower-tail probability that a key-less attacker is accepted.

    ``P = sum_{k=0}^{floor(threshold*n)} C(n,k) p^k (1-p)^(n-k)`` with
    ``p = attacker_rate``.
    """
    if num_qubits <= 0:
        return 1.0
    k_max = int(threshold * num_qubits)
    return sum(
        comb(num_qubits, k) * attacker_rate**k * (1 - attacker_rate) ** (num_qubits - k)
        for k in range(0, k_max + 1)
    )


def evaluate(
    mismatch_rate: float,
    num_qubits: int,
    qber: float = 0.0,
    threshold: float = DEFAULT_THRESHOLD,
    qber_threshold: float = DEFAULT_QBER_THRESHOLD,
) -> Decision:
    """Apply the two-sided statistical test and return the accept/reject decision."""
    p_forge = forgery_probability(num_qubits, threshold)
    if qber > qber_threshold:
        reason = (
            f"quantum channel compromised: QBER {qber:.3f} exceeds "
            f"tolerance {qber_threshold:.3f}"
        )
        verdict: Literal["ACCEPT", "REJECT"] = "REJECT"
    elif mismatch_rate > threshold:
        reason = (
            f"measurement mismatch rate {mismatch_rate:.3f} exceeds "
            f"threshold {threshold:.3f} (key-less attacker expectation "
            f"{ATTACKER_MISMATCH_RATE:.3f})"
        )
        verdict = "REJECT"
    else:
        reason = (
            f"measurement mismatch rate {mismatch_rate:.3f} within "
            f"threshold {threshold:.3f}"
        )
        verdict = "ACCEPT"
    return Decision(
        verdict=verdict,
        mismatch_rate=mismatch_rate,
        threshold=threshold,
        qber=qber,
        qber_threshold=qber_threshold,
        forgery_probability=p_forge,
        reason=reason,
    )
