@echo off
REM One-command demo launcher for Windows:
REM creates the Python environment if needed, starts the API, and serves the
REM prebuilt web UI at http://localhost:8000/
cd /d "%~dp0"

if not exist backend\.venv (
  echo Creating Python environment ^(first run only^)...
  py -3 -m venv backend\.venv || python -m venv backend\.venv
  backend\.venv\Scripts\python -m pip install --upgrade pip >nul
  backend\.venv\Scripts\pip install -r backend\requirements.txt
)

echo.
echo QuantumShield is starting on http://localhost:8000/  (close this window to stop)
echo.
start "" http://localhost:8000/

cd backend
..\backend\.venv\Scripts\python run.py
pause
