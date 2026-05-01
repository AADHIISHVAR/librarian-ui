#!/bin/bash
set -e

PROJECT_ROOT=$(pwd)
VENV_PATH="$PROJECT_ROOT/venv"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Librarian AI — Starting up"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Function to kill child processes on exit
cleanup() {
    echo ""
    echo "Stopping services..."
    kill $SIDECAR_PID $BACKEND_PID $FRONTEND_PID 2>/dev/null || true
    exit
}

trap cleanup SIGINT SIGTERM

# Clear existing ports
echo "[0/3] Clearing existing ports (8001, 7860, 8080)..."
fuser -k 8001/tcp || true
fuser -k 7860/tcp || true
fuser -k 8080/tcp || true
pkill -f "uvicorn" || true
pkill -f "library-backend" || true
pkill -f "trunk" || true
sleep 1

# Ensure venv exists
if [ ! -d "$VENV_PATH" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_PATH"
fi

# Clear old logs
rm -f sidecar.log backend.log frontend.log
touch sidecar.log backend.log frontend.log

# 1 — Python sidecar
echo "[1/3] Starting Python sidecar..."
cd sidecar
"$VENV_PATH/bin/pip" install -r requirements.txt -q
nohup "$VENV_PATH/bin/python3" -m uvicorn main:app --port 8001 --host 0.0.0.0 > ../sidecar.log 2>&1 &
SIDECAR_PID=$!
cd ..
echo "      Sidecar PID: $SIDECAR_PID"

# 2 — Axum backend
echo "[2/3] Starting Axum backend..."
cd backend
export DATABASE_URL="sqlite://$PROJECT_ROOT/library_database.db"
nohup cargo run --release > ../backend.log 2>&1 &
BACKEND_PID=$!
cd ..
echo "      Backend PID: $BACKEND_PID"

# 3 — Leptos frontend
echo "[3/3] Starting Leptos frontend..."
cd frontend
nohup trunk serve --port 8080 --address 0.0.0.0 > ../frontend.log 2>&1 &
FRONTEND_PID=$!
cd ..
echo "      Frontend PID: $FRONTEND_PID"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Services are running"
echo "  AI Sidecar:  http://localhost:8001"
echo "  Backend:     http://localhost:7860"
echo "  Frontend:    http://localhost:8080"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Streaming logs below (Ctrl+C to stop all services)..."
echo ""

# Tail all logs to terminal
tail -f sidecar.log backend.log frontend.log
