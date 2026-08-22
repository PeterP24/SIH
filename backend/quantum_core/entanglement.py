"""Bell-state (EPR pair) generation -- the shared quantum key resource.

Mathematical background
-----------------------
The four maximally entangled two-qubit Bell states are

    |Phi+> = (|00> + |11>)/sqrt(2)      |Phi-> = (|00> - |11>)/sqrt(2)
    |Psi+> = (|01> + |10>)/sqrt(2)      |Psi-> = (|01> - |10>)/sqrt(2)

``|Phi+>`` is produced from ``|00>`` by a Hadamard on the first qubit followed
by a CNOT:

    CNOT (H (x) I) |00> = (|00> + |11>)/sqrt(2)

In the QDS protocol Alice (signer) keeps qubit 0 of every pair and the verifier
(Bob / Charlie) keeps qubit 1.  Measuring both halves in the same Pauli basis
yields perfectly correlated outcomes, which is what turns the entangled pairs
into a shared secret key.  An eavesdropper cannot copy a half-pair
(no-cloning), so any interception shows up as decorrelation.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List

from qiskit import QuantumCircuit

from .backend import run_counts


def bell_pair_circuit(num_pairs: int = 1) -> QuantumCircuit:
    """Build a circuit preparing ``num_pairs`` independent ``|Phi+>`` states.

    Qubit layout: pair ``i`` occupies qubits ``2i`` (Alice) and ``2i+1``
    (verifier).
    """
    qc = QuantumCircuit(2 * num_pairs, name="bell_pairs")
    for i in range(num_pairs):
        qc.h(2 * i)
        qc.cx(2 * i, 2 * i + 1)
    return qc


@dataclass
class EntangledKey:
    """Shared key material distilled from measured Bell pairs.

    Attributes
    ----------
    alice_bits, verifier_bits:
        Measurement outcomes of the two halves.  For a noiseless channel they
        are identical; every mismatch is an error induced by noise or by an
        eavesdropper.
    """

    alice_bits: List[int] = field(default_factory=list)
    verifier_bits: List[int] = field(default_factory=list)

    @property
    def qber(self) -> float:
        """Quantum Bit Error Rate: fraction of positions where halves differ."""
        if not self.alice_bits:
            return 0.0
        mismatches = sum(a != b for a, b in zip(self.alice_bits, self.verifier_bits))
        return mismatches / len(self.alice_bits)

    @property
    def bits(self) -> List[int]:
        """Sifted key (Alice's copy is taken as the reference)."""
        return list(self.alice_bits)


#: Pairs simulated per circuit; keeps circuit width well inside the simulator's
#: qubit budget and memory usage negligible.
CHUNK_PAIRS = 8


def distribute_key(num_bits: int, seed: int | None = None) -> EntangledKey:
    """Simulate entanglement-based key distribution over ``num_bits`` EPR pairs.

    Each pair is prepared in ``|Phi+>`` and both halves measured in the Z basis;
    the perfectly correlated outcomes form the shared key.  Pairs are simulated
    in small chunks so the statevector stays tiny.
    """
    key = EntangledKey()
    remaining = num_bits
    while remaining > 0:
        pairs = min(CHUNK_PAIRS, remaining)
        qc = bell_pair_circuit(pairs)
        qc.measure_all()
        counts = run_counts(qc, shots=1, seed=seed)
        bitstring = next(iter(counts))  # Qiskit returns little-endian strings
        bits = [int(c) for c in reversed(bitstring.replace(" ", ""))]
        key.alice_bits.extend(bits[2 * i] for i in range(pairs))
        key.verifier_bits.extend(bits[2 * i + 1] for i in range(pairs))
        remaining -= pairs
    return key
