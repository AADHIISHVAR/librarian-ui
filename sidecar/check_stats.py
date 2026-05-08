import sqlite3
import sqlite_vec
import os
from dotenv import load_dotenv

load_dotenv()
DB_PATH = os.getenv("DB_PATH", "../library_database.db")

def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.row_factory = sqlite3.Row
    return conn

try:
    conn = get_conn()
    enriched = conn.execute("SELECT COUNT(*) FROM Books WHERE Description IS NOT NULL").fetchone()[0]
    embedded = conn.execute("SELECT COUNT(*) FROM book_embeddings").fetchone()[0]
    vec_indexed = conn.execute("SELECT COUNT(*) FROM vec_books").fetchone()[0]
    
    print(f"Enriched:    {enriched}")
    print(f"Embedded:    {embedded}")
    print(f"Vec Indexed: {vec_indexed}")
    
except Exception as e:
    print(f"Error: {e}")
finally:
    if 'conn' in locals():
        conn.close()
