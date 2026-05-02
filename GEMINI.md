# Librarian AI — Project Context (Updated May 2, 2026)

A comprehensive library assistant system that combines vector-based semantic search with Large Language Models (LLMs) and automated student notification systems. **Status: All systems fully operational and synchronized.**

## 🏗️ Architecture Overview

The project is deployed as a **CI/CD Integrated Multi-Service System**, solving all previous memory and cache issues.

1.  **Deployment Engine (GitHub Actions + GHCR):**
    *   **Verified:** Heavy compilation (Rust 1.85, Node build, Torch) is handled exclusively by GitHub.
    *   **Verified:** Git LFS support is enabled; real database files are correctly pulled and built into images.
    *   **Public Access:** Image is served via `ghcr.io/aadhiishvar/librarian-ai:latest`.

2.  **Backend Gateway (Rust/Axum):** 
    *   **Verified:** Primary API gateway serving as a secure proxy.
    *   **Security:** Simplified `api_key_middleware` to use token-based auth (`LIB_AI_2024_SECURE_TOKEN`) while removing restrictive origin blocks for maximum availability.

3.  **Svelte Frontend (JS):**
    *   **Verified:** Modern, responsive UI. All API calls are synchronized with the backend gateway.

4.  **AI Sidecar (Python/FastAPI):**
    *   **Verified:** Semantic search using `sqlite-vec` aligned with the `unique_books` schema.
    *   **Hardening:** Handles null search filters gracefully (resolves 422 errors).

5.  **Evolution API (Node.js):**
    *   **Verified:** WhatsApp integration. Fixed QR/Pairing code generation by disabling Redis and forcing global API keys (`hellowork.1234`).

## 🚀 WhatsApp & Notification System

### 1. Connection Stability
*   **Zero-Dependency:** Using local SQLite session storage for WhatsApp, removing the need for an external Redis server.
*   **Reliability:** Explicit absolute paths (`/app/evolution/prisma/evolution.db`) prevent runtime environment confusion.

### 2. Secure Messaging (Anti-Ban)
*   Implements "composing..." status and randomized delays to simulate human behavior.

## 🛠️ Technology Stack

*   **Languages:** Rust 1.85 (Edition 2024), Node 20 (LTS), Python 3.11.
*   **Databases:** 
    *   `uniqueBooks.db`: Master catalog (Table: `unique_books`).
    *   `evolution.db`: SQLite session store.
*   **Storage:** Git LFS enabled for large models and databases.

## 📂 Key API Endpoints

*   `POST /api/search`: AI-powered semantic discovery.
*   `POST /api/advanced-search`: Structured search (Highly robust).
*   `GET /api/overdue`: Automated tracking via attached databases.
*   `ANY /instance/*`: Proxied Evolution API management.

## 📦 Deployment & Maintenance

### Build Stability (The "Real Plan")
The "Thin Dockerfile" strategy on Hugging Face ensures **zero OOM crashes** during deployment. All heavy lifting is done on GitHub's infrastructure.

### Automated Health Checks
The `start_hf.sh` script handles:
1.  **LFS Verification:** Ensures `uniqueBooks.db` is a real DB and not a text pointer.
2.  **Database Repair:** Cleans corrupted SQLite placeholders before services start.
3.  **Dependency Ordering:** Ensures AI and WhatsApp services are healthy before opening the gateway.

---
**Maintained by:** Librarian Dev Team
**Last Sync:** May 2, 2026 — **Architecture Verified Stable**
