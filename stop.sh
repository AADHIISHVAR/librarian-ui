#!/bin/bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Librarian AI — Stopping"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "[1/3] Stopping services by port..."
fuser -k 8001/tcp 2>/dev/null || true
fuser -k 3000/tcp 2>/dev/null || true
fuser -k 8080/tcp 2>/dev/null || true

echo "[2/3] Cleaning up background processes..."
pkill -f "uvicorn" || true
pkill -f "library-backend" || true
pkill -f "trunk" || true

echo "[3/3] Services stopped successfully. ✅"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
