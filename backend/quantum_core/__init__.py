"""Quantum-inspired core of the QDS (Quantum Digital Signature) framework.

Modules
-------
entanglement : Bell-state (EPR pair) preparation used as the shared quantum key.
teleportation: Teleportation-based signing of message qubits.
pauli        : Pauli operators / eigenstate encoding and correction rules.
measurement  : Projective measurement of signature qubits in the Pauli bases.
threshold    : Purely statistical accept/reject decision engine (no ML).
signature    : High-level QDS protocol tying the above together.
"""

from .signature import QDSProtocol, Signature, VerificationResult  # noqa: F401
