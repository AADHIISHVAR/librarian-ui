import os
import sqlite3
import sqlite_vec
import struct
import time
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer
from typing import List

app = FastAPI(
    title="Librarian AI - Vector Search Space",
    description="Vector search service for library catalog powered by sqlite-vec and sentence-transformers.",
    version="1.1.0"
)

# Enable CORS for direct frontend interaction
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database path (relative to the app on Hugging Face Space)
DB_PATH = os.environ.get("DB_PATH", "uniqueBooks_ai_enhances.db")
model = None

def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.row_factory = sqlite3.Row
    return conn

def clean_prompt(prompt: str) -> str:
    """Removes conversational prefix filler to focus the semantic embedding vector."""
    prefixes = [
        "i want to learn about how to",
        "i want to learn about how",
        "i want to learn about",
        "i want to know about",
        "i want to find books about",
        "i am looking for books about",
        "looking for books about",
        "can you suggest books about",
        "can you find books about",
        "books about",
        "how to",
        "about",
    ]
    p_lower = prompt.lower().strip()
    for prefix in prefixes:
        if p_lower.startswith(prefix):
            p_lower = p_lower[len(prefix):].strip()
            
    # Remove trailing question marks/punctuation
    p_lower = p_lower.rstrip("?").rstrip(".").rstrip("!")
    return p_lower.strip() or prompt

@app.on_event("startup")
def startup_event():
    global model
    print("Loading sentence-transformers model (all-MiniLM-L6-v2)...")
    try:
        model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
        print("Model loaded successfully!")
    except Exception as e:
        print(f"Error loading model: {e}")
        model = None
        return

    # Check database and compile embeddings if they are missing or empty
    if not os.path.exists(DB_PATH):
        print(f"Database not found at {DB_PATH}. Startup database initialization skipped.")
        return

    try:
        conn = get_conn()
        
        # 1. Setup tables if not exists
        conn.execute("""
            CREATE TABLE IF NOT EXISTS book_embeddings (
                accession_num TEXT PRIMARY KEY,
                embedding      BLOB NOT NULL
            );
        """)
        conn.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS vec_books
            USING vec0(
                accession_num TEXT PRIMARY KEY,
                embedding     float[384]
            );
        """)
        conn.commit()
        
        # Check current count of embeddings vs unique books
        emb_count = conn.execute("SELECT COUNT(*) FROM vec_books").fetchone()[0]
        book_count = conn.execute("SELECT COUNT(*) FROM unique_books").fetchone()[0]
        
        print(f"Database stats: {emb_count} embeddings / {book_count} books in catalog.")
        
        if emb_count < book_count:
            print("Generating missing embeddings on Hugging Face Space startup...")
            
            # Find books that do not have embeddings in the database yet
            rows = conn.execute("""
                SELECT acc_no, title, author, description, key_topics, target_audience, ai_keywords
                FROM unique_books
                WHERE CAST(acc_no AS TEXT) NOT IN (SELECT accession_num FROM book_embeddings)
            """).fetchall()
            
            print(f"Need to embed {len(rows)} books...")
            
            batch_size = 128
            start_time = time.time()
            
            for i in range(0, len(rows), batch_size):
                batch_rows = rows[i:i+batch_size]
                texts = []
                acc_nos = []
                
                for r in batch_rows:
                    acc_no = str(r["acc_no"])
                    title = r["title"] or ""
                    author = r["author"] or ""
                    description = r["description"] or ""
                    target_audience = r["target_audience"] or ""
                    key_topics = r["key_topics"] or ""
                    ai_keywords = r["ai_keywords"] or ""
                    
                    # Combine fields to build a rich search context
                    parts = [f"Title: {title}", f"Author: {author}"]
                    if description:
                        parts.append(f"Description: {description}")
                    if target_audience:
                        parts.append(f"Target Audience: {target_audience}")
                    if key_topics:
                        parts.append(f"Key Topics: {key_topics}")
                    if ai_keywords:
                        parts.append(f"Keywords: {ai_keywords}")
                        
                    texts.append(". ".join(parts))
                    acc_nos.append(acc_no)
                
                # Generate embeddings for the batch
                embeddings = model.encode(texts, show_progress_bar=False)
                
                # Store embeddings in the database
                for acc_no, emb in zip(acc_nos, embeddings):
                    blob = struct.pack(f"{len(emb)}f", *emb)
                    conn.execute("REPLACE INTO book_embeddings (accession_num, embedding) VALUES (?, ?)", (acc_no, blob))
                    conn.execute("DELETE FROM vec_books WHERE accession_num = ?", (acc_no,))
                    conn.execute("INSERT INTO vec_books (accession_num, embedding) VALUES (?, ?)", (acc_no, blob))
                    
                conn.commit()
                print(f"Embedded {i + len(batch_rows)}/{len(rows)} books...")
                
            print(f"Successfully generated all embeddings in {time.time() - start_time:.2f} seconds!")
        else:
            print("Vector database is fully populated. No action needed.")
            
        conn.close()
    except Exception as e:
        print(f"Error during startup database initialization: {e}")

class SearchRequest(BaseModel):
    prompt: str
    limit: int = 10

@app.post("/search")
def search_books(req: SearchRequest):
    if not os.path.exists(DB_PATH):
        raise HTTPException(
            status_code=500, 
            detail=f"Database file '{DB_PATH}' not found in Space directory."
        )
    if model is None:
        raise HTTPException(
            status_code=500,
            detail="Embedding model is not loaded."
        )
    if not req.prompt.strip():
        return {"acc_nos": [], "similarities": []}

    try:
        # 1. Clean the user's conversational prompt
        cleaned = clean_prompt(req.prompt)
        print(f"Original prompt: '{req.prompt}' -> Cleaned prompt: '{cleaned}'")
        
        # 2. Generate text embedding for the search prompt
        query_vector = model.encode(cleaned).tolist()
        
        # 3. Pack vector into binary blob for sqlite-vec
        query_blob = struct.pack(f"{len(query_vector)}f", *query_vector)
        
        # 4. Query the virtual vector table vec_books
        conn = get_conn()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT accession_num, distance
            FROM vec_books
            WHERE embedding MATCH ?
              AND k = ?
            ORDER BY distance
        """, (query_blob, req.limit))
        
        rows = cursor.fetchall()
        acc_nos = []
        similarities = []
        
        for row in rows:
            acc_nos.append(row["accession_num"])
            # Calculate cosine similarity from L2 distance of normalized vectors: S = 1.0 - d^2 / 2.0
            d = float(row["distance"])
            sim = round(1.0 - (d * d) / 2.0, 4)
            # Clip similarity between 0.0 and 1.0
            sim = max(0.0, min(1.0, sim))
            similarities.append(sim)
            
        conn.close()
        
        return {"acc_nos": acc_nos, "similarities": similarities}
        
    except Exception as e:
        print(f"Search error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
def health():
    return {
        "status": "ok", 
        "db_exists": os.path.exists(DB_PATH), 
        "model_loaded": model is not None
    }
