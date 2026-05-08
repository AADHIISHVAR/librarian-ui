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

def main():
    conn = get_conn()
    
    # 1. Get the Accession_Nums of the first 364 books
    rows = conn.execute("""
        SELECT Accession_Num FROM Books 
        WHERE Title IS NOT NULL 
        LIMIT 364
    """).fetchall()
    
    acc_nums = [r[0] for r in rows]
    print(f"Found {len(acc_nums)} books to reset.")

    # 2. Clear descriptions and delete embeddings for these specific books
    print(f"Resetting {len(acc_nums)} books...")
    for acc_num in acc_nums:
        try:
            # Clear Description in main table
            conn.execute("UPDATE Books SET Description = NULL WHERE Accession_Num = ?", (acc_num,))
            # Delete from embedding tables
            conn.execute("DELETE FROM book_embeddings WHERE accession_num = ?", (acc_num,))
            
            # Virtual table delete (vec0)
            try:
                conn.execute("DELETE FROM vec_books WHERE accession_num = ?", (acc_num,))
            except sqlite3.Error:
                # If DELETE fails, we'll try to let the main script overwrite it later
                pass
                
        except Exception as e:
            print(f"Error resetting {acc_num}: {e}")

    conn.commit()
    conn.close()
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"  Reset Successful! ✅")
    print(f"  The first 364 books are now ready to be re-enriched.")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

if __name__ == "__main__":
    main()
