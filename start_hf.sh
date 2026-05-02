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
  
  # Ensure the directory exists
  mkdir -p prisma
  
  # AGGRESSIVE CLEANUP: 
  # If evolution.db exists, check if it's a valid SQLite file.
  # If it's not (e.g. 0 bytes or corrupted), delete it.
  DB_FILE="prisma/evolution.db"
  if [ -f "$DB_FILE" ]; then
    # Use sqlite3 to check integrity or just check size
    if [ ! -s "$DB_FILE" ]; then
        echo "[boot] $DB_FILE is 0 bytes. Deleting..."
        rm "$DB_FILE"
    elif ! sqlite3 "$DB_FILE" "PRAGMA integrity_check;" > /dev/null 2>&1; then
        echo "[boot] $DB_FILE is corrupted. Deleting..."
        rm "$DB_FILE"
    fi
  fi
  
  # Set DATABASE_URL explicitly for the Prisma command to use the absolute path
  export DATABASE_URL="file:/app/evolution/prisma/evolution.db"
  npx prisma db push --schema ./prisma/sqlite-schema.prisma --accept-data-loss
fi

# Evolution API is a standalone Node.js service
# Ensure the same DATABASE_URL is used for the runtime
export DATABASE_URL="file:/app/evolution/prisma/evolution.db"
npm run start:prod > /app/evolution.log 2>&1 &

# Wait for sidecar and evolution to be ready
echo "[boot] Waiting for services to wake up..."
max_retries=60
count=0
while ! curl -s http://localhost:8001/health > /dev/null; do
  sleep 2
  count=$((count+1))
  if [ $count -ge $max_retries ]; then
    echo "[error] AI Sidecar failed to start"
    cat /app/sidecar.log || true
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
    cat /app/evolution.log || true
    exit 1
  fi
done
echo "[boot] Evolution API ready ✅"

echo "[boot] Starting Axum Backend (Primary Gateway)..."
cd /app/backend
PORT=7860 \
SIDECAR_URL=http://localhost:8001 \
./backend-bin
