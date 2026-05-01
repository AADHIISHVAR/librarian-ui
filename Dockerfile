# ==========================================
# Stage 1: Svelte Frontend Builder
# ==========================================
FROM node:20-bookworm-slim AS frontend-builder
WORKDIR /app/frontend

# 1. Install dependencies (Very stable)
COPY package*.json ./
RUN npm install --no-audit --no-fund --ignore-scripts

# 2. Copy source and build (Changes frequently)
COPY src/ ./src/
COPY index.html vite.config.js ./
RUN NODE_OPTIONS="--max-old-space-size=2048" npm run build

# ==========================================
# Stage 2: Evolution API Builder
# ==========================================
FROM node:20-bookworm-slim AS evolution-builder
# Install system tools first (Stable)
RUN apt-get update && apt-get install -y --no-install-recommends git ffmpeg wget curl bash openssl python3 build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /app/evolution

# 1. Install dependencies (Stable unless package.json changes)
COPY evo_whatsapp_api/evolution-api/package*.json ./
RUN npm set-script prepare "" && npm ci --no-audit --no-fund --ignore-scripts

# 2. FORCE LINEARITY HERE (After dependencies are cached)
# This ensures we don't build the Evolution source in parallel with Frontend
COPY --from=frontend-builder /app/frontend/dist /tmp/dummy_frontend

# 3. Copy source and generate Prisma
COPY evo_whatsapp_api/evolution-api/prisma/ ./prisma/
COPY evo_whatsapp_api/evolution-api/src/ ./src/
COPY evo_whatsapp_api/evolution-api/tsup.config.ts evo_whatsapp_api/evolution-api/tsconfig.json ./
COPY evo_whatsapp_api/evolution-api/public/ ./public/
COPY evo_whatsapp_api/evolution-api/runWithProvider.js ./

# Generate Prisma client
ENV PRISMA_CLI_BINARY_TARGETS="debian-openssl-3.0.x"
RUN npx prisma generate --schema ./prisma/sqlite-schema.prisma

# 4. Build (Heavy RAM usage)
RUN NODE_OPTIONS="--max-old-space-size=2048" npx tsup src/main.ts --format cjs,esm --minify --clean --sourcemap false
RUN npm prune --omit=dev && npm cache clean --force

# ==========================================
# Stage 3: Rust Backend Builder
# ==========================================
FROM rust:1.82-slim AS backend-builder
# Install build tools (Stable)
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config libssl-dev build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend

# 1. Fetch dependencies (Stable)
COPY backend/Cargo.toml backend/Cargo.lock ./
RUN cargo fetch

# 2. Pre-build dependencies (Very effective cache layer)
RUN mkdir src && echo "fn main() {}" > src/main.rs && CARGO_BUILD_JOBS=1 cargo build --release && rm -rf src

# 3. FORCE LINEARITY HERE (Before heavy final compilation)
COPY --from=evolution-builder /app/evolution/dist /tmp/dummy_evolution

# 4. Final compilation
COPY backend/src ./src
ENV CARGO_INCREMENTAL=false
ENV CARGO_BUILD_JOBS=1
ENV RUSTFLAGS="-C codegen-units=1 -C opt-level=z -C debuginfo=0 -C link-arg=-s"
RUN cargo build --release --locked

# ==========================================
# Stage 4: Final Runtime Stage
# ==========================================
FROM python:3.11-slim

# 1. System Dependencies (Absolute top for max cache)
RUN apt-get update && apt-get install -y --no-install-recommends curl ffmpeg openssl sqlite3 libsqlite3-dev build-essential && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y --no-install-recommends nodejs && rm -rf /var/lib/apt/lists/*

# 2. AI Dependencies (Torch is huge, cache it early)
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu 

WORKDIR /app

# 3. AI Sidecar specific deps
COPY sidecar/requirements.txt ./sidecar/
RUN pip install --no-cache-dir -r ./sidecar/requirements.txt

# 4. Final LINEARITY & Artifact Copy
COPY --from=backend-builder /app/backend/target/release/library-backend /app/backend/backend-bin
COPY --from=evolution-builder /app/evolution/dist /app/evolution/dist
COPY --from=evolution-builder /app/evolution/node_modules /app/evolution/node_modules
COPY --from=evolution-builder /app/evolution/package.json /app/evolution/package.json
COPY --from=evolution-builder /app/evolution/prisma /app/evolution/prisma
COPY --from=evolution-builder /app/evolution/public /app/evolution/public
COPY --from=frontend-builder /app/frontend/dist /app/dist

# 5. Final Code and Data
COPY sidecar/ /app/sidecar/
COPY uniqueBooks.db /app/uniqueBooks.db
COPY start_hf.sh ./

RUN cp /app/uniqueBooks.db /app/library_database.db && touch /app/ilibrary-database-all.db /app/combined-library.db && chmod +x /app/start_hf.sh

ENV DATABASE_PROVIDER=sqlite
ENV DATABASE_CONNECTION_URI="file:/app/evolution/prisma/evolution.db"
ENV CACHE_PROVIDER=local
ENV AUTH_API_KEY=hellowork.1234
ENV PORT=7860
ENV SERVER_PORT=8080
ENV PYTHONUNBUFFERED=1
ENV MALLOC_ARENA_MAX=2

EXPOSE 7860
CMD ["/app/start_hf.sh"]
