#!/usr/bin/env bash
# One-command demo launcher for macOS/Linux:
# creates the Python environment if needed, starts the API, and serves the
# prebuilt web UI at http://localhost:8000/
set -e
cd "$(dirname "$0")"

PY=${PYTHON:-python3}
if [ ! -d backend/.venv ]; then
  echo "Creating Python environment (first run only)..."
  "$PY" -m venv backend/.venv
  backend/.venv/bin/pip install --upgrade pip >/dev/null
  backend/.venv/bin/pip install -r backend/requirements.txt
fi

echo
echo "QuantumShield is starting on http://localhost:8000/  (Ctrl+C to stop)"
echo

(sleep 4; (command -v xdg-open >/dev/null && xdg-open http://localhost:8000/) \
  || (command -v open >/dev/null && open http://localhost:8000/) || true) &

cd backend
exec .venv/bin/python run.py
