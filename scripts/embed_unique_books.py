import sqlite3
import sqlite_vec
import os
import sys
import struct
import time

DB_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "../uniqueBooks_ai enhances.db"))

def get_conn():
    conn = sqlite3.connect(DB_PATH, timeout=60.0)
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.row_factory = sqlite3.Row
    return conn

def vector_to_blob(vector):
    return struct.pack(f"{len(vector)}f", *vector)

def setup_vec_table(conn):
    print("Setting up vector tables...")
    conn.execute("DROP TABLE IF EXISTS vec_books")
    conn.execute("DROP TABLE IF EXISTS book_embeddings")
    
    conn.execute("""
        CREATE TABLE book_embeddings (
            accession_num TEXT PRIMARY KEY,
            embedding      BLOB NOT NULL
        );
    """)
    conn.execute("""
        CREATE VIRTUAL TABLE vec_books
        USING vec0(
            accession_num TEXT PRIMARY KEY,
            embedding     float[384]
        );
    """)
    conn.commit()

def main():
    if not os.path.exists(DB_PATH):
        print(f"Error: Database not found at {DB_PATH}")
        sys.exit(1)
        
    print(f"Opening database: {DB_PATH}")
    conn = get_conn()
    
    # 1. Fetch all books with AI enriched fields
    rows = conn.execute("""
        SELECT acc_no, title, author, description, key_topics, target_audience, ai_keywords, search_blob
        FROM unique_books
    """).fetchall()
    
    total = len(rows)
    print(f"Found {total} books to embed.")
    
    # 2. Setup vec tables
    setup_vec_table(conn)
    
    # 3. Initialize embedder
    print("Initializing SentenceTransformer...")
    try:
        from sentence_transformers import SentenceTransformer
        model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
        print("Using local sentence-transformers model.")
        use_local = True
    except ImportError:
        print("sentence-transformers not installed or failed to import. Cannot run local embeddings.")
        sys.exit(1)
        
    # 4. Generate and save embeddings
    start_time = time.time()
    batch_size = 128
    
    for i in range(0, total, batch_size):
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
            
            # Combine fields to form a rich representation
            parts = [f"Title: {title}", f"Author: {author}"]
            if description:
                parts.append(f"Description: {description}")
            if target_audience:
                parts.append(f"Target Audience: {target_audience}")
            if key_topics:
                parts.append(f"Key Topics: {key_topics}")
            if ai_keywords:
                parts.append(f"Keywords: {ai_keywords}")
                
            text = ". ".join(parts)
            texts.append(text)
            acc_nos.append(acc_no)
            
        # Embed batch
        embeddings = model.encode(texts, show_progress_bar=False)
        
        # Save to DB
        for acc_no, emb in zip(acc_nos, embeddings):
            blob = vector_to_blob(emb.tolist())
            conn.execute("REPLACE INTO book_embeddings (accession_num, embedding) VALUES (?, ?)", (acc_no, blob))
            conn.execute("INSERT INTO vec_books (accession_num, embedding) VALUES (?, ?)", (acc_no, blob))
            
        conn.commit()
        elapsed = time.time() - start_time
        avg_time = elapsed / (i + len(batch_rows))
        remaining = avg_time * (total - (i + len(batch_rows)))
        print(f"Embedded {i + len(batch_rows)}/{total} books (ETA: {remaining/60:.1f}m)...")
        
    print("Verification:")
    count = conn.execute("SELECT COUNT(*) FROM vec_books").fetchone()[0]
    print(f"Successfully populated vec_books with {count} entries.")
    conn.close()

if __name__ == "__main__":
    main()
