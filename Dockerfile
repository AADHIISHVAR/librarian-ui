# ==========================================
# Stage 1: Rust Backend Builder
# ==========================================
FROM rust:1.86-slim AS backend-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev build-essential ca-certificates git curl && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*
ENV CARGO_NET_RETRY=10
ENV CARGO_HTTP_TIMEOUT=600
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
ENV CARGO_INCREMENTAL=0
 
WORKDIR /app/backend
COPY backend/Cargo.toml backend/Cargo.lock ./
 
# Robust dependency fetch with explicit failure if retries are exhausted
RUN mkdir -p src && printf "fn main() {}\n" > src/main.rs
RUN ok=0; \
    for i in 1 2 3 4 5 6; do \
      if cargo fetch; then ok=1; break; fi; \
      echo "[build][cargo] fetch failed (attempt $i), retrying..." && sleep 20; \
    done; \
    test "$ok" -eq 1
 
# Copy real source and build
COPY backend/src ./src
ENV RUSTFLAGS="-C codegen-units=1 -C opt-level=z -C debuginfo=0 -C link-arg=-s"
RUN ok=0; \
    for i in 1 2 3; do \
      if CARGO_BUILD_JOBS=1 cargo build --release; then ok=1; break; fi; \
      echo "[build][cargo] build failed (attempt $i), retrying..." && sleep 20; \
    done; \
    test "$ok" -eq 1
 
# ==========================================
# Stage 2: Final Runtime Image
# ==========================================
FROM python:3.11-slim
 
# 1. System Runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ffmpeg openssl sqlite3 libsqlite3-dev build-essential \
    iproute2 iputils-ping dnsutils ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
 
# 2. Node.js (Still needed for the QR terminal rendering in backend)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
 
WORKDIR /app
 
# 3. AI Sidecar
COPY sidecar/requirements.txt ./sidecar/
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu 
RUN pip install --no-cache-dir -r ./sidecar/requirements.txt
 
# 4. Copy Artifacts
COPY --from=backend-builder /app/backend/target/release/library-backend /app/backend/backend-bin
 
# 5. Application Code & Data
COPY sidecar/ /app/sidecar/
COPY start_hf.sh ./
 
# 6. Final Setup & Permissions
RUN mkdir -p /app/evolution/instances /app/evolution/prisma /app/sidecar /app/backend /app/dist && \
    chmod +x /app/backend/backend-bin && \
    chmod +x /app/start_hf.sh && \
    chmod -R 777 /app/evolution /app/sidecar /app/backend
 
# Environment
ENV DATABASE_PROVIDER=sqlite
ENV DATABASE_CONNECTION_URI="file:///app/evolution/prisma/evolution.db"
ENV CACHE_PROVIDER=local
ENV AUTH_API_KEY=hellowork.1234
ENV PORT=7860
ENV SERVER_PORT=8080
ENV PYTHONUNBUFFERED=1
ENV MALLOC_ARENA_MAX=2
 
EXPOSE 7860
CMD ["/app/start_hf.sh"]

