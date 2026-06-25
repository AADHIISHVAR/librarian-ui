#!/bin/bash
set -e

REPO_DIR="/home/aadhiishvar/week_end_projects/enriched_ai"
HF_URL="https://$HF_USER:$HF_TOKEN@huggingface.co/spaces/AADHIISHVAR/enriched_ai"
SRC_DIR="/home/aadhiishvar/week_end_projects/lib_automation/hf_space"

echo "=== Cleaning previous clone if exists ==="
rm -rf "$REPO_DIR"

echo "=== Cloning Hugging Face Space Repo ==="
git clone "$HF_URL" "$REPO_DIR"

echo "=== Copying deployment files ==="
cp -rf "$SRC_DIR"/* "$REPO_DIR"/

cd "$REPO_DIR"

echo "=== Configuring Git LFS ==="
git lfs install
git lfs track "*.db"

echo "=== Configuring Git User ==="
git config user.name "AADHIISHVAR"
git config user.email "aadhiishvar@users.noreply.huggingface.co"

echo "=== Git Commit ==="
git add .
# Don't fail if there's nothing to commit (e.g. clean status)
git commit -m "Deploy self-contained AI Vector Search service with self-compiling SQLite DB" || echo "Nothing to commit"

echo "=== Pushing to Hugging Face Spaces ==="
git push origin main

echo "=== Push Completed Successfully! ==="
