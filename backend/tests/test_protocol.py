"""End-to-end tests for the quantum core, attack simulator and REST API."""

from __future__ import annotations

import os
import tempfile

import pytest
from fastapi.testclient import TestClient

from attacks import AttackSimulator
from quantum_core.pauli import basis_schedule, correction_for
from quantum_core.signature import QDSProtocol, digest_bits
from quantum_core.threshold import forgery_probability


@pytest.fixture(scope="module")
def protocol() -> QDSProtocol:
    return QDSProtocol()


def test_correction_table():
    assert correction_for(0, 0) == "I"
    assert correction_for(0, 1) == "X"
    assert correction_for(1, 0) == "Z"
    assert correction_for(1, 1) == "Y"


def test_basis_schedule_is_deterministic():
    key = [0, 1] * 24
    assert basis_schedule(key, 10) == basis_schedule(key, 10)


def test_digest_avalanche():
    a = digest_bits("transfer 100", 64)
    b = digest_bits("transfer 101", 64)
    drift = sum(x != y for x, y in zip(a, b)) / 64
    assert 0.25 < drift < 0.75


def test_honest_signature_is_accepted(protocol: QDSProtocol):
    key = protocol.generate_key()
    sig = protocol.sign("hello quantum", key["bits"], key["key_id"])
    result = protocol.verify(sig, "hello quantum", key["bits"])
    assert result.decision.accepted
    assert result.stats.mismatch_rate == 0.0


def test_attacks_are_detected(protocol: QDSProtocol):
    simulator = AttackSimulator(protocol)
    key = protocol.generate_key()
    sig = protocol.sign("pay 100 to bob", key["bits"], key["key_id"])
    for attack in ("forgery", "replay", "impersonation", "channel_manipulation"):
        report = simulator.run(attack, sig, key["bits"])
        assert report.detected, f"{attack} slipped through: {report.as_dict()}"
    baseline = simulator.run("baseline", sig, key["bits"])
    assert not baseline.detected


def test_forgery_probability_decays():
    assert forgery_probability(8) > forgery_probability(24) > forgery_probability(48)
    assert forgery_probability(24) < 0.05


@pytest.fixture()
def client():
    with tempfile.TemporaryDirectory() as tmp:
        os.environ["QDS_DB_PATH"] = os.path.join(tmp, "test.db")
        import importlib

        from api import main as main_module

        importlib.reload(main_module)
        with TestClient(main_module.app) as c:
            yield c
        os.environ.pop("QDS_DB_PATH", None)


def test_api_full_flow(client):
    signed = client.post("/sign", json={"message": "invoice #42"}).json()
    assert signed["length"] > 0

    verified = client.post("/verify", json={"signature_id": signed["signature_id"]}).json()
    assert verified["verdict"] == "ACCEPT"

    for attack in ("forgery", "replay", "impersonation", "channel_manipulation"):
        res = client.post(
            "/simulate-attack",
            json={"attack_type": attack, "signature_id": signed["signature_id"]},
        ).json()
        assert res["detected"] is True

    metrics = client.get("/metrics").json()
    assert metrics["security"]["detection_accuracy"] == 1.0
    assert metrics["totals"]["attacks"] == 4

    logs = client.get("/logs").json()["events"]
    assert len(logs) == 6  # 1 sign + 1 verify + 4 attacks
