# QuantumShield — 5-minute demo script (SIH PS 26141)

## Before you present
1. `cd backend && .venv/bin/python run.py` (leave running).
2. `cd frontend && flutter run -d chrome` (or the Windows/Android build on a projector).
3. Run one sign + one verify + one attack beforehand so the Dashboard and Analytics
   aren't empty when you open them.

## The one-line pitch
"Classical digital signatures rest on math that a quantum computer breaks. We simulate a
teleportation-based **quantum** digital signature and detect forgery, replay, impersonation and
channel tampering using only **measurement statistics and a threshold rule** — no AI, no
black box, every number on screen is explainable."

## Walkthrough (follow the app's tabs in order)

**1. Dashboard (30s)** — "Live counts: signatures issued, verifications, threats detected.
Protocol parameters are shown too: 24 signature qubits, accept threshold τ = 0.15, QBER
tolerance 0.11. Those three numbers drive every decision you'll see."

**2. Sign (60s)** — Type a realistic message, e.g. *"Transfer 100 credits to Bob"*. Point at the
step-by-step trace and narrate one line of it:
- SHA-256 of the message → digest bits, so the signature is bound to *this exact text*.
- Alice and the verifier share Bell pairs `|Φ+> = (|00>+|11>)/√2`; the measured **QBER = 0.000**
  proves nobody touched the channel.
- Each digest bit becomes a Pauli eigenstate (`|0>,|1>,|+>,|->,|+i>,|-i>`) in a basis chosen by
  the shared key, then is **teleported**: Alice's Bell measurement gives 2 classical bits, the
  verifier applies the matching Pauli correction `I / X / Z / Y`.

**3. Verify (45s)** — Paste the signature id and the same message → **ACCEPT**, mismatch rate
0.0000 against threshold 0.150, 24 green per-qubit chips. Then **change one word** and verify
again → **REJECT** at ~0.42 mismatch. This single contrast is the most convincing moment of the
demo: the verdict is content-bound, not a constant.

**4. Attack Simulator (90s)** — Run all four, one per click, and read the number aloud:
| Attack | What the attacker does | Why we catch it |
|---|---|---|
| Forgery | signs without the shared key | must guess among 3 mutually unbiased bases → ~1/3 mismatch |
| Replay | reuses a valid signature on a new message | SHA-256 avalanche → ~50% mismatch |
| Impersonation | rogue key claims to be Alice | key mismatch → ~1/3 mismatch |
| Channel manipulation | intercept-resend + noise | QBER jumps above 0.11 |
Every one shows **THREAT DETECTED** with the indicators that triggered it.

**5. Threat Log (20s)** — "Everything is persisted in SQLite: type, timestamp, verdict,
mismatch rate, QBER. Expand a row for the full forensic detail. This is the audit trail a SOC
would consume."

**6. Analytics (45s)** — Three charts: mismatch trend with the dashed τ line (honest runs hug
zero, attacks sit far above), per-attack detection rate (100%), and the binomial
forgery-probability curve. "Security is a dial: at 24 qubits forgery is ~2%; at 96 it's ~3×10⁻⁵.
That's the accuracy/latency trade-off, and it's a formula, not a trained model."

## Kill-shot answers to likely judge questions

- **"Is this real quantum hardware?"** No — Qiskit Aer state-vector simulation, deliberately, so
  it runs on a laptop. The same circuits would run unmodified on hardware.
- **"Where's the AI?"** There is none, by design. Detection is `mismatch_rate > τ` or
  `QBER > 0.11`. Show the ~10 lines in `quantum_core/threshold.py`.
- **"Why can't an attacker just copy the signature?"** No-cloning theorem: no unitary copies an
  unknown state. To forward a qubit the attacker must measure it, which collapses it and shows up
  as a 1/3 mismatch rate. See SECURITY_ANALYSIS.md §5.
- **"What's the false-alarm rate?"** Shown live on Analytics: FAR and FRR, currently 0%, because
  τ = 0.15 sits between an honest 0 and an attacker's 1/3.
- **"How fast is it?"** O(n) tiny circuits, tens of milliseconds per sign/verify at n = 24;
  independent of message length (SHA-256 is constant time).
- **"Cross-platform?"** One Flutter codebase → Android APK, iOS, Windows, and web; the backend is
  a single FastAPI service.

## Fallback if the demo machine misbehaves
Kill the backend and show the Offline banner — graceful degradation is a feature, not a crash.
Then restart it and hit Retry. If Flutter won't launch, drive the same flow with the `curl`
commands in the README.
