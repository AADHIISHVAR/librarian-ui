import sqlite3
import json
import os
from sidecar.embedder import get_embedding

# Connect to your SQLite database
DB_PATH = "library_database.db"

def embed_all_books():
    if not os.path.exists(DB_PATH):
        print(f"Error: {DB_PATH} not found!")
        return

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Get books that haven't been embedded yet
    # Adjust column names if they differ in your schema
    cur.execute("""
        SELECT id, title, author, shelf, summary 
        FROM books 
        WHERE embedding IS NULL OR embedding = ''
    """)
    
    books = cur.fetchall()
    if not books:
        print("No new books to embed. ✅")
        return

    print(f"Found {len(books)} books to embed...")

    for i, (book_id, title, author, shelf, summary) in enumerate(books):
        # Construct meaningful text for the embedding
        # Task: search_document is used for the database entries
        text = f"Title: {title}. Author: {author}. Shelf: {shelf}. Summary: {summary}"
        
        try:
            vector = get_embedding(text, task="search_document")
            
            # Store vector as JSON string in SQLite
            cur.execute(
                "UPDATE books SET embedding = ? WHERE id = ?",
                (json.dumps(vector), book_id)
            )
            
            if (i + 1) % 50 == 0:
                conn.commit()
                print(f"  Processed {i+1}/{len(books)} books...")
        
        except Exception as e:
            print(f"Error embedding book {book_id}: {e}")

    conn.commit()
    cur.close()
    conn.close()
    print("All books embedded successfully! ✅")

if __name__ == "__main__":
    embed_all_books()
