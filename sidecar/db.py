import sqlite3
import sqlite_vec
import numpy as np
import struct
import os
from dotenv import load_dotenv

load_dotenv()
DB_PATH = os.getenv("DB_PATH", "/app/library_database.db")


def get_conn():
    # Set a 60s timeout so it waits for locks to clear
    conn = sqlite3.connect(DB_PATH, timeout=60.0)
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.row_factory = sqlite3.Row
    return conn


def vector_to_blob(vector: list[float]) -> bytes:
    """Convert list of floats to raw bytes sqlite-vec expects."""
    return struct.pack(f"{len(vector)}f", *vector)


def blob_to_vector(blob: bytes) -> list[float]:
    """Convert raw bytes back to list of floats."""
    n = len(blob) // 4   # 4 bytes per float32
    return list(struct.unpack(f"{n}f", blob))


def setup_vec_table():
    conn = get_conn()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS book_embeddings (
            accession_num TEXT PRIMARY KEY,
            embedding      BLOB NOT NULL
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS vec_books
        USING vec0(
            accession_num TEXT PRIMARY KEY,
            embedding     float[768]
        );
    """)
    conn.commit()
    conn.close()
    print("[db] Vector tables ready.")


def upsert_embedding(accession_num: str, vector: list[float], conn=None):
    blob = vector_to_blob(vector)

    should_close = False
    if conn is None:
        conn = get_conn()
        should_close = True

    # 1. Update standard table (REPLACE works fine here)
    conn.execute("REPLACE INTO book_embeddings (accession_num, embedding) VALUES (?, ?)", (accession_num, blob))

    # 2. Update virtual table (vec0)
    try:
        conn.execute("DELETE FROM vec_books WHERE accession_num = ?", (accession_num,))
        conn.execute("INSERT INTO vec_books (accession_num, embedding) VALUES (?, ?)", (accession_num, blob))
    except sqlite3.Error:
        try:
            conn.execute("INSERT INTO vec_books (accession_num, embedding) VALUES (?, ?)", (accession_num, blob))
        except sqlite3.Error:
            pass

    if should_close:
        conn.commit()
        conn.close()

def map_library_name(library: str) -> str:
    """Map friendly UI library names to database llib_no."""
    if library.lower() == "central":
        return "1"
    elif library.lower() in ["mba", "kbs"]:
        return "2"
    return library

def search_books(query_vector: list[float], library: str = "all", top_k: int = 5):
    blob = vector_to_blob(query_vector)
    conn = get_conn()

    lib_filter = map_library_name(library)

    if library == "all":
        rows = conn.execute("""
            SELECT
                b.acc_no, b.title, b.author, 
                b.llib_no AS Library,
                b.location  AS shelf,
                b.availability_status AS status,
                b.edition, b.pub_no AS publisher,
                b.pub_year AS year,
                b.price, b.isbn,
                b.dept_no AS dept,
                b.subject,
                b.search_blob AS description,
                v.distance
            FROM vec_books v
            JOIN unique_books b ON b.acc_no = v.accession_num
            WHERE v.embedding MATCH ?
              AND k = ?
            ORDER BY v.distance
        """, (blob, top_k)).fetchall()
    else:
        rows = conn.execute("""
            SELECT
                b.acc_no, b.title, b.author, 
                b.llib_no AS Library,
                b.location  AS shelf,
                b.availability_status AS status,
                b.edition, b.pub_no AS publisher,
                b.pub_year AS year,
                b.price, b.isbn,
                b.dept_no AS dept,
                b.subject,
                b.search_blob AS description,
                v.distance
            FROM vec_books v
            JOIN unique_books b ON b.acc_no = v.accession_num
            WHERE v.embedding MATCH ?
              AND k = ?
              AND CAST(b.llib_no AS TEXT) = ?
            ORDER BY v.distance
        """, (blob, top_k, lib_filter)).fetchall()

    conn.close()

    results = []
    for r in rows:
        similarity = round(1 - (float(r["distance"]) / 2.0), 4)
        available  = "available" in (r["status"] or "").lower()
        results.append({
            "accession_num": str(r["acc_no"]),
            "title":         r["title"]     or "Unknown",
            "author":        r["author"]    or "Unknown",
            "library":       "Central Library" if str(r["Library"]) == "1" else "MBA Library",
            "shelf":         r["shelf"]     or "Ask librarian",
            "status":        r["status"]    or "",
            "edition":       r["edition"]   or "",
            "publisher":     str(r["publisher"] or ""),
            "year":          str(r["year"]      or ""),
            "price":         str(r["price"]     or ""),
            "isbn":          r["isbn"]      or "",
            "dept":          str(r["dept"]      or ""),
            "subject":       r["subject"]   or "",
            "description":   r["description"] or "",
            "available":     available,
            "similarity":    similarity,
        })
    return results

def list_library_books(library: str, query: str = None, limit: int = 1000):
    conn = get_conn()
    lib_filter = map_library_name(library)

    sql = """
        SELECT 
            acc_no, title, author, 
            llib_no AS Library,
            location AS shelf,
            availability_status AS status,
            edition, pub_no AS publisher, 
            pub_year AS year,
            price, isbn,
            dept_no AS dept, subject,
            search_blob AS description
        FROM unique_books
        WHERE 1=1
    """
    params = []
    
    if library != "all":
        sql += " AND CAST(llib_no AS TEXT) = ?"
        params.append(lib_filter)

    if query and query.strip():
        keywords = query.strip().split()
        for i, word in enumerate(keywords):
            pattern = f"%{word}%"
            sql += " AND (title LIKE ? OR author LIKE ? OR subject LIKE ? OR search_blob LIKE ?)"
            params.extend([pattern, pattern, pattern, pattern])

    sql += " ORDER BY title ASC LIMIT ?"
    params.append(limit)

    rows = conn.execute(sql, params).fetchall()
    conn.close()

    return [{
        "accession_num": str(r["acc_no"]),
        "title":         r["title"]     or "Unknown",
        "author":        r["author"]    or "Unknown",
        "library":       "Central Library" if str(r["Library"]) == "1" else "MBA Library",
        "shelf":         r["shelf"]     or "Ask librarian",
        "status":        r["status"]    or "",
        "edition":       r["edition"]   or "",
        "publisher":     str(r["publisher"] or ""),
        "year":          str(r["year"]      or ""),
        "price":         str(r["price"]     or ""),
        "isbn":          r["isbn"]      or "",
        "dept":          str(r["dept"]      or ""),
        "subject":       r["subject"]   or "",
        "description":   r["description"] or "",
        "available":     "available" in (r["status"] or "").lower(),
        "similarity":    1.0,
    } for r in rows]

def list_competitive_books(query: str = None, limit: int = 1000):
    conn = get_conn()
    
    exam_terms = [
        "GATE", "APTITUDE", "COMPETITIVE", "EXAM", "ENTRANCE", "TANCET",
        "PUZZLE", "UPSC", "CIVIL SERVICE", "CAT", "IELTS", "VERBAL",
        "SOLVED PAPER", "PRACTICE SET", "ARITHMETIC", "REASONING",
        "QUANTITATIVE", "MATHEMATICS", "SSC", "BANKING", "RRB", "PLACEMENT",
        "TESTS", "MOCK", "STUDY MATERIAL", "GMAT", "GRE", "NDA", "CDS"
    ]
    
    term_clauses = []
    for _ in exam_terms:
        term_clauses.append("(title LIKE ? OR subject LIKE ? OR search_blob LIKE ?)")
    
    base_sql = f"""
        SELECT 
            acc_no, title, author, 
            llib_no AS Library,
            location AS shelf,
            availability_status AS status,
            edition, pub_no AS publisher, 
            pub_year AS year,
            price, isbn,
            dept_no AS dept, subject,
            search_blob AS description
        FROM unique_books
        WHERE ({' OR '.join(term_clauses)})
    """
    
    params = []
    for t in exam_terms:
        pattern = f"%{t}%"
        params.extend([pattern, pattern, pattern])
        
    if query and query.strip():
        keywords = query.strip().split()
        for i, word in enumerate(keywords):
            pattern = f"%{word}%"
            base_sql += " AND (title LIKE ? OR author LIKE ? OR subject LIKE ? OR search_blob LIKE ?)"
            params.extend([pattern, pattern, pattern, pattern])
        
    base_sql += " ORDER BY title ASC LIMIT ?"
    params.append(limit)
    
    rows = conn.execute(base_sql, params).fetchall()
    conn.close()
    
    return [{
        "accession_num": str(r["acc_no"]),
        "title":         r["title"]     or "Unknown",
        "author":        r["author"]    or "Unknown",
        "library":       "Central Library" if str(r["Library"]) == "1" else "MBA Library",
        "shelf":         r["shelf"]     or "Ask librarian",
        "status":        r["status"]    or "",
        "edition":       r["edition"]   or "",
        "publisher":     str(r["publisher"] or ""),
        "year":          str(r["year"]      or ""),
        "price":         str(r["price"]     or ""),
        "isbn":          r["isbn"]      or "",
        "dept":          str(r["dept"]      or ""),
        "subject":       r["subject"]   or "",
        "description":   r["description"] or "",
        "available":     "available" in (r["status"] or "").lower(),
        "similarity":    1.0,
    } for r in rows]

def advanced_search(acc_no=None, title=None, author=None, isbn=None, limit=100):
    conn = get_conn()
    
    sql = """
        SELECT 
            acc_no, title, author, 
            llib_no AS Library,
            location AS shelf,
            availability_status AS status,
            edition, pub_no AS publisher, 
            pub_year AS year,
            price, isbn,
            dept_no AS dept, subject,
            search_blob AS description
        FROM unique_books
        WHERE 1=1
    """
    params = []
    
    if acc_no is not None and str(acc_no).strip():
        sql += " AND CAST(acc_no AS TEXT) LIKE ?"
        params.append(f"%{acc_no}%")
    if title is not None and title.strip():
        sql += " AND title LIKE ?"
        params.append(f"%{title}%")
    if author is not None and author.strip():
        sql += " AND author LIKE ?"
        params.append(f"%{author}%")
    if isbn is not None and isbn.strip():
        sql += " AND isbn LIKE ?"
        params.append(f"%{isbn}%")
        
    sql += " LIMIT ?"
    params.append(limit)
    
    rows = conn.execute(sql, params).fetchall()
    conn.close()
    
    return [{
        "accession_num": str(r["acc_no"]),
        "title":         r["title"]     or "Unknown",
        "author":        r["author"]    or "Unknown",
        "library":       "Central Library" if str(r["Library"]) == "1" else "MBA Library",
        "shelf":         r["shelf"]     or "Ask librarian",
        "status":        r["status"]    or "",
        "edition":       r["edition"]   or "",
        "publisher":     str(r["publisher"] or ""),
        "year":          str(r["year"]      or ""),
        "price":         str(r["price"]     or ""),
        "isbn":          r["isbn"]      or "",
        "dept":          str(r["dept"]      or ""),
        "subject":       r["subject"]   or "",
        "description":   r["description"] or "",
        "available":     "available" in (r["status"] or "").lower(),
        "similarity":    1.0,
    } for r in rows]
