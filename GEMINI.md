# Librarian AI — Project Context (Updated June 18, 2026)

A comprehensive library assistant system that combines vector-based semantic search with Large Language Models (LLMs) and automated student notification systems.

## 🏗️ Architecture Overview (Split Deployment)

The project is deployed using a split-deployment architecture to ensure reliability, bypass network restrictions, and maintain fast build times.

1.  **Frontend (GitHub Pages):**
    *   **Hosting:** Served from `https://aadhiishvar.github.io/librarian-ui`.
    *   **CI/CD:** Automatically built and deployed via `.github/workflows/deploy-frontend.yml`.
    *   **Config:** Communicates via HTTPS with the Rust Gateway.

2.  **Rust Gateway & AI Services (Azure VM):**
    *   **Hosting:** Hosted on Azure VM (`20.6.122.244`).
    *   **Rust Gateway (Axum):** Port 7860. Handles API routing, rate limiting, and secure proxying to the WhatsApp API.
    *   **AI Sidecar (Python):** Port 8001. Implements HyDE and semantic search using `sqlite-vec`.

3.  **WhatsApp API (Azure VM):**
    *   **Hosting:** Hosted on Azure VM (`20.6.122.244`).
    *   **Stack:** Evolution API running in Docker with a PostgreSQL database.
    *   **Access:** Only accessible via the Rust Gateway using a master `apikey`.

## 🚀 WhatsApp & Notification System

### 1. Secure Proxying & Connectivity
*   **Azure Migration:** Moved Evolution API to Azure VM to bypass Hugging Face's network-level WebSocket blocks on `e.whatsapp.net`.
*   **Secure Tunnel:** All frontend requests are routed through the Rust Gateway, which adds the necessary `apikey` and forwards them to the Evolution API.
*   **QR Lifecycle:** QR codes are detected by the gateway and cached in `/tmp/whatsapp_qr.json` for fast retrieval by the frontend via `/api/whatsapp/qr`.
*   **Stability:**
    *   Implemented optional chaining for phone numbers in `connectToWhatsapp` to prevent crashes during QR-based creation.
    *   Wrapped `logoutInstance` in try-catch to handle session deletion failures gracefully.

### 2. Secure Messaging (Anti-Ban)
*   Implements "composing..." status simulation and randomized 3-6 second delays between messages to mimic human behavior.

## 🤖 AI & Semantic Search

### 1. Vector-Based Discovery
*   **Engine:** Uses `sqlite-vec` for high-performance vector similarity search.
*   **Mechanism:** Implements HyDE (Hypothetical Document Embeddings) to expand user prompts into synthetic answers before searching.
*   **Fallback:** Automatically falls back to standard SQL `LIKE` title search if vector similarity is low (< 0.6).

### 2. Data Seeding
*   **Mock Data:** Implemented `seed_db.py` to automatically populate `library_database.db` at boot, enabling immediate testing of AI features.

## 🛠️ Technology Stack

*   **Languages:** Rust 1.86 (LTS), Node 20 (LTS), Python 3.11.
*   **Databases:** 
    *   `library_database.db`: Master catalog (seeded automatically).
    *   PostgreSQL: Evolution API session store on Azure VM.
*   **Deployment:** Rust backend run as a systemd service on Azure VM; AI sidecar run on port 8001.

## 📂 Key API Endpoints

*   `POST /api/search`: AI-powered semantic discovery.
*   `POST /api/advanced-search`: Structured search.
*   `GET /api/overdue`: Automated overdue book tracking.
*   `ANY /instance/*`, `/message/*`, `/chat/*`: Proxied Evolution API management.
*   `GET /api/whatsapp/qr`: Retrieves the latest cached WhatsApp QR code.

## 📦 Deployment & Maintenance

### Build Stability
All services are compiled and run locally on the Azure VM. All WhatsApp API services are managed independently on the Azure VM.

---
**Maintained by:** Librarian Dev Team
**Last Sync:** June 18, 2026 — **Production-Ready & Stable**
