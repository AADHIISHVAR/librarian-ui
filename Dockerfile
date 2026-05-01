# Stage 1: Build Rust Backend (Axum)
FROM rust:1.82-slim AS backend-builder
RUN apt-get update && apt-get install -y pkg-config libssl-dev build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /app/backend
COPY backend/ .
# Aggressive memory optimization for Rust build
ENV CARGO_INCREMENTAL=false
ENV CARGO_BUILD_JOBS=1
ENV RUSTFLAGS="-C codegen-units=1 -C opt-level=s -C debuginfo=0"
RUN cargo build --release

# Stage 2: Build Evolution API
FROM node:20-slim AS evolution-builder
RUN apt-get update && apt-get install -y git ffmpeg wget curl bash openssl python3 build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /app/evolution
COPY evo_whatsapp_api/evolution-api/package*.json ./
# Use npm install instead of ci for better resilience against lockfile mismatches on server
RUN npm install --no-audit --no-fund
COPY evo_whatsapp_api/evolution-api/ ./
RUN npx prisma generate --schema ./prisma/sqlite-schema.prisma
ENV NODE_OPTIONS="--max-old-space-size=1536"
RUN npm run build && \
    npm prune --omit=dev && \
    npm cache clean --force

# Stage 3: Build Svelte Frontend
FROM node:20-slim AS frontend-builder
WORKDIR /app/frontend
COPY package*.json ./
RUN npm install --no-audit --no-fund
COPY . .
ENV NODE_OPTIONS="--max-old-space-size=1536"
RUN npm run build

# Stage 4: Final Runtime Image
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    curl nodejs npm ffmpeg openssl sqlite3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Sidecar Dependencies (CPU version of torch is smaller)
COPY sidecar/requirements.txt ./sidecar/
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r ./sidecar/requirements.txt

RUN mkdir -p /app/backend /app/evolution/dist

# Copy built components
COPY --from=backend-builder /app/backend/target/release/library-backend /app/backend/backend-bin
COPY --from=evolution-builder /app/evolution/dist /app/evolution/dist
COPY --from=evolution-builder /app/evolution/node_modules /app/evolution/node_modules
COPY --from=evolution-builder /app/evolution/package.json /app/evolution/package.json
COPY --from=evolution-builder /app/evolution/prisma /app/evolution/prisma
COPY --from=evolution-builder /app/evolution/public /app/evolution/public
COPY --from=frontend-builder /app/frontend/dist /app/dist

# Copy Sidecar and Assets
COPY sidecar/ /app/sidecar/
# Only copy available databases
COPY uniqueBooks.db /app/uniqueBooks.db
# Create placeholders if databases are missing to prevent backend panic
RUN cp /app/uniqueBooks.db /app/library_database.db && \
    touch /app/ilibrary-database-all.db /app/combined-library.db

COPY start_hf.sh ./
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
