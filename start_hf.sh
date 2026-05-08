#!/bin/bash
set -e
 
# Setup library databases
echo "[boot] Syncing library databases from HF Bucket..."
BUCKET_URL="https://huggingface.co/datasets/AADHIISHVAR/library_assist_alphav1.10-storage/resolve/main"
HF_TOKEN_HEADER="Authorization: Bearer $HF_TOKEN"

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

if [ "$downloaded_any" = false ]; then
  echo "[boot] No production data found in bucket. Seeding with mock data..."
  python3 /app/seed_db.py || echo "[warn] Seeding failed"
fi

for db in /app/ilibrary-database-all.db /app/combined-library.db; do
  if [ ! -f "$db" ]; then
    sqlite3 "$db" "VACUUM;"
  fi
done

echo "[boot] Starting AI sidecar (FastAPI) in background..."
cd /app/sidecar
DB_PATH=/app/library_database.db \
CATALOG_DB_PATH=/app/uniqueBooks.db \
HF_TOKEN=$HF_TOKEN \
python3 -m uvicorn main:app --host 0.0.0.0 --port 8001 > /app/sidecar.log 2>&1 &

# Setup DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf || echo "[warn] Failed to update resolv.conf"

# Permissions
chmod -R 777 /app/sidecar /app/backend

echo "[boot] Waiting for sidecar health check..."
max_retries=30
count=0
while ! curl -s http://localhost:8001/health > /dev/null; do
  sleep 3
  count=$((count+1))
  echo "[boot] Sidecar still starting... ($count/$max_retries)"
  if [ $count -ge $max_retries ]; then
    echo "[error] AI Sidecar timed out. Starting backend anyway to avoid 503..."
    break
  fi
done
echo "[boot] Sidecar ready (or timeout reached). Starting Axum Backend..."

cd /app/backend
PORT=7860 \
SIDECAR_URL=http://localhost:8001 \
./backend-bin

