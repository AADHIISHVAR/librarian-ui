# Librarian AI — Project Context (Updated May 2, 2026)

A comprehensive library assistant system that combines vector-based semantic search with Large Language Models (LLMs) and automated student notification systems.

## 🏗️ Architecture Overview

The project is deployed as a **CI/CD Integrated Multi-Service System**:

1.  **Deployment Engine (GitHub Actions + GHCR):**
    *   Heavy compilation (Rust, Node build, Torch installation) is handled by GitHub Actions.
    *   Finished images are pushed to **GitHub Container Registry (GHCR)** as `ghcr.io/aadhiishvar/librarian-ai:latest`.
    *   **Crucial:** The package must be set to **Public** for Hugging Face to pull it.

2.  **Backend Gateway (Rust/Axum):** 
    *   **Port:** 7860 (Main Entry Point)
    *   **Role:** Primary API gateway and proxy. Built with Rust 1.85 to support Edition 2024.
    *   **Features:** Rate limiting, Bearer/X-Key authentication, and proxying for Evolution API.

3.  **Svelte Frontend (JS):**
    *   **Location:** Served by Axum from `/app/dist`.
    *   **Role:** Modern user interface for search, administration, and WhatsApp management.

4.  **AI Sidecar (Python/FastAPI):**
    *   **Port:** 8001
    *   **Role:** Semantic search using `sqlite-vec`. Aligned with `unique_books` schema.
    *   **Model:** Nomic-BERT for high-accuracy embedding.

5.  **Evolution API (Node.js):**
    *   **Port:** 8080 (Proxied)
    *   **Role:** WhatsApp integration. Configured for local caching (no Redis) and absolute SQLite pathing.

## 🚀 WhatsApp & Notification System

### 1. Connection Stability
*   **Forced Auth:** Global API key is locked to `hellowork.1234` for frontend consistency.
*   **Local Session:** `CACHE_REDIS_ENABLED` is set to `false`. Sessions are stored in `prisma/evolution.db` for zero-dependency reliability.
*   **Absolute Paths:** Uses `/app/evolution/prisma/evolution.db` to ensure runtime stability across environments.

### 2. Secure Messaging (Anti-Ban)
*   Implements "composing..." simulation and randomized 3-6 second delays between messages.

## 🛠️ Technology Stack

*   **Languages:** Rust 1.85 (Backend), Node 20 (Frontend/Evolution), Python 3.11 (AI Sidecar).
*   **Databases:** 
    *   `uniqueBooks.db`: Master catalog (Table: `unique_books`).
    *   `evolution.db`: SQLite-based session store for WhatsApp.
*   **Storage:** Git LFS enabled for `.db` and massive model files.

## 📂 Key API Endpoints

*   `POST /api/search`: AI-powered semantic discovery.
*   `POST /api/advanced-search`: Structured search (Handles null filters gracefully).
*   `GET /api/overdue`: Overdue tracking via attached SQLite databases.
*   `ANY /instance/*`: Proxied Evolution API management.

## 📦 Deployment & Maintenance

### Build Stability (The "Real Plan")
Due to RAM limits on HF Spaces, the system uses a "Thin Dockerfile" strategy:
*   **Compilation:** Happens on GitHub (Ubuntu Runners).
*   **HF Deploy:** Simply pulls the pre-built image. No compilation RAM spikes.
*   **LFS Support:** `checkout@v4` with `lfs: true` ensures real database files are included in the build, not just pointers.

### Automated Diagnostics
The `start_hf.sh` script automatically:
1.  Checks if `uniqueBooks.db` is a valid SQLite file (and not an LFS pointer).
2.  Creates valid SQLite placeholders for overdue tracking databases.
3.  Cleans up corrupted or 0-byte SQLite files before Prisma initialization.

---
**Maintained by:** Librarian Dev Team
**Last Sync:** May 2, 2026
