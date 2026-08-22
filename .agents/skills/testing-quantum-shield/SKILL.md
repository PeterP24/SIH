---
name: testing-quantum-shield
description: How to run and UI-test the QuantumShield demo (FastAPI + Qiskit Aer backend, Flutter client) end to end — starting services (dev server or the packaged self-hosted bundle), reaching each screen, the golden sign → verify → attack → log → analytics flow, and how to drive the Flutter web UI over CDP when computer-use is unavailable.
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

## Testing the packaged bundle (what users actually download)

The distributable serves a **prebuilt Flutter web bundle from the API itself**, so
there is no separate web server and no URL configuration:

```bash
cd /path/to/unzipped/quantum-shield && ./start.sh   # start.bat on Windows
# creates backend/.venv + pip installs on first run, then serves everything on :8000
curl -s localhost:8000/health && curl -so /dev/null -w '%{http_code}\n' localhost:8000/
```

`backend/api/main.py` `_web_dir()` looks for `$QDS_WEB_DIR`, then `<repo>/webapp`,
then `<repo>/frontend/build/web`, and mounts it with
`app.mount("/", StaticFiles(..., html=True))`. That mount is registered **after**
the API routes, so `/health`, `/sign`, `/metrics` etc. are not shadowed — verify
both a static path and an API path return the right content types when testing
packaging changes.

On web `AppConfig.defaultBaseUrl` is `Uri.base.origin`, i.e. the UI talks to
whatever origin served it. **To actually prove this rather than a hardcoded
`localhost:8000`, load the app via a different origin string for the same server
(`http://127.0.0.1:8000/`) and confirm the API calls go to `127.0.0.1`, not
`localhost`.** The Settings "Base URL" field is not a reliable read-out here: its
helper text always shows the static `Android emulator … · desktop …` hint, and
with CanvasKit the field's value is not mirrored into the DOM — use the network
log instead.

When testing the package, make sure no stale `flutter run -d web-server` on :8080
is around, and confirm the :8000 listener is really the unzipped copy
(`ls -l /proc/$(lsof -ti:8000)/cwd`).

## Driving the UI when computer-use / recording is unavailable

The GUI desktop session can die (symptoms: `computer` actions fail with
"enigo init failed: no connection could be established", `recording_start` fails
with "FFmpeg exited immediately", `/tmp/.X11-unix/` empty, no Chrome process).
Starting your own `Xvfb :0` restores an X server but does **not** make the
`computer` tool re-attach, so GUI testing stays blocked and you must say so in the
report. A workable fallback that still exercises the real bundle in a real Chrome:

```bash
google-chrome --headless=new --no-sandbox --disable-gpu \
  --remote-debugging-port=9222 --user-data-dir=/tmp/cdp-profile --window-size=1600,1000 about:blank
```

Then drive it over CDP (`websockets` is available system-wide; note `/json/new`
requires **PUT** on modern Chrome). Keys to making a CanvasKit Flutter app
inspectable:

- Flutter renders to WebGL, so `document.body.innerText` is empty and there are
  no ordinary DOM nodes. Enable the accessibility tree first:
  `document.querySelector('flt-semantics-placeholder').click()`.
- After that, `document.querySelectorAll('flt-semantics')` exposes every label;
  `getBoundingClientRect()` gives coordinates you can click with
  `Input.dispatchMouseEvent` (mousePressed + mouseReleased).
- Nav rail items have labels like `"Sign\nTab 2 of 7"` — match exactly to avoid
  hitting the "Sign a message" heading or the "Generate quantum signature" button.
- The semantics tree repeats ancestor labels, so de-duplicate before reading.
- `Page.captureScreenshot` still yields real PNGs for artifacts, but headless
  Chrome logs benign `Automatic fallback to software WebGL` warnings — ignore
  those when checking for console-fatal errors.
- Backend work is genuinely slow (Qiskit Aer): allow ~10–15s after clicking
  Generate/Verify/Launch attack before reading the result.

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

- **Offline handling depends on `_send` catching transport errors generically.**
  On Flutter web `package:http` throws `http.ClientException` (not
  `SocketException`) when the connection is refused, so `ApiService._send`
  (`frontend/lib/services/api_service.dart`) must have a bare `catch (_)`
  fallback mapping it to `ApiException`. Without it the exception escapes the
  screens' `on ApiException` handlers and the UI hangs forever (Dashboard
  blank, Sign stuck on "Teleporting qubits…") with the badge still reading
  "Backend online". To test offline behaviour: `pkill -f run.py`, then
  re-navigate to Dashboard — you should see an ErrorPanel reading
  "Cannot reach backend at http://localhost:8000. Is it running?" with a Retry
  button and a red "Offline" badge. If you instead see a hang, that catch
  clause has regressed. A separate way to exercise the error UI without
  stopping the backend is to trigger an HTTP error (verify a nonexistent
  signature id → 404 → ErrorPanel) or point the Settings backend URL at a bad
  host.
- Flutter web has **no hot reload from an outside process**; after changing
  Dart code, kill and relaunch `flutter run -d web-server` (~60s rebuild) and
  hard-reload the browser tab (ctrl+shift+r), otherwise you are testing stale
  JS.
- Typing into Flutter-web `TextField`s via xdotool can drop the first
  character after a `ctrl+a`; always screenshot and read back the field before
  asserting on hashes or ids.
- Timestamps in the Threat log are local time; sort is newest-first.

## Devin Secrets Needed

None — everything runs locally with no credentials.
