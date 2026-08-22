# Security Analysis — QuantumShield QDS

This document summarises the mathematics behind the accept/reject rule, the forgery-probability
formulas used in the code, and why the **no-cloning theorem** underlies the detection guarantees.
All quantities below are computed in `backend/quantum_core/threshold.py` and
`backend/api/metrics.py`.

## 1. Protocol recap

For a message `m`, the signer derives `n` digest bits from `SHA-256(m)`. Bit `i` is encoded as a
Pauli eigenstate in a basis `b_i ∈ {X, Y, Z}` chosen by the entanglement-derived shared key:

| basis | eigenstate for bit 0 | eigenstate for bit 1 |
|-------|----------------------|----------------------|
| Z     | `|0>`                | `|1>`                |
| X     | `|+>`                | `|->`                |
| Y     | `|+i>`               | `|-i>`               |

Each state is teleported through a Bell pair `|Φ+> = (|00> + |11>)/√2`. Alice's Bell measurement
yields classical bits `(m1, m0)`; the verifier applies the Pauli correction
`I, X, Z, Y` for `(0,0), (0,1), (1,0), (1,1)` respectively, then measures projectively in `b_i`
using the projectors

```
P_+ = (I + P)/2 ,  P_- = (I - P)/2 ,  P ∈ {X, Y, Z}
```

An honest run reproduces the digest bit deterministically (up to channel noise), so the mismatch
rate is ≈ 0.

## 2. Why an attacker mismatches at rate 1/3

The three Pauli bases are **mutually unbiased**: for eigenstates `|a>` of `P` and `|b>` of `Q`
with `P ≠ Q`, `|<a|b>|² = 1/2`. An attacker who does not hold the shared key does not know `b_i`
and must guess:

- with probability `1/3` the guess is correct → the forged qubit passes;
- with probability `2/3` the guess is wrong → the verifier's outcome is uniformly random and
  therefore wrong with probability `1/2`.

Per-qubit mismatch probability for an attacker:

```
p_att = (2/3) · (1/2) = 1/3
```

This constant is `ATTACKER_MISMATCH_RATE = 1/3` in the code. An honest signer has `p_hon ≈ 0`
(plus channel QBER).

## 3. Accept/reject rule (no ML)

The verifier accepts iff

```
mismatch_rate = (# mismatched qubits) / n  ≤  τ        (default τ = 0.15)
      and      QBER of the entangled key   ≤  Q_max    (default 0.11)
```

Both are fixed statistical thresholds — no training, no model, no inference. `τ` sits between
`p_hon ≈ 0` and `p_att = 1/3`, giving separation on both sides.

## 4. Forgery probability

A forger succeeds only if at most `⌊τn⌋` of its `n` qubits mismatch, where each mismatch is an
independent Bernoulli trial with `p = 1/3`. Hence the binomial lower tail:

```
P_forge(n, τ) = Σ_{k=0}^{⌊τ·n⌋} C(n, k) · (1/3)^k · (2/3)^(n−k)
```

Implemented as `forgery_probability(n, τ)`. Sample values for `τ = 0.15`:

| n  | ⌊τn⌋ | P_forge  |
|----|------|----------|
| 8  | 1    | ≈ 1.9e-1 |
| 16 | 2    | ≈ 5.9e-2 |
| 24 | 3    | ≈ 2.0e-2 |
| 48 | 7    | ≈ 2.9e-3 |
| 96 | 14   | ≈ 2.7e-5 |

The tail decays exponentially in `n` (Chernoff bound `P_forge ≤ exp(−n·D(τ ‖ 1/3))` with `D` the
binary KL divergence), so the security parameter is simply the signature length — the default of
24 qubits keeps a live demo fast while already giving ~2% forgery probability, and raising `n`
to 96 pushes it below `10⁻⁵`.

## 5. Why no-cloning is the foundation

The no-cloning theorem states there is no unitary `U` with `U(|ψ>|0>) = |ψ>|ψ>` for all `|ψ>`.
Consequences used here:

1. **A signature cannot be copied.** An eavesdropper who intercepts teleported signature qubits
   cannot duplicate them to keep one copy and forward another; forwarding requires measuring,
   which is irreversible.
2. **Measurement disturbs.** Intercept-resend in an unknown Pauli basis collapses the state; the
   resent qubit mismatches with probability `1/3` per qubit, exactly the attacker rate above. So
   eavesdropping is *statistically visible* as an elevated mismatch rate/QBER, not merely
   suspected.
3. **Keys cannot be harvested.** The Bell-pair key is created by correlated measurement, not
   transmitted, so there is no classical key material in flight to steal or clone. Interference
   raises the QBER above `Q_max`.

Classical signatures rest on computational hardness (factoring, discrete log) — both broken by
Shor's algorithm on a large quantum computer. Here, security rests on physical law: the attacker's
`1/3` mismatch rate holds regardless of computational power.

## 6. Attack models and expected detection

| Attack | Simulation | Detection signal |
|--------|------------|------------------|
| Forgery | attacker signs with random (non-shared) key material | mismatch ≈ 1/3 > τ |
| Replay | valid signature replayed on a modified message | SHA-256 digest bits change (avalanche) → ~50% of qubits mismatch |
| Impersonation | rogue key claims Alice's identity | key mismatch → mismatch ≈ 1/3 |
| Channel manipulation | intercept-resend + injected depolarising noise | elevated mismatch rate and QBER > `Q_max` |

## 7. Reported metrics

`GET /metrics` aggregates over the logged runs:

```
detection accuracy      = (TP + TN) / (TP + TN + FP + FN)
false acceptance rate   = FN / (TP + FN)     (attacks wrongly accepted)
false rejection rate    = FP / (TN + FP)     (honest runs wrongly rejected)
```

Complexity: signing and verification are `O(n)` single-qubit-plus-Bell-pair circuits of ≤ 3
qubits each, so runtime is linear in the signature length and independent of message size (the
message only enters through a constant-time SHA-256 digest). Typical laptop timings are tens of
milliseconds per sign or verify at `n = 24`.
