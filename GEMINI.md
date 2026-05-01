# Librarian AI — Project Context (Updated May 1, 2026)

A comprehensive library assistant system that combines vector-based semantic search with Large Language Models (LLMs) and automated student notification systems.

## 🏗️ Architecture Overview

The project is deployed as a **Containerized Multi-Service System** via Docker on Hugging Face Spaces:

1.  **Backend Gateway (Rust/Axum):** 
    *   **Port:** 7860 (Main Entry Point)
    *   **Role:** Acts as the primary API gateway, serving the Svelte UI and proxying requests to internal services (Sidecar & Evolution).
    *   **Features:** Rate limiting, Bearer/X-Key authentication, and static file serving for the frontend.
2.  **Svelte Frontend (JS):**
    *   **Location:** Served by Axum from `/app/dist`.
    *   **Role:** Modern, mobile-responsive user interface for search and administration.
3.  **AI Sidecar (Python/FastAPI):**
    *   **Port:** 8001
    *   **Role:** Handles semantic vector search using `sqlite-vec` and LLM-based query expansion.
4.  **Evolution API (Node.js):**
    *   **Port:** 8080 (Proxied via `/instance/*`, `/message/*`, etc.)
    *   **Role:** Production-grade WhatsApp integration for student notifications and overdue alerts.

## 🚀 WhatsApp & Notification System

### 1. Secure Messaging (Anti-Ban)
The backend implements human-behavior simulation:
*   **Presence Simulation:** Triggers "composing..." status before sending.
*   **Randomized Timing:** 3 to 6-second randomized delay between messages.
*   **Encrypted Proxy:** Axum proxies all Evolution API requests to ensure security and header preservation.

### 2. Overdue Tracking System
Integrated into the **Admin Portal** (`hisernbug` / `pounds`):
*   **Real-time Alerts:** "Notify" button generates academic reminders via WhatsApp.
*   **Data Source:** Combines `book_circle` and `combined_book` tables.

## 🛠️ Technology Stack

*   **Languages:** Rust (Backend), JavaScript/Svelte (Frontend), Python (AI Sidecar).
*   **Databases:** 
    *   `uniqueBooks.db`: Primary catalog and vector store.
    *   `evolution.db`: WhatsApp session management (SQLite).
*   **Containerization:** Multi-stage Docker build optimized for memory efficiency.
*   **Storage:** Git LFS for `.db` and `.wasm` files.

## 📂 Key API Endpoints

*   `POST /api/search`: AI-powered semantic discovery.
*   `POST /api/advanced-search`: Structured catalog search.
*   `GET /api/overdue`: Fetch list of students with overdue books.
*   `ANY /instance/*`: Proxied Evolution API management.

## 📦 Deployment & Maintenance

### Memory Optimization (HF Limits)
Due to the 16GB RAM limit on HF Spaces, the following optimizations are enforced:
*   **Rust:** `codegen-units=1`, `opt-level=z`, and `debuginfo=0`.
*   **Node:** `NODE_OPTIONS="--max-old-space-size=1536"`.
*   **Vite:** Sourcemaps disabled to prevent OOM during build.

### Manual Database Sync
If `library_database.db` is missing, the system automatically uses `uniqueBooks.db` as a fallback to ensure search functionality remains active.

---
**Maintained by:** Librarian Dev Team
**Last Sync:** May 1, 2026
