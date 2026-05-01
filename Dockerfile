# ==========================================
# Stage 1: Svelte Frontend Builder
# ==========================================
FROM node:20-bookworm-slim AS frontend-builder
WORKDIR /app/frontend

# Copy dependencies first for caching
COPY package*.json ./
RUN npm install --no-audit --no-fund --ignore-scripts

# Copy all source files
COPY . .
# Explicitly set memory limit for Vite
RUN NODE_OPTIONS="--max-old-space-size=2048" npm run build

# ==========================================
# Stage 2: Evolution API Builder
# ==========================================
FROM node:20-bookworm-slim AS evolution-builder

# FORCE LINEARITY: Ensure this stage waits for the previous one to finish
# to keep cumulative RAM usage low on Hugging Face shared builders.
COPY --from=frontend-builder /app/frontend/dist /tmp/dummy_frontend

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg wget curl bash openssl python3 build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/evolution

# Copy package files
COPY evo_whatsapp_api/evolution-api/package*.json ./
RUN npm set-script prepare "" && npm ci --no-audit --no-fund --ignore-scripts

# Copy full source
COPY evo_whatsapp_api/evolution-api/ ./

# Generate Prisma client
ENV PRISMA_CLI_BINARY_TARGETS="debian-openssl-3.0.x"
RUN npx prisma generate --schema ./prisma/sqlite-schema.prisma

# Build the app using tsup
RUN NODE_OPTIONS="--max-old-space-size=2048" npx tsup src/main.ts --format cjs,esm --minify --clean --sourcemap false

# Clean up dev dependencies to keep the image small
RUN npm prune --omit=dev && npm cache clean --force

# ==========================================
# Stage 3: Rust Backend Builder
# ==========================================
FROM rust:1.82-slim AS backend-builder

# FORCE LINEARITY
COPY --from=evolution-builder /app/evolution/dist /tmp/dummy_evolution

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend

# Copy Cargo files
COPY backend/Cargo.toml backend/Cargo.lock ./

# Cache dependencies
RUN cargo fetch
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    CARGO_BUILD_JOBS=1 cargo build --release && \
    rm -rf src

# Copy source and build
COPY backend/src ./src
ENV CARGO_INCREMENTAL=false
ENV CARGO_BUILD_JOBS=1
ENV RUSTFLAGS="-C codegen-units=1 -C opt-level=z -C debuginfo=0 -C link-arg=-s"
RUN cargo build --release --locked

# ==========================================
# Stage 4: Final Runtime Stage
# ==========================================
FROM python:3.11-slim

# FORCE LINEARITY
COPY --from=backend-builder /app/backend/target/release/library-backend /tmp/dummy_backend

# 1. Install System Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ffmpeg openssl sqlite3 libsqlite3-dev build-essential \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Node.js (needed to run Evolution API)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 3. Python Dependencies (AI Sidecar)
COPY sidecar/requirements.txt ./sidecar/
# Install torch separately with index-url for CPU (saves several GB and RAM)
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu 
RUN pip install --no-cache-dir -r ./sidecar/requirements.txt

# 4. Prepare Directories
RUN mkdir -p /app/backend /app/evolution/dist /app/sidecar /app/dist

# 5. Copy Artifacts from Builder Stages
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

# 7. Final Setup
RUN cp /app/uniqueBooks.db /app/library_database.db && \
    touch /app/ilibrary-database-all.db /app/combined-library.db && \
    chmod +x /app/start_hf.sh

# Environment Variables
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
