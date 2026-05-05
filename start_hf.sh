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
export LOG_LEVEL="DEBUG"
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
export WA_WEB_VERSION="2.3000.1018224522"

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

echo "[boot] Starting Evolution Node process (Logging to STDOUT)..."
# Setting LOG_LEVEL to DEBUG to capture linkage failures
export LOG_LEVEL="DEBUG"

# Diagnostic: Verify qrcode-terminal is present
if [ -d "/app/evolution/node_modules/qrcode-terminal" ]; then
    echo "[boot] qrcode-terminal found in node_modules ✅"
else
    echo "[boot] WARNING: qrcode-terminal NOT FOUND in /app/evolution/node_modules!"
    # Try to install it if missing (last resort)
    # cd /app/evolution && npm install qrcode-terminal
fi

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
echo "[boot] Auto-provisioning 'halo' instance for instant QR..."
CREATE_RESP=$(curl -s -w "%{http_code}" -o /tmp/create_resp.log -X POST "http://localhost:8080/instance/create" \
     -H "Content-Type: application/json" \
     -H "apikey: hellowork.1234" \
     -d '{
       "instanceName": "halo",
       "qrcode": true,
       "integration": "WHATSAPP-BAILEYS"
     }')

if [ "$CREATE_RESP" != "201" ] && [ "$CREATE_RESP" != "200" ]; then
  echo "[error] Failed to create 'halo' instance. HTTP Status: $CREATE_RESP"
  cat /tmp/create_resp.log
  # We don't exit 1 here to allow other services to start, but this is a critical failure
fi

# Give the API time to actually initialize the instance in memory/DB
echo "[boot] Waiting 5s for instance initialization..."
sleep 5

# Trigger connect once immediately so QR generation starts without admin login.
echo "[boot] Triggering immediate connect for 'halo'..."
curl -v -X GET "http://localhost:8080/instance/connect/halo" \
     -H "apikey: hellowork.1234" || true

# Keep QR warm in background from process start.
echo "[boot] Starting background QR keeper for 'halo'..."
python3 - <<'PYBOOT' &
import json, os, subprocess, time, urllib.request

API = "http://127.0.0.1:8080/instance/connect/halo"
HDR = {"apikey": "hellowork.1234"}
CACHE_FILE = "/tmp/whatsapp_qr.json"


def fetch():
    req = urllib.request.Request(API, headers=HDR)
    with urllib.request.urlopen(req, timeout=45) as resp:
        return json.load(resp)


def render_ascii(code: str) -> None:
    path = "/tmp/hf_qr_payload.txt"
    with open(path, "w", encoding="utf-8") as f:
        f.write(code)
    env = os.environ.copy()
    env["NODE_PATH"] = "/app/evolution/node_modules"
    js = (
        "const fs=require('fs');const qrt=require('qrcode-terminal');"
        "const code=fs.readFileSync('/tmp/hf_qr_payload.txt','utf8');"
        "qrt.generate(code,{small:true},function(o){"
        "process.stdout.write('\\n========== [boot] WhatsApp QR (scan with phone) ==========\\n'+o+'\\n============================================================\\n');"
        "});"
    )
    r = subprocess.run(["node", "-e", js], cwd="/app/evolution", env=env, capture_output=True, text=True)
    if r.stdout:
        print(r.stdout, end="")
    if r.stderr:
        print(r.stderr, end="")
    if r.returncode != 0:
        print(f"[boot][QR] qrcode-terminal exit {r.returncode}")


time.sleep(3)
last_code = None
while True:
    try:
        j = fetch()
    except Exception as e:
        print(f"[boot][QR] keeper: HTTP error: {e}")
        time.sleep(3)
        continue

    if isinstance(j, dict) and j.get("error"):
        print(f"[boot][QR] keeper: API error: {j.get('message')}")
        time.sleep(3)
        continue

    p = j.get("qrcode") if isinstance(j, dict) else None
    if not isinstance(p, dict):
        p = j if isinstance(j, dict) else {}

    code = p.get("code")
    b64 = p.get("base64")

    if isinstance(code, str) and len(code) > 10:
        if code != last_code:
            print(f"[boot][QR] keeper: new raw QR string length={len(code)}")
            last_code = code
            render_ascii(code)
        try:
            with open(CACHE_FILE, "w") as f:
                json.dump({"code": code, "base64": b64, "timestamp": time.time()}, f)
        except Exception as e:
            print(f"[boot][QR] keeper: failed to save cache: {e}")
    elif isinstance(b64, str) and len(b64) > 80:
        try:
            with open(CACHE_FILE, "w") as f:
                json.dump({"code": None, "base64": b64, "timestamp": time.time()}, f)
        except Exception as e:
            print(f"[boot][QR] keeper: failed to save base64 cache: {e}")
        print(f"[boot][QR] keeper: base64 QR present (len={len(b64)}), waiting for raw code...")
    else:
        keys = list(j.keys()) if isinstance(j, dict) else []
        print(f"[boot][QR] keeper: waiting... keys={keys}")

    time.sleep(5)
PYBOOT

echo "[boot] ALL SERVICES DISCOVERED. Starting Axum Backend (Primary Gateway)..."
echo "[boot] If ASCII QR did not print, check Evolution lines above or proxy logs for [proxy][instance/connect]."
cd /app/backend
PORT=7860 \
SIDECAR_URL=http://localhost:8001 \
./backend-bin
