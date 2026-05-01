#!/bin/bash
set -e

PROJECT_ROOT=$(pwd)
VENV_PATH="$PROJECT_ROOT/venv"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Librarian AI — Starting up"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Ensure venv exists
if [ ! -d "$VENV_PATH" ]; then
    echo "[0/3] Creating virtual environment..."
    python3 -m venv "$VENV_PATH"
fi

# 1 — Python sidecar
echo "[1/3] Starting Python sidecar..."
cd sidecar
"$VENV_PATH/bin/pip" install -r requirements.txt -q
# Ensure uvicorn runs in background and stays there
nohup "$VENV_PATH/bin/python3" -m uvicorn main:app --port 8001 --host 0.0.0.0 > sidecar.log 2>&1 &
SIDECAR_PID=$!
cd ..
echo "      Sidecar PID: $SIDECAR_PID"

# 2 — Axum backend
echo "[2/3] Starting Axum backend..."
cd backend
export DATABASE_URL="sqlite://$PROJECT_ROOT/library_database.db"
nohup cargo run --release > backend.log 2>&1 &
BACKEND_PID=$!
cd ..
echo "      Backend PID: $BACKEND_PID"

# 3 — Leptos frontend
echo "[3/3] Starting Leptos frontend..."
cd frontend
# Trunk serve handles its own hot-reloading
nohup trunk serve --port 8080 > frontend.log 2>&1 &
FRONTEND_PID=$!
cd ..
echo "      Frontend PID: $FRONTEND_PID"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Services are running in background"
echo "  AI Sidecar:  http://localhost:8001"
echo "  Backend:     http://localhost:3000"
echo "  Frontend:    http://localhost:8080"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
