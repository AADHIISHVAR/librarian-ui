import sqlite3
import os
import time
from embedder import get_embedding
from db import upsert_embedding, search_books, get_conn, setup_vec_table

# Connect to your SQLite database
DB_PATH = os.getenv("DB_PATH", "../library_database.db")

def embed_all_books():
    if not os.path.exists(DB_PATH):
        print(f"Error: {DB_PATH} not found!")
        return

    setup_vec_table()
    conn = get_conn()
    
    # Get all books with more metadata columns
    rows = conn.execute("""
        SELECT 
            Accession_Num, Title, Author, Library, 
            Edition, Publisher, Keywords, Subject,
            Year_of_Publishing, Language, Department
        FROM Books
    """).fetchall()
    
    if not rows:
        print("No books found in database. ❌")
        conn.close()
        return

    print(f"[embed] Found {len(rows)} books to embed...")

    start_time = time.time()
    for i, row in enumerate(rows):
        # Construct much richer text for better matching (increased "depth")
        title = row["Title"] or ""
        parts = [
            f"Title: {title}",
            f"Author: {row['Author'] or 'Unknown'}",
            f"Library: {row['Library'] or ''}",
            f"Edition: {row['Edition'] or ''}",
            f"Publisher: {row['Publisher'] or ''}",
            f"Year: {row['Year_of_Publishing'] or ''}",
            f"Language: {row['Language'] or ''}",
            f"Department: {row['Department'] or ''}",
            f"Keywords: {row['Keywords'] or ''}",
            f"Subject: {row['Subject'] or ''}"
        ]
        # remove empty or filler parts
        parts = [p for p in parts if p.split(": ", 1)[-1].strip() not in ("", "-", "None", "Unknown")]
        text = ". ".join(parts)
        
        try:
            # Task: search_document is used for the database entries
            vector = get_embedding(text, task="search_document")
            
            # Use the shared connection, don't commit yet
            upsert_embedding(row["Accession_Num"], vector, conn=conn)
            
            if (i + 1) % 100 == 0:
                conn.commit() # Batch commit every 100 books
                elapsed = time.time() - start_time
                per_book = elapsed / (i + 1)
                remaining = per_book * (len(rows) - (i + 1))
                print(f"  Processed {i+1}/{len(rows)} books... (ETA: {remaining/60:.1f}m)")
        
        except Exception as e:
            print(f"Error embedding book {row['Accession_Num']}: {e}")

    conn.commit() # Final commit
    conn.close()
    print("[embed] All books embedded successfully! ✅")

def sanity_check():
    from embedder import get_embedding
    from db import search_books

    print("\n[sanity] Testing search...")
    vec    = get_embedding("computer architecture", task="search_query")
    result = search_books(vec, top_k=3)

    if not result:
        print("[sanity] ❌ No results — vec_books may be empty")
        return

    for r in result:
        print(f"  {r['similarity']:.4f} → {r['title']}")

    if result[0]["similarity"] > 0.6:
        print("[sanity] ✅ Embeddings working correctly")
    else:
        # Note: with 1 - distance, if distance is ~1.77, similarity is ~-0.77.
        # But if it's working well, distance should be < 0.4, so similarity > 0.6.
        print("[sanity] ⚠️  Scores still low — check sqlite-vec version")

if __name__ == "__main__":
    # Drop and recreate for a clean start as requested
    conn = get_conn()
    print("Dropping old vector tables for a clean start...")
    try:
        # Dropping is much more robust for virtual tables
        conn.execute("DROP TABLE IF EXISTS vec_books")
        conn.execute("DROP TABLE IF EXISTS book_embeddings")
        conn.commit()
    except Exception as e:
        print(f"Cleanup warning: {e}")
    conn.close()
    
    setup_vec_table()
    embed_all_books()
    sanity_check()
