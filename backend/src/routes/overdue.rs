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
    let db_all_path = "/app/ilibrary-database-all.db";
    let db_combined_path = "/app/combined-library.db";

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
            cb.title,
            cb.author
        FROM book_circle bc
        JOIN combined.combined_book cb ON bc.acc_no = cb.acc_no
        WHERE bc.due_date < ?
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
