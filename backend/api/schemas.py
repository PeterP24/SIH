"""Pydantic request/response models for the REST API."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from attacks import ATTACK_TYPES


class SignRequest(BaseModel):
    message: str = Field(..., min_length=1, description="Plaintext message to sign")
    signer: str = Field("Alice", description="Identity of the signer")


class SignResponse(BaseModel):
    signature_id: str
    message: str
    message_hash: str
    signer: str
    key_id: str
    length: int
    bell_bits: List[List[int]]
    corrections: List[str]
    encoding_bases: List[str]
    declared_bits: List[int]
    nonce: str
    created_at: float
    steps: List[Dict[str, Any]]
    elapsed_ms: float
    key_qber: float


class VerifyRequest(BaseModel):
    signature_id: str
    message: Optional[str] = Field(
        None, description="Message to verify against; defaults to the signed message"
    )
    verifier: str = Field("Bob", description="Identity of the verifier")


class VerifyResponse(BaseModel):
    signature_id: str
    verifier: str
    message: str
    verdict: str
    accepted: bool
    decision: Dict[str, Any]
    stats: Dict[str, Any]
    verifier_bases: List[str]
    measured_bits: List[int]
    expected_bits: List[int]
    anomalies: List[str]
    elapsed_ms: float


class AttackRequest(BaseModel):
    attack_type: str = Field(..., description=f"One of {', '.join(ATTACK_TYPES)}")
    signature_id: Optional[str] = Field(
        None, description="Target signature; defaults to the most recent one"
    )
    tampered_message: Optional[str] = None
    channel_error_rate: float = Field(0.25, ge=0.0, le=1.0)


class AttackResponse(BaseModel):
    attack_id: str
    attack_type: str
    description: str
    target_signature_id: str
    presented_message: str
    attacker: str
    detected: bool
    expected_detection: bool
    correct_decision: bool
    indicators: List[str]
    verification: Dict[str, Any]
    elapsed_ms: float


class AttackTypeInfo(BaseModel):
    attack_type: str
    description: str
