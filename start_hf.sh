#!/bin/bash
set -e

# Setup library databases
echo "[boot] Ensuring library databases exist..."
for db in /app/uniqueBooks.db /app/library_database.db /app/ilibrary-database-all.db /app/combined-library.db; do
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

echo "[boot] Starting Evolution WhatsApp API..."
cd /app/evolution

# Environment for Evolution API - HARDENED FOR HF
export LOG_LEVEL="INFO"
export LOG_COLOR="false"
export LOG_Pino_Pretty="true"
export QRCODE_TERMINAL="true"
export AUTHENTICATION_TYPE="apikey"
export AUTHENTICATION_API_KEY="hellowork.1234"
export AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES="true"

# CRITICAL: Force IPv4 and specific WhatsApp version
# Adding NODE_IP_FAMILY=4 to force IPv4
export NODE_OPTIONS="--dns-result-order=ipv4first --max-old-space-size=2048"
export NODE_IP_FAMILY=4
export WA_WEB_VERSION="2.3000.1015901355"

# Baileys Tweak: Try to force specific connection behavior via env
export WA_MOBILE="false"
export WA_BROWSER="Chrome"

# Force IPv4 and attempt a specific DNS for WhatsApp if default fails
# This is a last-resort attempt to ensure e.whatsapp.net resolves
echo "nameserver 8.8.8.8" > /etc/resolv.conf || echo "[warn] Failed to update resolv.conf"


# Better session identification
export CONFIG_SESSION_PHONE_CLIENT="Librarian AI"
export CONFIG_SESSION_PHONE_NAME="Chrome (Linux)"
export LOG_BAILEYS="info"

# Diagnostic: Deep Network Audit
echo "[boot] Network Audit: Testing reachability and DNS..."
echo "--- DNS Check ---"
getent hosts web.whatsapp.com || echo "web.whatsapp.com resolution failed"
getent hosts g.whatsapp.net || echo "g.whatsapp.net resolution failed"
getent hosts e.whatsapp.net || echo "e.whatsapp.net resolution failed"


echo "--- Ping Check ---"
ping -c 1 -W 2 8.8.8.8 || echo "Ping to 8.8.8.8 failed"

echo "--- Port 443 Check ---"
timeout 3 bash -c 'cat < /dev/null > /dev/tcp/web.whatsapp.com/443' && echo "Port 443 OK" || echo "Port 443 CLOSED"

echo "--- Port 5222 Check (WhatsApp Protocol) ---"
timeout 3 bash -c 'cat < /dev/null > /dev/tcp/e.whatsapp.net/5222' && echo "Port 5222 OK" || echo "Port 5222 CLOSED"

echo "--- MTU Check ---"
ip addr show | grep mtu || true

# Baileys Tweak: Try to force specific connection behavior via env
export WA_MOBILE="false"
export WA_BROWSER="Chrome"

# Force IPv4 and attempt a specific DNS for WhatsApp if default fails
# This is a last-resort attempt to ensure e.whatsapp.net resolves
echo "nameserver 8.8.8.8" > /etc/resolv.conf || echo "[warn] Failed to update resolv.conf"

# Fix permissions at runtime (HF runs as user 1000)
echo "[boot] Fixing permissions for $(whoami)..."
mkdir -p /app/evolution/instances
mkdir -p /app/evolution/prisma
chmod -R 777 /app/evolution
chmod -R 777 /app/sidecar
chmod -R 777 /app/backend


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
# Canonical HF Space URL (usually lowercase)
export SERVER_URL="https://aadhiishvar-library-assist-alphav1-10.hf.space"
export LOG_LEVEL="INFO,ERROR,WARN"
export LOG_COLOR="true"
export DEL_INSTANCE="false"
export QRCODE_LIMIT=30

# Initialize SQLite database
echo "[boot] Initializing SQLite database for Evolution API..."
mkdir -p /app/evolution/prisma
mkdir -p /app/evolution/instances
chmod -R 777 /app/evolution/instances
DB_FILE="/app/evolution/prisma/evolution.db"

# Seed library databases with mock data for testing
echo "[boot] Seeding library databases with mock data..."
python3 /app/seed_db.py || echo "[warn] Seeding failed, continuing..."
# Also seed the primary evolution DB if needed, but we focus on the library sidecar
cp /app/library_database.db /app/uniqueBooks.db || true

# Create dummy DB if it doesn't exist so sqlite3 doesn't fail
if [ ! -f "$DB_FILE" ]; then
    echo "[boot] Creating initial empty database..."
    sqlite3 "$DB_FILE" "VACUUM;"
fi



# NUCLEAR CLEANUP: Completely wipe 'halo' state to ensure a fresh session
echo "[boot] Wiping any existing 'halo' session files and database entries..."
rm -rf /app/evolution/instances/halo
rm -f /tmp/whatsapp_qr.json

if [ -f "$DB_FILE" ]; then
    echo "[boot] Cleaning database entries for 'halo'..."
    sqlite3 "$DB_FILE" "DELETE FROM \"Session\" WHERE sessionId IN (SELECT id FROM \"Instance\" WHERE name='halo');" || true
    sqlite3 "$DB_FILE" "DELETE FROM \"Instance\" WHERE name='halo';" || true
    sqlite3 "$DB_FILE" "VACUUM;" || true
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

# The Evolution API is now hosted on GCP (20.6.122.244)
# We no longer start it locally on HF.
echo "[boot] Evolution API is remote (GCP: 20.6.122.244). Skipping local startup."


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

# The Evolution API is remote. We no longer need to check local health.
echo "[boot] Evolution API remote check skipped."

# Evolution API is remote. Auto-provisioning handled via GCP/manual setup.
echo "[boot] Skipping local auto-provisioning of 'halo' instance."


# The Evolution API is remote. Local QR keeper is no longer needed.
echo "[boot] Skipping local QR keeper (API is remote)."


echo "[boot] ALL SERVICES DISCOVERED. Starting Axum Backend (Primary Gateway)..."
echo "[boot] If ASCII QR did not print, check Evolution lines above or proxy logs for [proxy][instance/connect]."
cd /app/backend
PORT=7860 \
SIDECAR_URL=http://localhost:8001 \
./backend-bin
