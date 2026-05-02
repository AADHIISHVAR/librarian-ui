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
    # We explicitly DELETE then INSERT because 'REPLACE' can be buggy on virtual tables
    try:
        conn.execute("DELETE FROM vec_books WHERE accession_num = ?", (accession_num,))
        conn.execute("INSERT INTO vec_books (accession_num, embedding) VALUES (?, ?)", (accession_num, blob))
    except sqlite3.Error as e:
        # If DELETE fails for some reason, try a direct INSERT
        try:
            conn.execute("INSERT INTO vec_books (accession_num, embedding) VALUES (?, ?)", (accession_num, blob))
        except sqlite3.Error:
            # If both fail, the row likely already exists and won't budge
            # We skip this one book to keep the process running
            pass

    if should_close:
        conn.commit()
        conn.close()

def map_library_name(library: str) -> str:
    """Map friendly UI library names to database Location_Library names."""
    if library.lower() == "central":
        return "GENERAL LIBRARY"
    elif library.lower() in ["mba", "kbs"]:
        return "MBA LIBRARY"
    return library

def search_books(query_vector: list[float], library: str = "all", top_k: int = 5):
    blob = vector_to_blob(query_vector)
    conn = get_conn()

    lib_filter = map_library_name(library)

    if library == "all":
        rows = conn.execute("""
            SELECT
                b.Accession_Num, b.Title, b.Author, 
                b.Location_Library AS Library,
                b.Location___Availability  AS shelf,
                b.Circulation_Status       AS status,
                b.Edition, b.Publisher,
                b.Year_of_Publishing       AS year,
                b.Price                    AS price,
                b.ISBN                     AS isbn,
                b.Department               AS dept,
                b.Subject                  AS subject,
                b.Description              AS description,
                v.distance
            FROM vec_books v
            JOIN Books b ON b.Accession_Num = v.accession_num
            WHERE v.embedding MATCH ?
              AND k = ?
            ORDER BY v.distance
        """, (blob, top_k)).fetchall()
    else:
        rows = conn.execute("""
            SELECT
                b.Accession_Num, b.Title, b.Author, 
                b.Location_Library AS Library,
                b.Location___Availability  AS shelf,
                b.Circulation_Status       AS status,
                b.Edition, b.Publisher,
                b.Year_of_Publishing       AS year,
                b.Price                    AS price,
                b.ISBN                     AS isbn,
                b.Department               AS dept,
                b.Subject                  AS subject,
                b.Description              AS description,
                v.distance
            FROM vec_books v
            JOIN Books b ON b.Accession_Num = v.accession_num
            WHERE v.embedding MATCH ?
              AND k = ?
              AND b.Location_Library = ?
            ORDER BY v.distance
        """, (blob, top_k, lib_filter)).fetchall()

    conn.close()

    results = []
    for r in rows:
        similarity = round(1 - (float(r["distance"]) / 2.0), 4)
        available  = "available" in (r["status"] or "").lower()
        results.append({
            "accession_num": r["Accession_Num"],
            "title":         r["Title"]     or "Unknown",
            "author":        r["Author"]    or "Unknown",
            "library":       r["Library"]   or "Unknown",
            "shelf":         r["shelf"]     or "Ask librarian",
            "status":        r["status"]    or "",
            "edition":       r["Edition"]   or "",
            "publisher":     r["Publisher"] or "",
            "year":          r["year"]      or "",
            "price":         r["price"]     or "",
            "isbn":          r["isbn"]      or "",
            "dept":          r["dept"]      or "",
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
            Accession_Num, Title, Author, 
            Location_Library AS Library,
            Location___Availability AS shelf,
            Circulation_Status AS status,
            Edition, Publisher, 
            Year_of_Publishing AS year,
            Price AS price, ISBN AS isbn,
            Department AS dept, Subject AS subject,
            Description AS description
        FROM Books
        WHERE Location_Library = ?
    """
    params = [lib_filter]

    if query and query.strip():
        # Better keyword-based search for catalogs: match ALL keywords
        keywords = query.strip().split()
        for i, word in enumerate(keywords):
            pattern = f"%{word}%"
            sql += " AND (Title LIKE ? OR Author LIKE ? OR Subject LIKE ? OR Keywords LIKE ?)"
            params.extend([pattern, pattern, pattern, pattern])

    sql += " ORDER BY Title ASC LIMIT ?"
    params.append(limit)

    rows = conn.execute(sql, params).fetchall()
    conn.close()

    return [{
        "accession_num": r["Accession_Num"],
        "title":         r["Title"]     or "Unknown",
        "author":        r["Author"]    or "Unknown",
        "library":       r["Library"]   or "Unknown",
        "shelf":         r["shelf"]     or "Ask librarian",
        "status":        r["status"]    or "",
        "edition":       r["Edition"]   or "",
        "publisher":     r["Publisher"] or "",
        "year":          r["year"]      or "",
        "price":         r["price"]     or "",
        "isbn":          r["isbn"]      or "",
        "dept":          r["dept"]      or "",
        "subject":       r["subject"]   or "",
        "description":   r["description"] or "",
        "available":     "available" in (r["status"] or "").lower(),
        "similarity":    1.0,
    } for r in rows]

def list_competitive_books(query: str = None, limit: int = 1000):
    conn = get_conn()
    
    # Define keywords for competitive exams
    exam_terms = [
        "GATE", "APTITUDE", "COMPETITIVE", "EXAM", "ENTRANCE", "TANCET",
        "PUZZLE", "UPSC", "CIVIL SERVICE", "CAT", "IELTS", "VERBAL",
        "SOLVED PAPER", "PRACTICE SET", "ARITHMETIC", "REASONING",
        "QUANTITATIVE", "MATHEMATICS", "SSC", "BANKING", "RRB", "PLACEMENT",
        "TESTS", "MOCK", "STUDY MATERIAL", "GMAT", "GRE", "NDA", "CDS"
    ]
    
    term_clauses = []
    for _ in exam_terms:
        term_clauses.append("(Title LIKE ? OR Subject LIKE ? OR Keywords LIKE ?)")
    
    base_sql = f"""
        SELECT 
            Accession_Num, Title, Author, 
            Location_Library AS Library,
            Location___Availability AS shelf,
            Circulation_Status AS status,
            Edition, Publisher, 
            Year_of_Publishing AS year,
            Price AS price, ISBN AS isbn,
            Department AS dept, Subject AS subject,
            Description AS description
        FROM Books
        WHERE ({' OR '.join(term_clauses)})
    """
    
    params = []
    for t in exam_terms:
        pattern = f"%{t}%"
        params.extend([pattern, pattern, pattern])
        
    if query and query.strip():
        # Better keyword-based search for catalogs: match ALL keywords
        keywords = query.strip().split()
        for i, word in enumerate(keywords):
            pattern = f"%{word}%"
            base_sql += " AND (Title LIKE ? OR Author LIKE ? OR Subject LIKE ? OR Keywords LIKE ?)"
            params.extend([pattern, pattern, pattern, pattern])
        
    base_sql += " ORDER BY Title ASC LIMIT ?"
    params.append(limit)
    
    rows = conn.execute(base_sql, params).fetchall()
    conn.close()
    
    return [{
        "accession_num": r["Accession_Num"],
        "title":         r["Title"]     or "Unknown",
        "author":        r["Author"]    or "Unknown",
        "library":       r["Library"]   or "Unknown",
        "shelf":         r["shelf"]     or "Ask librarian",
        "status":        r["status"]    or "",
        "edition":       r["Edition"]   or "",
        "publisher":     r["Publisher"] or "",
        "year":          r["year"]      or "",
        "price":         r["price"]     or "",
        "isbn":          r["isbn"]      or "",
        "dept":          r["dept"]      or "",
        "subject":       r["subject"]   or "",
        "description":   r["description"] or "",
        "available":     "available" in (r["status"] or "").lower(),
        "similarity":    1.0,
    } for r in rows]

def title_search_fallback(query: str, library: str = "all", top_k: int = 5):
    """Plain SQL LIKE search — used when vector scores are weak."""
    conn = get_conn()
    lib_filter = map_library_name(library)
    
    stop_words = {"a", "an", "the", "and", "or", "of", "for", "to", "in", "on", "with"}
    words = [w.lower() for w in query.strip().split() if w.lower() not in stop_words]
    
    if not words:
        words = query.strip().split()
    
    clauses = []
    params = []
    for w in words[:2]:
        clauses.append("Title LIKE ?")
        params.append(f"%{w}%")
    
    where_sql = " OR ".join(clauses) if clauses else "1=1"
    
    if library != "all":
        where_sql = f"({where_sql}) AND Location_Library = ?"
        params.append(lib_filter)
        
    params.append(top_k)

    rows = conn.execute(f"""
        SELECT 
            Accession_Num, Title, Author, 
            Location_Library AS Library,
            Location___Availability AS shelf,
            Circulation_Status      AS status,
            Edition, Publisher,
            Year_of_Publishing       AS year,
            Price                    AS price,
            ISBN                     AS isbn,
            Department               AS dept,
            Subject                  AS subject,
            Description              AS description
        FROM Books
        WHERE {where_sql}
        LIMIT ?
    """, params).fetchall()

    conn.close()
    return [{
        "accession_num": r["Accession_Num"],
        "title":         r["Title"]     or "Unknown",
        "author":        r["Author"]    or "Unknown",
        "library":       r["Library"]   or "Unknown",
        "shelf":         r["shelf"]     or "Ask librarian",
        "status":        r["status"]    or "",
        "edition":       r["Edition"]   or "",
        "publisher":     r["Publisher"] or "",
        "year":          r["year"]      or "",
        "price":         r["price"]     or "",
        "isbn":          r["isbn"]      or "",
        "dept":          r["dept"]      or "",
        "subject":       r["subject"]   or "",
        "description":   r["description"] or "",
        "available":     "available" in (r["status"] or "").lower(),
        "similarity":    1.0,
    } for r in rows]

def advanced_search(acc_no=None, title=None, author=None, isbn=None, limit=100):
    conn = get_conn()
    
    sql = """
        SELECT 
            Accession_Num, Title, Author, 
            Location_Library AS Library,
            Location___Availability AS shelf,
            Circulation_Status AS status,
            Edition, Publisher, 
            Year_of_Publishing AS year,
            Price AS price, ISBN AS isbn,
            Department AS dept, Subject AS subject,
            Description AS description
        FROM Books
        WHERE 1=1
    """
    params = []
    
    if acc_no:
        sql += " AND Accession_Num LIKE ?"
        params.append(f"%{acc_no}%")
    if title:
        sql += " AND Title LIKE ?"
        params.append(f"%{title}%")
    if author:
        sql += " AND Author LIKE ?"
        params.append(f"%{author}%")
    if isbn:
        sql += " AND ISBN LIKE ?"
        params.append(f"%{isbn}%")
        
    sql += " LIMIT ?"
    params.append(limit)
    
    rows = conn.execute(sql, params).fetchall()
    conn.close()
    
    return [{
        "accession_num": r["Accession_Num"],
        "title":         r["Title"]     or "Unknown",
        "author":        r["Author"]    or "Unknown",
        "library":       r["Library"]   or "Unknown",
        "shelf":         r["shelf"]     or "Ask librarian",
        "status":        r["status"]    or "",
        "edition":       r["Edition"]   or "",
        "publisher":     r["Publisher"] or "",
        "year":          r["year"]      or "",
        "price":         r["price"]     or "",
        "isbn":          r["isbn"]      or "",
        "dept":          r["dept"]      or "",
        "subject":       r["subject"]   or "",
        "description":   r["description"] or "",
        "available":     "available" in (r["status"] or "").lower(),
        "similarity":    1.0,
    } for r in rows]
