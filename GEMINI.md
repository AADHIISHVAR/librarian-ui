# Librarian AI — Project Context (Updated May 5, 2026)
 
A comprehensive library assistant system that combines vector-based semantic search with Large Language Models (LLMs) and automated student notification systems.
 
## 🏗️ Architecture Overview (Split Deployment)
 
The project is now deployed using a split architecture for maximum reliability and build stability:
 
1.  **Frontend (GitHub Pages):**
    *   **Hosting:** Served from `https://aadhiishvar.github.io/librarian-ui`.
    *   **CI/CD:** Automatically built and deployed via `.github/workflows/deploy-frontend.yml`.
    *   **Config:** Communicates with the Hugging Face backend URL.
 
2.  **Backend & AI Services (Hugging Face):**
    *   **Natively Built:** Build is handled directly by Hugging Face using the self-contained `Dockerfile`.
    *   **Services:** Runs the Rust Axum Gateway (Port 7860), AI Sidecar (Port 8001), and Evolution API (Port 8080).
    *   **Reliability:** No longer dependent on external GHCR image pulls.
 
3.  **Hugging Face "Thin Repository":**
    *   Hugging Face builds from source on every push to the `hf` remote.
 
## 🚀 WhatsApp & Notification System
 
### 1. Hardened Connection
*   **Status:** Currently disabled on HF due to network-level WebSocket blocks on `e.whatsapp.net`.
*   **QR Lifecycle Fixed:** Resolved the connection flow (Connect -> Generate -> Return) to ensure QR codes are correctly returned to the frontend.
*   **Crash Prevention:** 
    *   Implemented optional chaining for phone numbers in `connectToWhatsapp` to prevent `TypeError` during QR-based creation.
    *   Wrapped `logoutInstance` in try-catch to prevent session deletion failures from crashing the server.
*   **Network Tunneling (HF Space):** 
    *   Forced IPv4 priority via `NODE_OPTIONS`.
    *   Overrode `/etc/resolv.conf` with Google DNS (`8.8.8.8`) to ensure critical WhatsApp WebSocket endpoints resolve.
    *   Removed hardcoded IP overrides in `/etc/hosts` to prevent `ECONNREFUSED` errors.
*   **Zero-Dependency:** Using local SQLite session storage. `CACHE_REDIS_ENABLED` is set to `false`.
*   **Persistence:** Explicit absolute paths (`/app/evolution/prisma/evolution.db`) ensure session stability.
*   **Forced Auth:** Uses fixed `AUTHENTICATION_API_KEY` to synchronize with frontend requests.
 
### 2. Secure Messaging (Anti-Ban)
*   Implements "composing..." status simulation and randomized 3-6 second delays between messages.
 
## 🤖 AI & Semantic Search
 
### 1. Vector-Based Discovery
*   **Engine:** Uses `sqlite-vec` for high-performance vector similarity search.
*   **Mechanism:** Implements HyDE (Hypothetical Document Embeddings) to expand user prompts into synthetic answers before searching.
*   **Fallback:** If vector similarity is low (< 0.6), the system automatically falls back to standard SQL `LIKE` title search.
 
### 2. Data Seeding
*   **Mock Data:** Implemented `seed_db.py` to automatically populate `library_database.db` at boot, enabling immediate testing of AI features without manual data imports.
 
## 🛠️ Technology Stack
 
*   **Languages:** Rust 1.86 (LTS), Node 20 (LTS), Python 3.11.
*   **Databases:** 
*   `uniqueBooks.db`: Master catalog. Seeded automatically at boot for demo purposes.
*   `evolution.db`: SQLite session store for WhatsApp sessions.
*   **Storage:** Binary files removed from Git history to comply with HF constraints.
 
## 📂 Key API Endpoints
 
*   `POST /api/search`: AI-powered semantic discovery.
*   `POST /api/advanced-search`: Structured search (Supports multi-filter nulls).
*   `GET /api/overdue`: Automated tracking via attached SQLite databases.
*   `ANY /instance/*`: Proxied Evolution API management.
 
## 📦 Deployment & Maintenance
 
### Build Stability (The "Real Plan")
The "Thin Dockerfile" strategy on Hugging Face ensures **zero OOM crashes**. All compilation happens on GitHub Runners.
 
### Automated Boot Diagnostics (`start_hf.sh`)
1.  **DB Auto-Initialization & Seeding:** Automatically creates and populates missing SQLite databases (via `seed_db.py`) to prevent boot failures.
2.  **Instance Auto-Provisioning:** Creates the `halo` instance and triggers an immediate connection with a 5s delay for stability.
3.  **Network Audit:** Verifies DNS resolution for `web.whatsapp.com`, `g.whatsapp.net`, and `e.whatsapp.net` at boot.
4.  **DB Integrity:** Uses `sqlite3` to verify and repair session databases before Prisma starts.
5.  **Environment Sync:** Exports all critical API keys and paths at runtime to prevent configuration drift.
 
---
**Maintained by:** Librarian Dev Team
**Last Sync:** May 5, 2026 — **Production-Ready & Stable (AI/Search enabled, WhatsApp Network-Blocked)**
