"""Quantum teleportation protocol used to transport signature qubits.

Mathematical background
-----------------------
Alice holds an unknown message qubit ``|psi> = a|0> + b|1>`` (qubit ``q0``) and
one half of an EPR pair ``|Phi+>_{q1 q2}``; the verifier holds ``q2``.  The
joint state is

    |psi> (x) |Phi+> = 1/2 [ |Phi+>_{q0q1} (a|0>+b|1>)_{q2}
                           + |Phi->_{q0q1} (a|0>-b|1>)_{q2}
                           + |Psi+>_{q0q1} (a|1>+b|0>)_{q2}
                           + |Psi->_{q0q1} (a|1>-b|0>)_{q2} ]

Alice performs a Bell measurement on ``q0 q1`` (CNOT, then H on ``q0``, then
measure both).  The two classical bits ``(m1, m0)`` she obtains occur with
probability 1/4 each -- they carry *no* information about ``|psi>``, which is
why they can be published as the classical part of the signature.  The verifier
recovers ``|psi>`` by applying the Pauli correction ``X^{m0} Z^{m1}``
(see :mod:`quantum_core.pauli`).

Because the state is *moved* rather than copied, an attacker intercepting the
quantum channel destroys the state (no-cloning theorem) and shows up as an
elevated mismatch rate in the verifier's projective measurements.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from typing import Optional

from qiskit import ClassicalRegister, QuantumCircuit, QuantumRegister

from .backend import single_shot_bits
from .pauli import correction_for, eigenstate_angles


@dataclass
class TeleportationOutcome:
    """Result of teleporting one signature qubit.

    Attributes
    ----------
    bell_bits:
        Alice's Bell-measurement outcome ``(m1, m0)`` -- the classical part of
        the signature.
    correction:
        Pauli label (``I``/``X``/``Y``/``Z``) the verifier had to apply.
    measured_bit:
        The verifier's projective-measurement outcome in the agreed basis.
    """

    bell_bits: tuple[int, int]
    correction: str
    measured_bit: int


def _prepare_message_qubit(qc: QuantumCircuit, qubit, basis: str, bit: int) -> None:
    """Encode ``bit`` into the ``+/-1`` eigenstate of the given Pauli ``basis``."""
    theta, phi, lam = eigenstate_angles(basis, bit)
    qc.u(theta, phi, lam, qubit)


def _measure_in_basis(qc: QuantumCircuit, qubit, creg, basis: str) -> None:
    """Rotate the ``basis`` eigenbasis onto the computational basis and measure.

    X basis: H maps |+>,|-> -> |0>,|1>.
    Y basis: S^dagger then H maps |+i>,|-i> -> |0>,|1>.
    Z basis: measure directly.
    """
    basis = basis.upper()
    if basis == "X":
        qc.h(qubit)
    elif basis == "Y":
        qc.sdg(qubit)
        qc.h(qubit)
    qc.measure(qubit, creg)


def teleport_bit(
    bit: int,
    encode_basis: str,
    measure_basis: str,
    *,
    channel_error_rate: float = 0.0,
    intercept: bool = False,
    rng: Optional[random.Random] = None,
    seed: Optional[int] = None,
) -> TeleportationOutcome:
    """Teleport one signature qubit from Alice to the verifier.

    Parameters
    ----------
    bit:
        Message/digest bit to encode.
    encode_basis:
        Pauli basis Alice uses to encode (derived from the shared key).
    measure_basis:
        Pauli basis the verifier measures in.  Equals ``encode_basis`` for a
        legitimate party; a forger/impersonator holding no valid key guesses and
        is wrong with probability 2/3, in which case the outcome is uniformly
        random (mutually unbiased bases).
    channel_error_rate:
        Probability that the travelling qubit suffers a random Pauli flip
        (a simple depolarising-style channel model).
    intercept:
        If ``True`` an eavesdropper measures the verifier's half of the EPR pair
        in a random basis and resends it -- the classic intercept-resend attack,
        which unavoidably disturbs the state.
    """
    rng = rng or random.Random()

    q = QuantumRegister(3, "q")  # q0: message, q1: Alice EPR half, q2: verifier half
    c_bell = ClassicalRegister(2, "bell")
    c_out = ClassicalRegister(1, "out")
    qc = QuantumCircuit(q, c_bell, c_out)

    # 1. Alice encodes the digest bit into a Pauli eigenstate.
    _prepare_message_qubit(qc, q[0], encode_basis, bit)

    # 2. Entanglement distribution: |Phi+> across q1 (Alice) and q2 (verifier).
    qc.h(q[1])
    qc.cx(q[1], q[2])

    # 2b. Channel imperfection / eavesdropping on the travelling qubit q2.
    if intercept:
        # Intercept-resend: measuring in a random basis collapses the pair.
        eve_basis = rng.choice(["X", "Y", "Z"])
        if eve_basis == "X":
            qc.h(q[2])
        elif eve_basis == "Y":
            qc.sdg(q[2])
            qc.h(q[2])
        qc.measure(q[2], c_out[0])  # temporary use; overwritten below
        if eve_basis == "X":
            qc.h(q[2])
        elif eve_basis == "Y":
            qc.h(q[2])
            qc.s(q[2])
    if channel_error_rate > 0 and rng.random() < channel_error_rate:
        getattr(qc, rng.choice(["x", "y", "z"]))(q[2])

    # 3. Alice's Bell measurement on (q0, q1).
    qc.cx(q[0], q[1])
    qc.h(q[0])
    qc.measure(q[1], c_bell[0])  # m0
    qc.measure(q[0], c_bell[1])  # m1

    # 4. Verifier's Pauli correction X^{m0} Z^{m1} (deferred, classically
    #    controlled on Alice's published bits).
    with qc.if_test((c_bell[0], 1)):
        qc.x(q[2])
    with qc.if_test((c_bell[1], 1)):
        qc.z(q[2])

    # 5. Projective measurement of the recovered state in the agreed basis.
    _measure_in_basis(qc, q[2], c_out[0], measure_basis)

    bits = single_shot_bits(qc, seed=seed)
    m0, m1, out = bits[0], bits[1], bits[2]
    return TeleportationOutcome(
        bell_bits=(m1, m0),
        correction=correction_for(m1, m0),
        measured_bit=out,
    )
