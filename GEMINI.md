# Librarian AI — Project Context (Updated May 3, 2026)

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
*   **Zero-Dependency:** Using local SQLite session storage. `CACHE_REDIS_ENABLED` is set to `false`.
*   **Persistence:** Explicit absolute paths (`/app/evolution/prisma/evolution.db`) ensure session stability.
*   **Forced Auth:** Uses fixed `AUTHENTICATION_API_KEY` to synchronize with frontend requests.

### 2. Secure Messaging (Anti-Ban)
*   Implements "composing..." status simulation and randomized 3-6 second delays between messages.

## 🛠️ Technology Stack

*   **Languages:** Rust 1.85 (LTS), Node 20 (LTS), Python 3.11.
*   **Databases:** 
    *   `uniqueBooks.db`: Master catalog (Table: `unique_books`).
    *   `evolution.db`: SQLite session store for WhatsApp sessions.
*   **Storage:** Git LFS enabled for large models and databases.

## 📂 Key API Endpoints

*   `POST /api/search`: AI-powered semantic discovery.
*   `POST /api/advanced-search`: Structured search (Supports multi-filter nulls).
*   `GET /api/overdue`: Automated tracking via attached SQLite databases.
*   `ANY /instance/*`: Proxied Evolution API management.

## 📦 Deployment & Maintenance

### Build Stability (The "Real Plan")
The "Thin Dockerfile" strategy on Hugging Face ensures **zero OOM crashes**. All compilation happens on GitHub Runners.

### Automated Boot Diagnostics (`start_hf.sh`)
1.  **LFS Verification:** Automatically checks if `uniqueBooks.db` is a real DB or a text pointer.
2.  **DB Integrity:** Uses `sqlite3` to verify and repair session databases before Prisma starts.
3.  **Environment Sync:** Exports all critical API keys and paths at runtime to prevent configuration drift.

---
**Maintained by:** Librarian Dev Team
**Last Sync:** May 2, 2026 — **Production-Ready & Stable**
