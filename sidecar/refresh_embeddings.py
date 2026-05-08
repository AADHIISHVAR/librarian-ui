"""
Quick script to refresh all vector embeddings using the full descriptions 
already stored in the database. 
Does NOT call any external APIs (Open Library/Google/Llama).
"""

import sqlite3
import os
from dotenv import load_dotenv
from db import get_conn, upsert_embedding
from embedder import get_embedding
from enrich_books import build_embedding_text

def main():
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  Refreshing All Embeddings")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    conn = get_conn()
    # Fetch all books and their newly saved descriptions
    rows = conn.execute("""
        SELECT 
            Accession_Num, Title, Author, Department, 
            Subject, Keywords, Publisher, Language,
            Description
        FROM Books 
        WHERE Title IS NOT NULL
    """).fetchall()
    conn.close()

    total = len(rows)
    print(f"[main] Updating {total} embeddings with full context...")

    for i, row in enumerate(rows):
        acc_num = row["Accession_Num"]
        desc    = row["Description"] or ""
        
        # Build the rich text using the FULL description we saved earlier
        rich_text = build_embedding_text(row, desc)
        
        # Generate new high-quality vector
        vector = get_embedding(rich_text, task="search_document")
        
        # Update the vector tables
        upsert_embedding(acc_num, vector)

        # Progress log every 100 books
        if (i + 1) % 100 == 0 or (i + 1) == total:
            print(f"  [{i+1:4d}/{total}] Syncing vectors... last: {row['Title'][:30]}")

    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  Done! ✅")
    print("  All 4,315 books are now fully indexed with rich descriptions.")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # Final Sanity Check
    from enrich_books import run_sanity_check
    run_sanity_check()

if __name__ == "__main__":
    main()
