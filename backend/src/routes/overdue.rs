use axum::{
    Json,
    http::StatusCode,
    response::IntoResponse,
};
use serde::Serialize;
use rusqlite::Connection;
use chrono::Local;

#[derive(Serialize)]
pub struct OverdueBook {
    pub acc_no: i64,
    pub id_no: String,
    pub title: String,
    pub author: String,
    pub due_date: String,
    pub days_overdue: i64,
}

pub async fn get_overdue_books() -> impl IntoResponse {
    let db_all_path = std::env::var("DATABASE_ALL_PATH")
        .unwrap_or_else(|_| "/app/ilibrary-database-all.db".to_string());
    let db_combined_path = std::env::var("DATABASE_COMBINED_PATH")
        .unwrap_or_else(|_| "/app/combined-library.db".to_string());

    let conn = match Connection::open(db_all_path) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open database-all: {}", e)).into_response(),
    };

    // Attach combined-library database
    if let Err(e) = conn.execute(&format!("ATTACH DATABASE '{}' AS combined", db_combined_path), []) {
        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to attach combined-library: {}", e)).into_response();
    }

    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    
    let mut stmt = match conn.prepare("
        SELECT 
            bc.acc_no, 
            bc.id_no, 
            bc.due_date,
            b.title,
            b.author
        FROM book_circle bc
        JOIN book b ON bc.acc_no = b.acc_no
        LEFT JOIN personal p ON LOWER(bc.id_no) = LOWER(p.id_no)
        WHERE bc.due_date < ?
          AND NOT (
            p.cat_no IN (2, 4, 5) AND 
            (p.id_no LIKE '2K%' OR p.id_no LIKE '2k%') AND
            (
              (p.cat_no = 2 AND (2000 + CAST(SUBSTR(p.id_no, 3, 2) AS INTEGER)) < 2023) OR
              (p.cat_no IN (4, 5) AND (2000 + CAST(SUBSTR(p.id_no, 3, 2) AS INTEGER)) < 2025)
            )
          )
        ORDER BY bc.due_date ASC
    ") {
        Ok(s) => s,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to prepare statement: {}", e)).into_response(),
    };

    let overdue_iter = match stmt.query_map([&now], |row| {
        let due_date_str: String = row.get(2)?;
        // Simple days overdue calculation
        let days_overdue = 0; // Placeholder for now

        Ok(OverdueBook {
            acc_no: row.get(0)?,
            id_no: row.get(1)?,
            due_date: due_date_str,
            title: row.get(3)?,
            author: row.get(4)?,
            days_overdue,
        })
    }) {
        Ok(iter) => iter,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query overdue books: {}", e)).into_response(),
    };

    let mut overdue_books = Vec::new();
    for book in overdue_iter {
        if let Ok(b) = book {
            overdue_books.push(b);
        }
    }

    (StatusCode::OK, Json(overdue_books)).into_response()
}
