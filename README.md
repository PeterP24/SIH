# QuantumShield — Quantum-Inspired Cyber Threat Detection for Digital Signature Security

Smart India Hackathon — Problem Statement ID **26141**.

A **simulation-based** framework (Qiskit Aer, no real quantum hardware) that implements a
teleportation-based **Quantum Digital Signature (QDS)** protocol and detects attacks against it
using **only quantum measurement statistics and mathematical threshold rules — no AI/ML anywhere
in the detection path**.

```
quantum-shield/
├── backend/            FastAPI + Qiskit Aer + SQLite
│   ├── quantum_core/   Bell states, teleportation, Pauli corrections, measurement, thresholds
│   ├── attacks/        forgery / replay / impersonation / channel manipulation / baseline
│   ├── api/            REST layer, schemas, SQLite storage, metrics
│   └── tests/          protocol + REST end-to-end tests
├── frontend/           Flutter app (Android, iOS, Windows, web/desktop for demos)
│   └── lib/            screens/, services/, models/, state/, theme/, widgets/
├── webapp/             prebuilt web UI (index.html) served by the backend
├── start.sh            one-command launcher (macOS/Linux)
└── start.bat           one-command launcher (Windows)
```

## Quick start (no Flutter needed)

Only Python 3.10+ is required — the compiled web UI ships in `webapp/`.

- **Windows:** double-click `start.bat`
- **macOS/Linux:** `./start.sh`

The first run creates a virtualenv and installs dependencies (a minute or two), then the
app opens at **http://localhost:8000/** — the UI and the API are served from the same
address, so there is nothing to configure. Press Ctrl+C (or close the window) to stop.

## How the protocol works (demo talking points)

1. **Entangled key distribution** — Alice and each verifier share Bell pairs
   `|Φ+> = (|00> + |11>)/√2`; correlated measurements give a shared secret key and a measured
   QBER. Chunked into small circuits so it runs instantly on a laptop.
2. **Digest binding** — the message is hashed with SHA-256; digest bits select the Pauli
   eigenstates (`|0>,|1>,|+>,|->,|+i>,|-i>`) to be signed.
3. **Teleportation** — each signature qubit is teleported to the verifier: Bell measurement by
   Alice, classical `(m1, m0)` bits, and the verifier's Pauli correction
   `(0,0)→I, (0,1)→X, (1,0)→Z, (1,1)→Y`.
4. **Projective verification** — the verifier re-measures in the key-scheduled Pauli basis and
   compares against the expected eigenvalue.
5. **Threshold decision** — accept iff `mismatch_rate ≤ τ` (default `0.15`) and `QBER ≤ 0.11`.
   An attacker guessing bases mismatches at ~`1/3`, so detection is statistical, not learned.

See [SECURITY_ANALYSIS.md](SECURITY_ANALYSIS.md) for the forgery-probability formulas and the
no-cloning argument.

## Backend — run locally

Requires Python 3.10+.

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python run.py            # serves http://0.0.0.0:8000
```

Tests:

```bash
cd backend && .venv/bin/python -m pytest tests -q
```

### Endpoints

| Method | Path               | Purpose |
|--------|--------------------|---------|
| GET    | `/health`          | status + active protocol parameters |
| POST   | `/sign`            | sign a message, returns signature + step-by-step teleportation trace |
| POST   | `/verify`          | verify a signature, returns ACCEPT/REJECT + measurement statistics |
| POST   | `/simulate-attack` | run `forgery`, `replay`, `impersonation`, `channel_manipulation` or `baseline` |
| GET    | `/metrics`         | detection accuracy, FAR, FRR, timings, forgery probability |
| GET    | `/logs`            | signing / verification / attack event history |
| GET    | `/signatures`      | stored signatures |
| GET    | `/attack-types`    | attack catalogue for the UI |

Quick end-to-end check:

```bash
curl -s -X POST localhost:8000/sign -H 'Content-Type: application/json' \
  -d '{"message":"Transfer 100 credits to Bob","signer":"alice"}'
curl -s -X POST localhost:8000/verify -H 'Content-Type: application/json' \
  -d '{"signature_id":"<id>","message":"Transfer 100 credits to Bob"}'
curl -s -X POST localhost:8000/simulate-attack -H 'Content-Type: application/json' \
  -d '{"attack_type":"forgery","signature_id":"<id>"}'
curl -s localhost:8000/metrics
```

### Configuration (environment variables)

| Variable | Default | Meaning |
|----------|---------|---------|
| `QDS_SIGNATURE_LENGTH` | `24` | signature qubits per message |
| `QDS_THRESHOLD` | `0.15` | mismatch-rate accept threshold τ |
| `QDS_QBER_THRESHOLD` | `0.11` | channel QBER alarm threshold |
| `QDS_DB_PATH` | `backend/data/qds.db` | SQLite location |
| `QDS_HOST` / `QDS_PORT` | `0.0.0.0` / `8000` | bind address |

## Frontend — run and build

Requires Flutter 3.29+ (developed on 3.47 / Dart 3.13).

```bash
cd frontend
flutter pub get
flutter run                      # any connected device
flutter build apk                # Android .apk
flutter build windows            # Windows .exe (run on Windows)
flutter build ipa                # iOS (run on macOS with Xcode)
```

Screens: Dashboard, Sign, Verify, Attack Simulator, Threat Log, Analytics, Settings.

### Connecting the app to the backend

The base URL is stored with `shared_preferences` and editable in **Settings → Backend URL**
(with a "Test connection" button). Defaults:

- Android emulator: `http://10.0.2.2:8000`
- iOS simulator / Windows / desktop / web: `http://localhost:8000`
- Physical device: use your laptop's LAN IP, e.g. `http://192.168.1.20:8000`, and start the
  backend with `QDS_HOST=0.0.0.0` (the default).

The backend enables permissive CORS so the web build also works during demos. Every screen has
loading, error and offline states; when the backend is unreachable the app shows an offline
banner instead of failing silently.

## Constraints honoured

- Qiskit Aer simulation only — no quantum hardware, no cloud provider credentials.
- No AI/ML libraries or models: detection is `mismatch_rate` vs τ plus QBER rules.
- Small circuits (≤ 16 qubits per run) so a full sign+verify takes tens of milliseconds.
