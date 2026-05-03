import sqlite3
import os
import re

def normalize(text):
    if not text: return ""
    s = str(text).strip().upper()
    if s in ("NONE", "-", "0", ""): return ""
    # Remove special characters and extra spaces for a "fuzzy" grouping key
    return re.sub(r"[^A-Z0-9]", "", s)

def get_completeness_score(row):
    score = 0
    for val in row:
        if val is not None and str(val).strip() not in ('', '-', '0', 'None'):
            score += 1
    return score

def create_optimized_unique_db():
    in_db_path = 'combined-library.db'
    out_db_path = 'uniqueBooks.db'
    
    if os.path.exists(out_db_path):
        os.remove(out_db_path)
    
    conn = sqlite3.connect(in_db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute("PRAGMA table_info(combined_book)")
    col_info = cursor.fetchall()
    columns = [info["name"] for info in col_info]
    col_types = {info["name"]: info["type"] for info in col_info}
    
    out_conn = sqlite3.connect(out_db_path)
    out_cursor = out_conn.cursor()
    
    # Define columns with the original types + aggregation fields
    cols_sql = [f"\"{col}\" {col_types[col]}" for col in columns]
    create_table_sql = f"""
    CREATE TABLE unique_books (
        {", ".join(cols_sql)},
        all_acc_nos TEXT,
        all_locations TEXT,
        total_copies INTEGER,
        available_copies INTEGER,
        availability_status TEXT,
        search_blob TEXT
    )"""
    out_cursor.execute(create_table_sql)
    
    print("Fetching data and optimizing records...")
    cursor.execute("SELECT * FROM combined_book")
    rows = cursor.fetchall()
    
    groups = {}
    
    for row in rows:
        # Smart Grouping Key: Prefer ISBN, fall back to Normalized Title + Author
        isbn = normalize(row['isbn'])
        title_norm = normalize(row['title'])
        author_norm = normalize(row['author'])
        
        if isbn and len(isbn) >= 8:
            key = f"ISBN_{isbn}"
        else:
            key = f"T_{title_norm}_A_{author_norm}"
        
        acc_no = str(row['acc_no']).strip()
        location = str(row['location']).strip() if row['location'] else ""
        is_avail = 1 if row['avail'] and int(row['avail']) > 0 else 0
        score = get_completeness_score(row)
        
        if key not in groups:
            groups[key] = {
                'best_row': dict(row),
                'score': score,
                'acc_nos': {acc_no},
                'locs': {location} if location and location != '-' else set(),
                'total': 1,
                'avail': is_avail
            }
        else:
            g = groups[key]
            g['total'] += 1
            g['avail'] += is_avail
            g['acc_nos'].add(acc_no)
            if location and location != '-':
                g['locs'].add(location)
            if score > g['score']:
                g['score'] = score
                g['best_row'] = dict(row)

    print(f"Building Search Blobs and inserting {len(groups)} unique records...")
    
    insert_cols = columns + ['all_acc_nos', 'all_locations', 'total_copies', 'available_copies', 'availability_status', 'search_blob']
    placeholders = ', '.join(['?' for _ in insert_cols])
    insert_sql = f"INSERT INTO unique_books ({', '.join([f'\"{c}\"' for c in insert_cols])}) VALUES ({placeholders})"
    
    rows_to_insert = []
    for key, data in groups.items():
        row_dict = data['best_row']
        
        # Format Accession numbers for unambiguous searching: |1|22|333|
        sorted_accs = sorted(list(data['acc_nos']), key=lambda x: int(x) if x.isdigit() else 999999)
        acc_string = "|" + "|".join(sorted_accs) + "|"
        
        row_dict['all_acc_nos'] = ", ".join(sorted_accs)
        row_dict['all_locations'] = ", ".join(sorted(list(data['locs'])))
        row_dict['total_copies'] = data['total']
        row_dict['available_copies'] = data['avail']
        row_dict['availability_status'] = "Available" if data['avail'] > 0 else "Out of Stock"
        
        # PEAK OPTIMIZATION: Create the unified search blob
        # Combine everything into one string for a single-column scan
        blob = " ".join([
            str(row_dict.get('title', '')),
            str(row_dict.get('author', '')),
            str(row_dict.get('subject', '')),
            str(row_dict.get('keywords', '')),
            str(row_dict.get('isbn', '')),
            acc_string
        ]).lower()
        row_dict['search_blob'] = blob
        
        vals = [row_dict.get(c) for c in insert_cols]
        rows_to_insert.append(vals)
        
        if len(rows_to_insert) >= 1000:
            out_cursor.executemany(insert_sql, rows_to_insert)
            rows_to_insert = []
            
    if rows_to_insert:
        out_cursor.executemany(insert_sql, rows_to_insert)
        
    out_conn.commit()
    conn.close()
    out_conn.close()
    print("Done! Peak Optimized Unique Database created.")

if __name__ == "__main__":
    create_optimized_unique_db()
