#!/bin/bash
set -e
 
# Setup library databases
echo "[boot] Syncing library databases from HF Bucket..."
BUCKET_URL="https://huggingface.co/datasets/AADHIISHVAR/library_assist_alphav1.10-storage/resolve/main"
HF_TOKEN_HEADER="Authorization: Bearer $HF_TOKEN"

# Track if we managed to download any real data
downloaded_any=false

for db in uniqueBooks.db library_database.db; do
  echo "[boot] Downloading $db..."
  if curl -f -H "$HF_TOKEN_HEADER" -L "$BUCKET_URL/$db" -o "/app/$db"; then
    echo "[boot] Successfully downloaded $db"
    downloaded_any=true
  else
    echo "[warn] Failed to download $db from bucket, creating empty fallback..."
    sqlite3 "/app/$db" "VACUUM;"
  fi
done

# Only seed with mock data if we didn't get any production databases from the bucket
if [ "$downloaded_any" = false ]; then
  echo "[boot] No production data found in bucket. Seeding with mock data for testing..."
  python3 /app/seed_db.py || echo "[warn] Seeding failed, continuing..."
fi

# Ensure other legacy databases exist as empty files if missing
for db in /app/ilibrary-database-all.db /app/combined-library.db; do
  if [ ! -f "$db" ]; then
    echo "[boot] Creating initial empty database: $db"
    sqlite3 "$db" "VACUUM;"
  fi
done

# Ensure other legacy databases exist as empty files if missing
for db in /app/ilibrary-database-all.db /app/combined-library.db; do
  if [ ! -f "$db" ]; then
    echo "[boot] Creating initial empty database: $db"
    sqlite3 "$db" "VACUUM;"
  fi
done
 
echo "[boot] Starting AI sidecar (FastAPI)..."
cd /app/sidecar
DB_PATH=/app/library_database.db \
CATALOG_DB_PATH=/app/uniqueBooks.db \
HF_TOKEN=$HF_TOKEN \
python3 -m uvicorn main:app --host 0.0.0.0 --port 8001 > /app/sidecar.log 2>&1 &
 
# Setup DNS for remote connectivity
echo "nameserver 8.8.8.8" > /etc/resolv.conf || echo "[warn] Failed to update resolv.conf"
 
# Fix permissions for sidecar and backend
echo "[boot] Fixing permissions for $(whoami)..."
chmod -R 777 /app/sidecar
chmod -R 777 /app/backend
 
# Seed library databases with mock data for testing
echo "[boot] Seeding library databases with mock data..."
python3 /app/seed_db.py || echo "[warn] Seeding failed, continuing..."
cp /app/library_database.db /app/uniqueBooks.db || true
 
# Wait for sidecar to be ready
echo "[boot] Waiting for services to wake up..."
max_retries=60
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
 
echo "[boot] ALL SERVICES DISCOVERED. Starting Axum Backend (Primary Gateway)..."
cd /app/backend
PORT=7860 \
SIDECAR_URL=http://localhost:8001 \
./backend-bin

