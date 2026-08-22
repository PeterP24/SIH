"""Simulated adversaries against the teleportation-based QDS protocol.

Every attack returns an :class:`AttackReport` describing what the adversary did
and whether the *statistical* detection engine caught it.  Detection never uses
machine learning -- only quantum measurement statistics and threshold rules.
"""

from .simulator import (  # noqa: F401
    ATTACK_DESCRIPTIONS,
    ATTACK_TYPES,
    AttackReport,
    AttackSimulator,
)
