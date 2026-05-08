import sqlite3

def clean_db():
    conn = sqlite3.connect('library_database.db')
    cur = conn.cursor()
    
    print("Cleaning Accession_Num from both tables...")
    # Strip literal single quotes from Books
    cur.execute("UPDATE Books SET Accession_Num = REPLACE(Accession_Num, \"'\", '')")
    # Strip literal single quotes from vec_books (if any)
    # Note: vec_books doesn't support REPLACE directly on virtual tables, 
    # so we'll just ensure the join works by cleaning Books.
    
    conn.commit()
    
    # Check first 3
    cur.execute("SELECT Accession_Num FROM Books LIMIT 3")
    print("New Accession_Num samples:", cur.fetchall())
    conn.close()

if __name__ == "__main__":
    clean_db()
