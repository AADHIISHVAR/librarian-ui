import sqlite3
import json
import random

# Connect to DB
conn = sqlite3.connect("library_database.db")
cur = conn.cursor()

# Create table if not exists
cur.execute("CREATE TABLE IF NOT EXISTS book_embeddings (accession_num TEXT PRIMARY KEY, embedding BLOB NOT NULL)")

# Fetch all books
cur.execute("SELECT Accession_Num FROM Books")
books = cur.fetchall()

print(f"Mock embedding {len(books)} books...")

for b in books:
    acc_num = b[0]
    # Mock a 768-dimensional vector
    embedding = [random.uniform(-0.1, 0.1) for _ in range(768)]
    embedding_blob = json.dumps(embedding).encode('utf-8')
    
    cur.execute(
        "INSERT OR REPLACE INTO book_embeddings (accession_num, embedding) VALUES (?, ?)",
        (acc_num, embedding_blob)
    )

conn.commit()
cur.close()
conn.close()
print("Mock Ingestion complete!")
