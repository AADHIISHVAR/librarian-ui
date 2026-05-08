-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create books table
CREATE TABLE IF NOT EXISTS books (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    author TEXT NOT NULL,
    library TEXT NOT NULL,
    shelf_location TEXT NOT NULL,
    available BOOLEAN DEFAULT TRUE,
    embedding VECTOR(768) -- nomic-embed-text-v1.5 is 768 dimensions
);

-- Create index for vector similarity search
CREATE INDEX ON books USING hnsw (embedding vector_cosine_ops);
