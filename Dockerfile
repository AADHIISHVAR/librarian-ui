# Stage 1: Build Svelte Frontend
FROM node:20-bookworm-slim AS frontend-builder
WORKDIR /app/frontend
COPY package*.json ./
RUN npm install --no-audit --no-fund --ignore-scripts
# Only copy what's needed for the frontend build
COPY src/ ./src/
COPY index.html vite.config.js ./
RUN NODE_OPTIONS="--max-old-space-size=2048" npm run build

# Stage 2: Build Evolution API
FROM node:20-bookworm-slim AS evolution-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg wget curl bash openssl python3 build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/evolution
# Surgical copy of Evolution API
COPY evo_whatsapp_api/evolution-api/package*.json ./
RUN npm set-script prepare "" && npm ci --no-audit --no-fund --ignore-scripts
COPY evo_whatsapp_api/evolution-api/ ./
# Prisma configuration
ENV PRISMA_CLI_BINARY_TARGETS="debian-openssl-3.0.x"
RUN npx prisma generate --schema ./prisma/sqlite-schema.prisma
# Build using tsup
RUN NODE_OPTIONS="--max-old-space-size=2048" npx tsup src/main.ts --format cjs,esm --minify --clean --sourcemap false
RUN npm prune --omit=dev && npm cache clean --force

# Stage 3: Build Rust Backend
FROM rust:1.82-slim AS backend-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend
COPY backend/Cargo.toml backend/Cargo.lock ./
# Pre-fetch dependencies
RUN cargo fetch
# Build dependencies only (cache layer)
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    CARGO_BUILD_JOBS=1 cargo build --release && \
    rm -rf src

COPY backend/src ./src
ENV CARGO_INCREMENTAL=false
ENV CARGO_BUILD_JOBS=1
ENV RUSTFLAGS="-C codegen-units=1 -C opt-level=z -C debuginfo=0 -C link-arg=-s"
RUN cargo build --release --locked

# Stage 4: Final Runtime Image
FROM python:3.11-slim

# 1. System Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ffmpeg openssl sqlite3 libsqlite3-dev build-essential \
    && rm -rf /var/lib/apt/lists/*

# 2. Node.js 20 Setup
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 3. AI Sidecar Dependencies
COPY sidecar/requirements.txt ./sidecar/
# Install torch separately to handle potential OOM or timeout better
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu 
RUN pip install --no-cache-dir -r ./sidecar/requirements.txt

# 4. Create Directory Structure
RUN mkdir -p /app/backend /app/evolution/dist /app/sidecar /app/dist

# 5. Copy Built Assets
COPY --from=backend-builder /app/backend/target/release/library-backend /app/backend/backend-bin
COPY --from=evolution-builder /app/evolution/dist /app/evolution/dist
COPY --from=evolution-builder /app/evolution/node_modules /app/evolution/node_modules
COPY --from=evolution-builder /app/evolution/package.json /app/evolution/package.json
COPY --from=evolution-builder /app/evolution/prisma /app/evolution/prisma
COPY --from=evolution-builder /app/evolution/public /app/evolution/public
COPY --from=frontend-builder /app/frontend/dist /app/dist

# 6. Final Code and Data
COPY sidecar/ /app/sidecar/
COPY uniqueBooks.db /app/uniqueBooks.db
COPY start_hf.sh ./

# Setup databases
RUN cp /app/uniqueBooks.db /app/library_database.db && \
    touch /app/ilibrary-database-all.db /app/combined-library.db
RUN chmod +x /app/start_hf.sh

# Environment
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

