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

# Environment for Evolution API - HARDENED FOR HF
export LOG_LEVEL="DEBUG"
export LOG_COLOR="false"
export LOG_Pino_Pretty="true"
export QRCODE_TERMINAL="true"
export AUTHENTICATION_TYPE="apikey"
export AUTHENTICATION_API_KEY="hellowork.1234"
export AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES="true"

# CRITICAL: Force IPv4 and specific WhatsApp version
export NODE_OPTIONS="--dns-result-order=ipv4first --max-old-space-size=2048"
export WA_WEB_VERSION="2.3000.1018224522"

# Force IPv4 at the host level (works if running as root)
echo "57.144.55.32 web.whatsapp.com" >> /etc/hosts || echo "[warn] Failed to update /etc/hosts"
echo "157.240.22.60 e.whatsapp.net" >> /etc/hosts || echo "[warn] Failed to update /etc/hosts"
echo "157.240.22.60 g.whatsapp.net" >> /etc/hosts || echo "[warn] Failed to update /etc/hosts"

# Better session identification
export CONFIG_SESSION_PHONE_CLIENT="Librarian AI"
export CONFIG_SESSION_PHONE_NAME="Chrome (Linux)"
export LOG_BAILEYS="info"

# Diagnostic: Deep Network Audit
echo "[boot] Network Audit: Testing reachability and DNS..."
echo "--- DNS Check ---"
getent hosts web.whatsapp.com || echo "web.whatsapp.com resolution failed"
getent hosts g.whatsapp.net || echo "g.whatsapp.net resolution failed"

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
curl -s -X POST "http://localhost:8080/instance/create" \
     -H "Content-Type: application/json" \
     -H "apikey: hellowork.1234" \
     -d '{
       "instanceName": "halo",
       "qrcode": true,
       "integration": "WHATSAPP-BAILEYS"
     }' > /dev/null

# Poll Evolution until the raw QR string exists, then print an ASCII QR to HF logs (stdout).
echo "[boot] Polling /instance/connect/halo — ASCII QR will print below when Baileys exposes raw 'code'…"
python3 - <<'PYBOOT'
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


time.sleep(5)
printed = False
for attempt in range(1, 46):
    try:
        j = fetch()
    except Exception as e:
        print(f"[boot][QR] attempt {attempt}: HTTP error: {e}")
        time.sleep(2)
        continue
    if isinstance(j, dict) and j.get("error"):
        print(f"[boot][QR] attempt {attempt}: API error: {j.get('message')}")
        time.sleep(2)
        continue
    
    p = j.get("qrcode") if isinstance(j, dict) else None
    if not isinstance(p, dict):
        p = j if isinstance(j, dict) else {}
    
    code = p.get("code")
    b64 = p.get("base64")
    
    if isinstance(code, str) and len(code) > 10:
        print(f"[boot][QR] attempt {attempt}: raw QR string length={len(code)}")
        
        # Save to cache for backend
        try:
            with open(CACHE_FILE, "w") as f:
                json.dump({"code": code, "base64": b64, "timestamp": time.time()}, f)
        except Exception as e:
            print(f"[boot][QR] Failed to save cache: {e}")
            
        render_ascii(code)
        printed = True
        break
    
    if isinstance(b64, str) and len(b64) > 80:
        print(
            f"[boot][QR] attempt {attempt}: only base64 PNG present (len={len(b64)}), "
            "waiting for raw 'code' for terminal render…"
        )
        # Still save the base64 if we have it
        try:
            with open(CACHE_FILE, "w") as f:
                json.dump({"code": None, "base64": b64, "timestamp": time.time()}, f)
        except: pass
    else:
        keys = list(j.keys()) if isinstance(j, dict) else []
        cnt = p.get("count") if isinstance(p, dict) else None
        print(f"[boot][QR] attempt {attempt}: waiting… keys={keys} count={cnt}")
    time.sleep(2)

if not printed:
    print(
        "[boot][QR] No raw 'code' in /instance/connect/halo after ~90s. "
        "Check Evolution stdout above for Baileys terminal QR, or use the admin UI once base64 is returned."
    )
PYBOOT

echo "[boot] ALL SERVICES DISCOVERED. Starting Axum Backend (Primary Gateway)..."
echo "[boot] If ASCII QR did not print, check Evolution lines above or proxy logs for [proxy][instance/connect]."
cd /app/backend
PORT=7860 \
SIDECAR_URL=http://localhost:8001 \
./backend-bin
