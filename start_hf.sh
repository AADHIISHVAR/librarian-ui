#!/bin/bash
set -e

echo "[boot] Starting AI sidecar (FastAPI)..."
cd /app/sidecar
DB_PATH=/app/library_database.db \
CATALOG_DB_PATH=/app/uniqueBooks.db \
HF_TOKEN=$HF_TOKEN \
python3 -m uvicorn main:app --host 0.0.0.0 --port 8001 > /app/sidecar.log 2>&1 &

echo "[boot] Starting Evolution WhatsApp API..."
cd /app/evolution

# Initialize SQLite database if provider is sqlite
if [ "$DATABASE_PROVIDER" = "sqlite" ]; then
  echo "[boot] Initializing SQLite database for Evolution API..."
  npx prisma db push --schema ./prisma/sqlite-schema.prisma --accept-data-loss
fi

# Evolution API is a standalone Node.js service
npm run start:prod > /app/evolution.log 2>&1 &

# Wait for sidecar and evolution to be ready
echo "[boot] Waiting for services to wake up..."
max_retries=30
count=0
while ! curl -s http://localhost:8001/health > /dev/null; do
  sleep 2
  count=$((count+1))
  if [ $count -ge $max_retries ]; then
    echo "[error] AI Sidecar failed to start"
    exit 1
  fi
done
echo "[boot] AI Sidecar ready ✅"

count=0
while ! curl -s http://localhost:8080/instance/fetchInstances -H "apikey: hellowork.1234" > /dev/null; do
  sleep 2
  count=$((count+1))
  if [ $count -ge $max_retries ]; then
    echo "[error] Evolution API failed to start"
    exit 1
  fi
done
echo "[boot] Evolution API ready ✅"

echo "[boot] Starting Axum Backend (Primary Gateway)..."
cd /app/backend
PORT=7860 \
SIDECAR_URL=http://localhost:8001 \
./backend-bin
