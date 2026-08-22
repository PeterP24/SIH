"""Security and performance metrics derived from the event log.

Definitions
-----------
Let the ground truth of every verification/attack run be "malicious" (an attack
was actually mounted) or "honest".

    TP: malicious run rejected            FN: malicious run accepted
    TN: honest run accepted               FP: honest run rejected

    detection_accuracy      = (TP + TN) / (TP + TN + FP + FN)
    false_acceptance_rate   = FN / (TP + FN)     -- forged signature accepted
    false_rejection_rate    = FP / (TN + FP)     -- honest signature rejected
    detection_rate (recall) = TP / (TP + FN)

Theoretical forgery probability comes from the binomial tail in
``quantum_core.threshold.forgery_probability``; the empirical false-acceptance
rate above is its measured counterpart.
"""

from __future__ import annotations

from statistics import mean
from typing import Any, Dict, List

from quantum_core.threshold import (
    ATTACKER_MISMATCH_RATE,
    DEFAULT_THRESHOLD,
    forgery_probability,
)


def _safe_div(num: float, den: float) -> float:
    return num / den if den else 0.0


def compute_metrics(
    rows: List[Dict[str, Any]], signature_length: int, threshold: float = DEFAULT_THRESHOLD
) -> Dict[str, Any]:
    """Aggregate the event log into security + performance metrics."""
    runs = [r for r in rows if r["event_type"] in ("verify", "attack")]
    sign_rows = [r for r in rows if r["event_type"] == "sign"]

    tp = fn = tn = fp = 0
    for r in runs:
        malicious = bool(r.get("expected_detection"))
        rejected = r.get("verdict") == "REJECT"
        if malicious and rejected:
            tp += 1
        elif malicious and not rejected:
            fn += 1
        elif not malicious and rejected:
            fp += 1
        else:
            tn += 1

    per_attack: Dict[str, Dict[str, Any]] = {}
    for r in runs:
        if r["event_type"] != "attack":
            continue
        key = r.get("subject") or "unknown"
        bucket = per_attack.setdefault(
            key, {"runs": 0, "detected": 0, "mismatch_rates": []}
        )
        bucket["runs"] += 1
        bucket["detected"] += int(bool(r.get("detected")))
        if r.get("mismatch_rate") is not None:
            bucket["mismatch_rates"].append(r["mismatch_rate"])
    for key, bucket in per_attack.items():
        rates = bucket.pop("mismatch_rates")
        bucket["detection_rate"] = round(_safe_div(bucket["detected"], bucket["runs"]), 4)
        bucket["mean_mismatch_rate"] = round(mean(rates), 4) if rates else 0.0

    sign_times = [r["elapsed_ms"] for r in sign_rows if r.get("elapsed_ms")]
    verify_times = [r["elapsed_ms"] for r in runs if r.get("elapsed_ms")]
    mismatch_series = [
        {"t": r["created_at"], "value": r["mismatch_rate"], "type": r.get("subject")}
        for r in runs
        if r.get("mismatch_rate") is not None
    ]

    return {
        "totals": {
            "signatures": len(sign_rows),
            "verifications": len([r for r in runs if r["event_type"] == "verify"]),
            "attacks": len([r for r in runs if r["event_type"] == "attack"]),
            "threats_detected": sum(1 for r in runs if r.get("detected")),
            "true_positives": tp,
            "false_negatives": fn,
            "true_negatives": tn,
            "false_positives": fp,
        },
        "security": {
            "detection_accuracy": round(_safe_div(tp + tn, tp + tn + fp + fn), 4),
            "detection_rate": round(_safe_div(tp, tp + fn), 4),
            "false_acceptance_rate": round(_safe_div(fn, tp + fn), 4),
            "false_rejection_rate": round(_safe_div(fp, tn + fp), 4),
            "theoretical_forgery_probability": forgery_probability(
                signature_length, threshold
            ),
            "attacker_expected_mismatch_rate": round(ATTACKER_MISMATCH_RATE, 4),
            "threshold": threshold,
            "signature_length_qubits": signature_length,
        },
        "performance": {
            "avg_sign_ms": round(mean(sign_times), 3) if sign_times else 0.0,
            "avg_verify_ms": round(mean(verify_times), 3) if verify_times else 0.0,
            "max_verify_ms": round(max(verify_times), 3) if verify_times else 0.0,
            # Circuit cost: 3 qubits and a constant gate count per signature
            # qubit -> O(n) simulated gates, linear in the signature length.
            "complexity": "O(n) circuits of 3 qubits each (n = signature length)",
            "qubits_per_teleportation": 3,
        },
        "per_attack": per_attack,
        "mismatch_series": mismatch_series[-100:],
    }
