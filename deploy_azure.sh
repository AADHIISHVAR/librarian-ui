#!/bin/bash
set -e

echo "🚀 Starting Librarian Backend Deployment on Azure..."

# 1. Update and install system dependencies
sudo apt-get update
sudo apt-get install -y pkg-config libssl-dev build-essential ca-certificates git curl

# 2. Install Rust
if ! command -v cargo &> /dev/null; then
    echo "📦 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
else
    echo "✅ Rust is already installed."
fi

# 3. Clone Repository
REPO_DIR="$HOME/librarian-ui"
if [ ! -d "$REPO_DIR" ]; then
    echo "📂 Cloning repository..."
    git clone https://github.com/AADHIISHVAR/librarian-ui.git "$REPO_DIR"
else
    echo "✅ Repository already exists, pulling latest changes..."
    cd "$REPO_DIR" && git pull
fi

# 4. Build Backend
echo "🏗️ Building backend in release mode..."
cd "$REPO_DIR/backend"
cargo build --release

# 5. Setup Systemd Service for background running
echo "⚙️ Setting up systemd service..."
SERVICE_FILE="/etc/systemd/system/librarian.service"
sudo bash -c "cat <<EOF > $SERVICE_FILE
[Unit]
Description=Librarian Rust Backend
After=network.target

[Service]
User=$USER
WorkingDirectory=$REPO_DIR/backend
ExecStart=$REPO_DIR/backend/target/release/library-backend
Restart=always
Environment=PORT=7860
Environment=SIDECAR_URL=http://localhost:8001
Environment=EVOLUTION_URL=http://localhost:8080

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable librarian
sudo systemctl restart librarian

echo "✅ DEPLOYMENT COMPLETE!"
echo "----------------------------------------------------------------"
echo "Backend is now running in the background."
echo "Check status: sudo systemctl status librarian"
echo "Check logs: journalctl -u librarian -f"
echo "Remember to open port 7860 in your Azure Network Security Group!"
echo "----------------------------------------------------------------"
