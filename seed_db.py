import sqlite3
import os

# Path to the database - using the same as sidecar/db.py
DB_PATH = os.getenv("DB_PATH", "/app/library_database.db")


def seed_database():
    print(f"[seed] Seeding database at {DB_PATH}...")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 1. Create table if not exists
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS unique_books (
            acc_no TEXT PRIMARY KEY,
            title TEXT,
            author TEXT,
            llib_no TEXT,
            location TEXT,
            availability_status TEXT,
            edition TEXT,
            pub_no TEXT,
            pub_year TEXT,
            price TEXT,
            isbn TEXT,
            dept_no TEXT,
            subject TEXT,
            search_blob TEXT
        );
    """)

    # 2. Mock Data
    books = [
        (
            "1001",
            "Introduction to Quantum Mechanics",
            "David Griffiths",
            "1",
            "Shelf A1",
            "available",
            "2nd Ed",
            "Pearson",
            "2018",
            "50.00",
            "9780131518843",
            "Physics",
            "Quantum Physics",
            "A comprehensive guide to quantum mechanics basics",
        ),
        (
            "1002",
            "Clean Code",
            "Robert C. Martin",
            "2",
            "Shelf B2",
            "available",
            "1st Ed",
            "Prentice Hall",
            "2008",
            "40.00",
            "9780132350884",
            "CS",
            "Software Engineering",
            "Best practices for writing clean and maintainable code",
        ),
        (
            "1003",
            "The Art of Computer Programming",
            "Donald Knuth",
            "1",
            "Shelf C3",
            "borrowed",
            "3rd Ed",
            "Addison-Wesley",
            "1997",
            "120.00",
            "9780201896831",
            "CS",
            "Algorithms",
            "The definitive guide to algorithms and data structures",
        ),
        (
            "1004",
            "A Brief History of Time",
            "Stephen Hawking",
            "1",
            "Shelf A2",
            "available",
            "1st Ed",
            "Bantam",
            "1988",
            "20.00",
            "9780553380163",
            "Physics",
            "Cosmology",
            "Exploration of the origin and evolution of the universe",
        ),
        (
            "1005",
            "Principles of Economics",
            "N. Gregory Mankiw",
            "2",
            "Shelf D1",
            "available",
            "9th Ed",
            "Cengage",
            "2020",
            "80.00",
            "9780393653437",
            "Economics",
            "Microeconomics",
            "Foundational principles of economic theory and practice",
        ),
    ]

    cursor.executemany(
        """
        INSERT OR REPLACE INTO unique_books 
        (acc_no, title, author, llib_no, location, availability_status, edition, pub_no, pub_year, price, isbn, dept_no, subject, search_blob) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
        books,
    )

    conn.commit()
    conn.close()
    print(f"[seed] Successfully seeded {len(books)} mock books.")


if __name__ == "__main__":
    seed_database()
