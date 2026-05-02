# Librarian AI — Project Context (Updated May 2, 2026)

A comprehensive library assistant system that combines vector-based semantic search with Large Language Models (LLMs) and automated student notification systems. **Status: All systems fully operational, synchronized, and hardened.**

## 🏗️ Architecture Overview

The project is deployed as a **CI/CD Integrated Multi-Service System**, leveraging GitHub's infrastructure for builds and Hugging Face for stable runtime.

1.  **Deployment Engine (GitHub Actions + GHCR):**
    *   **Heavy Lifting:** All compilation (Rust 1.85, Node build, Torch) happens on GitHub to avoid 16GB RAM limits on HF.
    *   **LFS Support:** `checkout@v4` with `lfs: true` and explicit `git lfs pull` ensures real database files are included in the image.
    *   **Registry:** Images are served via `ghcr.io/aadhiishvar/librarian-ai:latest`. (Must be set to **Public**).

2.  **Backend Gateway (Rust/Axum):** 
    *   **Primary Gateway:** Built with Rust 1.85 (Edition 2024).
    *   **Auth:** Secured via `LIB_AI_2024_SECURE_TOKEN`. Origin-agnostic middleware ensures global accessibility.

3.  **Svelte Frontend (JS):**
    *   **Admin Portal:** Integrated WhatsApp instance management, QR/Pairing code display, and overdue tracking.

4.  **AI Sidecar (Python/FastAPI):**
    *   **Semantic Search:** Using `sqlite-vec`. Aligned with `unique_books` schema.
    *   **Robustness:** Handles null/missing search filters gracefully (resolves 422 errors).

5.  **Evolution API (Node.js):**
    *   **WhatsApp Core:** Hardened for zero-dependency local mode.
    *   **Connectivity:** Fixed QR generation by disabling Redis and forcing global API key `hellowork.1234`.

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
