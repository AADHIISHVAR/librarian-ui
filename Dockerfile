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
RUN npm config set fetch-retries 10 && \
    npm install --no-audit --no-fund --ignore-scripts

COPY evo_whatsapp_api/evolution-api/ ./
ENV PRISMA_CLI_BINARY_TARGETS="debian-openssl-3.0.x"

# CRITICAL: Disable the onSuccess hook in tsup.config.ts to avoid crashes
# and handle the copy manually in the Dockerfile
RUN sed -i '/onSuccess:/,+3d' tsup.config.ts || true

RUN npx prisma generate --schema ./prisma/sqlite-schema.prisma

# Optimization for HF: No minify, no sourcemap, more memory headroom
# We use --no-minify explicitly to override any config file settings
# This prevents the OOM crashes during the bundling phase
RUN NODE_OPTIONS="--max-old-space-size=4096" npx tsup src/main.ts \
    --format cjs \
    --clean \
    --no-minify \
    --no-sourcemap \
    --no-splitting

# Manually copy translations since we disabled the hook
RUN mkdir -p dist/translations && cp -r src/utils/translations/* dist/translations/ || echo "No translations found"

# Remove devDependencies to keep the final image small
RUN npm prune --omit=dev && npm cache clean --force

# ==========================================
# Stage 2: Rust Backend Builder
# ==========================================
FROM rust:1.85-slim AS backend-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev build-essential ca-certificates git curl && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend
COPY backend/Cargo.toml backend/Cargo.lock ./

# Create dummy source to allow cargo to fetch/build dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo fetch
# Using CARGO_BUILD_JOBS=1 to avoid OOM on Hugging Face Builders
RUN CARGO_BUILD_JOBS=1 cargo build --release && rm -rf src

# Copy real source and build
COPY backend/src ./src
ENV RUSTFLAGS="-C codegen-units=1 -C opt-level=z -C debuginfo=0 -C link-arg=-s"
RUN CARGO_BUILD_JOBS=1 cargo build --release --locked

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

# 2. Node.js for Evolution API
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
RUN mkdir -p /app/evolution/instances /app/evolution/prisma /app/sidecar /app/backend /app/dist && \
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
