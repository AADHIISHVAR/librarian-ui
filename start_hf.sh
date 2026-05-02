#!/bin/bash
set -e

# Diagnostic: Check if uniqueBooks.db is a real database or an LFS pointer
echo "[boot] Diagnostic for uniqueBooks.db:"
ls -lh /app/uniqueBooks.db
if head -c 100 /app/uniqueBooks.db | grep -q "version https://git-lfs"; then
  echo "[error] /app/uniqueBooks.db is a Git LFS pointer, not a real database!"
else
  echo "[boot] /app/uniqueBooks.db seems to be a real file."
fi

# Setup library database
cp /app/uniqueBooks.db /app/library_database.db

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
  
  mkdir -p prisma
  DB_FILE="prisma/evolution.db"
  if [ -f "$DB_FILE" ]; then
    if [ ! -s "$DB_FILE" ]; then
        echo "[boot] $DB_FILE is 0 bytes. Deleting..."
        rm "$DB_FILE"
    elif ! sqlite3 "$DB_FILE" "PRAGMA integrity_check;" > /dev/null 2>&1; then
        echo "[boot] $DB_FILE is corrupted or not a DB. Deleting..."
        rm "$DB_FILE"
    fi
  fi
  
  export DATABASE_URL="file:/app/evolution/prisma/evolution.db"
  npx prisma db push --schema ./prisma/sqlite-schema.prisma --accept-data-loss
fi

# Ensure correct API Key and Disable Redis (if not provided) to ensure local stability
export AUTHENTICATION_API_KEY="hellowork.1234"
export CACHE_REDIS_ENABLED="false"
export CACHE_LOCAL_ENABLED="true"
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
    echo "--- Sidecar Log ---"
    cat /app/sidecar.log || true
    echo "--- End Log ---"
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
    echo "--- Evolution Log ---"
    cat /app/evolution.log || true
    echo "--- End Log ---"
    exit 1
  fi
done
echo "[boot] Evolution API ready ✅"

echo "[boot] Starting Axum Backend (Primary Gateway)..."
cd /app/backend
PORT=7860 \
SIDECAR_URL=http://localhost:8001 \
./backend-bin
