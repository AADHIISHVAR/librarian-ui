# Stage 1: Build Rust Backend (Axum)
FROM rust:1.82-slim AS backend-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend
# Use the fixed Cargo.lock
COPY backend/Cargo.toml backend/Cargo.lock ./

# Step 1: Compile dependencies only (Cacheable)
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    CARGO_BUILD_JOBS=1 cargo build --release && \
    rm -rf src

# Step 2: Build final binary
COPY backend/src ./src
ENV CARGO_INCREMENTAL=false
ENV CARGO_BUILD_JOBS=1
ENV RUSTFLAGS="-C codegen-units=1 -C opt-level=z -C debuginfo=0"
RUN cargo build --release --locked

# Stage 2: Build Evolution API
FROM node:20-bookworm-slim AS evolution-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg wget curl bash openssl python3 build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/evolution
COPY evo_whatsapp_api/evolution-api/package*.json ./
# Clean install for reliability
RUN npm set-script prepare "" && npm ci --no-audit --no-fund --ignore-scripts
COPY evo_whatsapp_api/evolution-api/ ./
# Explicitly set binary target for Prisma
ENV PRISMA_CLI_BINARY_TARGETS="debian-openssl-3.0.x"
RUN npx prisma generate --schema ./prisma/sqlite-schema.prisma
ENV NODE_OPTIONS="--max-old-space-size=2048"
# Build (skipping memory-heavy tsc)
RUN npx tsup src/main.ts --format cjs,esm --minify --clean --sourcemap false && \
    npm prune --omit=dev && \
    npm cache clean --force

# Stage 3: Build Svelte Frontend
FROM node:20-bookworm-slim AS frontend-builder
WORKDIR /app/frontend
COPY package*.json ./
RUN npm install --no-audit --no-fund --ignore-scripts
COPY src/ ./src/
COPY index.html vite.config.js package.json ./
ENV NODE_OPTIONS="--max-old-space-size=2048"
RUN npm run build

# Stage 4: Final Runtime Image
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ffmpeg openssl sqlite3 libsqlite3-dev build-essential \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Sidecar Dependencies (Checkpointable)
COPY sidecar/requirements.txt ./sidecar/
# Install Torch separately to avoid OOM during multi-package resolution
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu 
RUN pip install --no-cache-dir -r ./sidecar/requirements.txt

# Create necessary directories
RUN mkdir -p /app/backend /app/evolution/dist /app/sidecar /app/dist

# Copy built components from stages
COPY --from=backend-builder /app/backend/target/release/library-backend /app/backend/backend-bin
COPY --from=evolution-builder /app/evolution/dist /app/evolution/dist
COPY --from=evolution-builder /app/evolution/node_modules /app/evolution/node_modules
COPY --from=evolution-builder /app/evolution/package.json /app/evolution/package.json
COPY --from=evolution-builder /app/evolution/prisma /app/evolution/prisma
COPY --from=evolution-builder /app/evolution/public /app/evolution/public
COPY --from=frontend-builder /app/frontend/dist /app/dist

# Copy Sidecar code and Assets from context
COPY sidecar/ /app/sidecar/
COPY uniqueBooks.db /app/uniqueBooks.db
COPY start_hf.sh ./

# Setup databases
RUN cp /app/uniqueBooks.db /app/library_database.db && \
    touch /app/ilibrary-database-all.db /app/combined-library.db

RUN chmod +x /app/start_hf.sh

# Environment variables
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
