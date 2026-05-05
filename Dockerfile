# ==========================================
# Stage 1: Evolution API Builder
# ==========================================
FROM node:20-bookworm-slim AS evolution-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg wget curl bash openssl python3 build-essential ca-certificates && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/evolution
COPY evo_whatsapp_api/evolution-api/package*.json ./

# Install dependencies including devDeps for build
# Added @swc/core to support decorators during tsup build
RUN npm config set fetch-retries 10 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm config set fetch-timeout 300000 && \
    (npm install --no-audit --no-fund --ignore-scripts || npm install --no-audit --no-fund --ignore-scripts) && \
    (npm install @swc/core --no-audit --no-fund --ignore-scripts || npm install @swc/core --no-audit --no-fund --ignore-scripts)

COPY evo_whatsapp_api/evolution-api/ ./
ENV PRISMA_CLI_BINARY_TARGETS="debian-openssl-3.0.x"

# Verify files before build
RUN ls -la src/main.ts

RUN npx prisma generate --schema ./prisma/sqlite-schema.prisma

# Optimization for HF: Only CJS, no minify, no sourcemap
# Using 3072 to give enough headroom for the build
RUN NODE_OPTIONS="--max-old-space-size=3072" npx tsup src/main.ts --format cjs --clean --sourcemap false

# Keep build output stable in HF builders; pruning can fail on some npm trees.
# Size is slightly larger, but avoids non-critical build failures.

# ==========================================
# Stage 2: Rust Backend Builder
# ==========================================
FROM rust:1.85-slim AS backend-builder
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

# Pre-fetch dependencies to warm cargo cache
RUN for i in 1 2 3 4 5 6; do \
      cargo fetch && break; \
      echo "[build][cargo] fetch failed (attempt $i), retrying..." && sleep 20; \
    done

# Build real application
COPY backend/src ./src
ENV RUSTFLAGS="-C codegen-units=1 -C opt-level=z -C debuginfo=0 -C link-arg=-s"
RUN for i in 1 2 3; do \
      CARGO_BUILD_JOBS=1 cargo build --release && break; \
      echo "[build][cargo] build failed (attempt $i), retrying..." && sleep 20; \
    done

# ==========================================
# Stage 3: Final Runtime Image
# ==========================================
FROM python:3.11-slim

# 1. System Runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ffmpeg openssl sqlite3 libsqlite3-dev build-essential \
    iproute2 iputils-ping dnsutils ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. Node.js Runtime
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 3. AI Sidecar
COPY sidecar/requirements.txt ./sidecar/
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_DEFAULT_TIMEOUT=180
RUN python -m pip install --no-cache-dir --upgrade pip setuptools wheel
RUN for i in 1 2 3 4; do \
      pip install --no-cache-dir --retries 10 --timeout 180 --prefer-binary -r ./sidecar/requirements.txt && break; \
      echo "[build][pip] requirements install failed on pypi (attempt $i), retrying..." && sleep 20; \
    done || \
    pip install --no-cache-dir --retries 10 --timeout 180 --prefer-binary -r ./sidecar/requirements.txt --extra-index-url https://download.pytorch.org/whl/cpu

# 4. Copy Artifacts
COPY --from=backend-builder /app/backend/target/release/library-backend /app/backend/backend-bin
COPY --from=evolution-builder /app/evolution/dist /app/evolution/dist
COPY --from=evolution-builder /app/evolution/node_modules /app/evolution/node_modules
COPY --from=evolution-builder /app/evolution/package.json /app/evolution/package.json
COPY --from=evolution-builder /app/evolution/prisma /app/evolution/prisma
COPY --from=evolution-builder /app/evolution/public /app/evolution/public

# 5. Application Code & Data
COPY sidecar/ /app/sidecar/
COPY uniqueBooks.db /app/uniqueBooks.db
COPY start_hf.sh ./

# 6. Final Setup & Permissions
RUN mkdir -p /app/evolution/instances /app/evolution/prisma && \
    chmod +x /app/backend/backend-bin && \
    chmod +x /app/start_hf.sh && \
    cp /app/uniqueBooks.db /app/library_database.db && \
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
