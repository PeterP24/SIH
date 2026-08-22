---
name: testing-quantum-shield
description: How to run and UI-test the QuantumShield demo (FastAPI + Qiskit Aer backend, Flutter client) end to end — starting services, reaching each screen, and the golden sign → verify → attack → log → analytics flow.
---

# Testing QuantumShield end to end

## Bring up the stack

Backend (FastAPI + Qiskit Aer, venv already provisioned):

```bash
cd backend && nohup .venv/bin/python run.py > /tmp/backend.log 2>&1 &
curl -s localhost:8000/health   # {"status":"ok",...}
```

Frontend — the **web build is by far the fastest target** for UI testing (Android
emulator is not needed):

```bash
export PATH=$PATH:/home/ubuntu/flutter/bin
cd frontend && nohup flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0 > /tmp/flutterweb.log 2>&1 &
# wait for "lib/main.dart is being served at http://0.0.0.0:8080" (~60s first build)
```

Then open `http://localhost:8080` in Chrome and maximize with
`wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz`.
No auth/secrets are required. Backend CORS is permissive.
Default backend URL on web/desktop is `http://localhost:8000` (Android emulator
uses `10.0.2.2:8000`); it is editable on the Settings screen and persisted in
SharedPreferences.

## Navigating the UI

With a window wider than 820px a left `NavigationRail` shows:
Dashboard, Sign, Verify, Attacks, Threat log, Analytics, Settings.
Below 820px these become a bottom `NavigationBar` and Settings moves to the
app-bar gear icon. The app-bar chip on the right reads "Backend online" /
"Offline".

Golden path:
1. **Sign** → edit "Message", click **Generate quantum signature** → note the
   `sig-xxxxxxxx` id; step tiles show the per-qubit teleportation trace.
2. **Verify** → the id/message are prefilled from the last signature → **Run
   projective measurement** → expect `SIGNATURE ACCEPTED`, mismatch 0.000.
   Editing the message to anything else must flip it to `SIGNATURE REJECTED`
   (mismatch ≈ 0.3–0.5) — good adversarial check that verification is
   content-bound.
3. **Attacks** → target signature id prefills → click each chip (Forgery,
   Replay, Impersonation, Channel Manipulation, Baseline) then **Launch
   attack**. Attacks should read `THREAT DETECTED`; Baseline should read
   `NO THREAT DETECTED` and still show a green banner (banner colour tracks
   `detected == expectedDetection`, not `detected`).
4. **Threat log** → ALL/SIGN/VERIFY/ATTACK filter chips; expand a row for
   signature id, QBER, indicators, anomalies.
5. **Analytics** → mismatch-rate line chart (only populated after verify/attack
   runs), per-attack bar chart (only shows attack types that have actually been
   run — `baseline` is absent until a baseline run exists), and a client-side
   forgery-probability curve that renders even with no data.

Cross-check any on-screen number against `curl -s localhost:8000/metrics`
(`totals`, `per_attack`, `mismatch_series`) — the Dashboard "Verifications" card
is `verifications + attacks`, not `verifications`.

## Known pitfalls

- **Offline handling is broken on web.** `ApiService._send`
  (`frontend/lib/services/api_service.dart`) only catches `SocketException`
  (dart:io), but on Flutter web `package:http` throws `http.ClientException`
  when the connection is refused. That exception escapes the screens'
  `on ApiException` handlers, so with the backend stopped the UI hangs
  (Dashboard renders blank, Sign is stuck on "Teleporting qubits…") and the
  badge stays "Backend online". If you test offline behaviour and see a hang
  rather than an error banner, this is likely the cause; a workaround for
  exercising the error UI is to trigger an HTTP error instead (e.g. verify a
  nonexistent signature id → 404 → ErrorPanel + "Offline" badge), or point the
  Settings backend URL at a bad host. This may be fixed by catching
  `http.ClientException` / a bare `catch`.
- Typing into Flutter-web `TextField`s via xdotool can drop the first
  character after a `ctrl+a`; always screenshot and read back the field before
  asserting on hashes or ids.
- Timestamps in the Threat log are local time; sort is newest-first.

## Devin Secrets Needed

None — everything runs locally with no credentials.
