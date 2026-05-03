#!/bin/bash
set -e

# Diagnostic: Check if uniqueBooks.db is a real database or an LFS pointer
echo "[boot] Diagnostic for uniqueBooks.db:"
ls -lh /app/uniqueBooks.db
if head -c 100 /app/uniqueBooks.db | grep -q "version https://git-lfs"; then
  echo "[error] /app/uniqueBooks.db is a Git LFS pointer, not a real database!"
  # Try to fix it if git is available (it should be in the builder, but maybe not runtime)
  # On HF, we hope the builder did its job.
else
  echo "[boot] /app/uniqueBooks.db seems to be a real file."
fi

# Setup library database
cp /app/uniqueBooks.db /app/library_database.db

# Ensure overdue tracking databases exist as valid SQLite files (not empty files)
for db in /app/ilibrary-database-all.db /app/combined-library.db; do
  if [ ! -f "$db" ]; then
    sqlite3 "$db" "VACUUM;"
  fi
done

echo "[boot] Starting AI sidecar (FastAPI)..."
cd /app/sidecar
DB_PATH=/app/library_database.db \
CATALOG_DB_PATH=/app/uniqueBooks.db \
HF_TOKEN=$HF_TOKEN \
python3 -m uvicorn main:app --host 0.0.0.0 --port 8001 > /app/sidecar.log 2>&1 &

echo "[boot] Starting Evolution WhatsApp API..."
cd /app/evolution

# Environment for Evolution API
export AUTHENTICATION_TYPE="apikey"
export AUTHENTICATION_API_KEY="hellowork.1234"
export AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES="true"

# Database Configuration (Hardened for SQLite)
export DATABASE_PROVIDER="sqlite"
export DATABASE_CONNECTION_URI="file:///app/evolution/prisma/evolution.db"
export DATABASE_URL="file:///app/evolution/prisma/evolution.db"
export DATABASE_SAVE_DATA_INSTANCE="true"
export DATABASE_SAVE_DATA_NEW_MESSAGE="true"
export DATABASE_SAVE_MESSAGE_UPDATE="true"
export DATABASE_SAVE_DATA_CONTACTS="true"
export DATABASE_SAVE_DATA_CHATS="true"
export DATABASE_SAVE_DATA_HISTORIC="true"
export DATABASE_SAVE_DATA_LABELS="true"

# Cache & Connection
export CACHE_REDIS_ENABLED="false"
export CACHE_LOCAL_ENABLED="true"
export WEBHOOK_GLOBAL_ENABLED="false"
export SERVER_URL="https://aadhiishvar-library-assist-alphav1-10.hf.space"
export LOG_LEVEL="INFO,ERROR,WARN"
export LOG_COLOR="true"
export QRCODE_LIMIT=30
export QRCODE_TERMINAL="true"

# Initialize SQLite database
echo "[boot] Initializing SQLite database for Evolution API..."
mkdir -p prisma
DB_FILE="prisma/evolution.db"

# NUCLEAR CLEANUP: Remove 'halo' instance and its session to FORCE fresh QR generation
if [ -f "$DB_FILE" ]; then
    echo "[boot] Scrubbing 'halo' session data for fresh start..."
    # Correct order: Delete Session first (related by sessionId), then Instance
    sqlite3 "$DB_FILE" "DELETE FROM \"Session\" WHERE sessionId IN (SELECT id FROM \"Instance\" WHERE name='halo');" || true
    sqlite3 "$DB_FILE" "DELETE FROM \"Instance\" WHERE name='halo';" || true
fi

# Run prisma migration/push
echo "[boot] Generating Prisma client..."
npx prisma generate --schema ./prisma/sqlite-schema.prisma
echo "[boot] Pushing database schema..."
npx prisma db push --schema ./prisma/sqlite-schema.prisma --accept-data-loss

# Check if DB exists now
if [ -f "$DB_FILE" ]; then
    echo "[boot] Database file verified: $(ls -lh $DB_FILE)"
else
    echo "[boot] WARNING: Database file $DB_FILE missing after prisma push!"
fi

echo "[boot] Starting Evolution Node process (Logging to STDOUT)..."
# We no longer redirect to /app/evolution.log so that the QR code prints to the Hugging Face terminal
npm run start:prod &

# Wait for sidecar and evolution to be ready
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

count=0
while ! curl -sf http://localhost:8080/instance/fetchInstances -H "apikey: hellowork.1234" > /dev/null; do
  sleep 2
  count=$((count+1))
  if [ $count -ge $max_retries ]; then
    echo "[error] Evolution API failed to start or authentication failed"
    # Diagnostic: Check if port 8080 is even listening
    echo "[boot] Diagnostic: Netstat for 8080:"
    netstat -tulpn | grep 8080 || echo "Port 8080 is NOT listening"
    exit 1
  fi
done
echo "[boot] Evolution API ready ✅"

# FORCE CREATE 'halo' instance now to trigger QR generation in terminal
echo "[boot] Auto-provisioning 'halo' instance..."
curl -s -X POST "http://localhost:8080/instance/create" \
     -H "Content-Type: application/json" \
     -H "apikey: hellowork.1234" \
     -d '{
       "instanceName": "halo",
       "qrcode": true,
       "integration": "WHATSAPP-BAILEYS"
     }' || echo "[warn] Auto-provisioning failed (may already exist)"

echo "[boot] ALL SERVICES DISCOVERED. Starting Axum Backend (Primary Gateway)..."
cd /app/backend
PORT=7860 \
SIDECAR_URL=http://localhost:8001 \
./backend-bin
