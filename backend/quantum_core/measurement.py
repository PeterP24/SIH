"""Projective measurement statistics used by the verification stage.

Mathematical background
-----------------------
A projective measurement of a Pauli observable ``P`` uses the projectors

    P_+ = (I + P)/2      P_- = (I - P)/2

and yields outcome ``+1`` with probability ``<psi|P_+|psi>``.  When the verifier
measures in the *same* basis in which Alice encoded, the outcome is
deterministic (probability 1) in the noiseless case.  When the basis differs,
the two eigenbases are mutually unbiased and

    Pr[outcome] = |<phi_measure | phi_encode>|^2 = 1/2 ,

so the outcome carries no information and matches the expected bit only half of
the time.  An attacker who guesses the basis uniformly at random is wrong with
probability 2/3, giving an expected per-qubit mismatch rate of

    p_mismatch = (2/3) * (1/2) = 1/3 .

This module only aggregates outcomes; the actual circuits live in
:mod:`quantum_core.teleportation`.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Sequence


@dataclass
class MeasurementStats:
    """Aggregated projective-measurement statistics for one verification run."""

    total: int = 0
    mismatches: int = 0
    per_basis_total: Dict[str, int] = field(default_factory=dict)
    per_basis_mismatch: Dict[str, int] = field(default_factory=dict)
    outcomes: List[int] = field(default_factory=list)

    def record(self, basis: str, expected_bit: int, observed_bit: int) -> None:
        """Record one projective measurement outcome."""
        self.total += 1
        self.per_basis_total[basis] = self.per_basis_total.get(basis, 0) + 1
        self.outcomes.append(int(observed_bit))
        if int(expected_bit) != int(observed_bit):
            self.mismatches += 1
            self.per_basis_mismatch[basis] = self.per_basis_mismatch.get(basis, 0) + 1

    @property
    def mismatch_rate(self) -> float:
        """Fraction of qubits whose measured value differed from the expected one."""
        return self.mismatches / self.total if self.total else 0.0

    @property
    def fidelity(self) -> float:
        """Empirical agreement rate ``1 - mismatch_rate``."""
        return 1.0 - self.mismatch_rate

    def as_dict(self) -> Dict[str, object]:
        return {
            "total": self.total,
            "mismatches": self.mismatches,
            "mismatch_rate": round(self.mismatch_rate, 6),
            "fidelity": round(self.fidelity, 6),
            "per_basis_total": self.per_basis_total,
            "per_basis_mismatch": self.per_basis_mismatch,
        }


def compare_bits(expected: Sequence[int], observed: Sequence[int]) -> int:
    """Hamming distance between two equal-length bit sequences."""
    return sum(int(a) != int(b) for a, b in zip(expected, observed))
