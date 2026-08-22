"""Thin wrapper around the Qiskit Aer statevector simulator.

Keeping every simulator interaction in one place makes the rest of the code
independent of Qiskit's version-specific execution API and lets us cheaply
cap circuit width / shot counts so the whole demo stays laptop-friendly.
"""

from __future__ import annotations

from typing import Dict, Optional

from qiskit import QuantumCircuit, transpile
from qiskit_aer import AerSimulator

#: A single shared simulator instance (thread-safe for our sequential usage).
_SIMULATOR = AerSimulator()


def run_counts(
    circuit: QuantumCircuit, shots: int = 1, seed: Optional[int] = None
) -> Dict[str, int]:
    """Execute ``circuit`` on the Aer simulator and return the counts dict."""
    kwargs = {"shots": shots}
    if seed is not None:
        kwargs["seed_simulator"] = seed
    try:
        # Our circuits only use gates Aer supports natively, so the (relatively
        # expensive) transpilation pass can normally be skipped.
        result = _SIMULATOR.run(circuit, **kwargs).result()
    except Exception:  # pragma: no cover - defensive fallback
        result = _SIMULATOR.run(transpile(circuit, _SIMULATOR), **kwargs).result()
    return result.get_counts()


def single_shot_bits(circuit: QuantumCircuit, seed: Optional[int] = None) -> list[int]:
    """Run one shot and return the classical register as a little-endian bit list.

    Bit ``i`` of the returned list corresponds to classical bit ``i`` of the
    circuit (Qiskit prints registers most-significant-bit first, hence the
    reversal).
    """
    counts = run_counts(circuit, shots=1, seed=seed)
    bitstring = next(iter(counts)).replace(" ", "")
    return [int(c) for c in reversed(bitstring)]
