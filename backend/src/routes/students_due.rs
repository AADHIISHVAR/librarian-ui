use axum::{
    Json,
    extract::{Query, Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use chrono::{Local, NaiveDateTime};

#[derive(Serialize)]
pub struct StudentDueBook {
    pub id_no: String,
    pub student_name: String,
    pub student_class: String,
    pub department: String,
    pub category: String,
    pub acc_no: i64,
    pub title: String,
    pub author: String,
    pub due_date: String,
    pub days_overdue: i64,
    pub phone: Option<String>,
    pub email: Option<String>,
}

#[derive(Deserialize)]
pub struct StudentsDueQuery {
    pub department: Option<String>,
    pub category: Option<String>,
    pub overdue_only: Option<bool>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    pub class_name: Option<String>,
    pub search_query: Option<String>,
    pub study_year: Option<String>,
    pub gender: Option<String>,
}

#[derive(Serialize)]
pub struct StudentsDueResponse {
    pub students: Vec<StudentDueBook>,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
}

pub async fn get_students_due_overview(
    Query(params): Query<StudentsDueQuery>,
) -> impl IntoResponse {
    let db_all_path = std::env::var("DATABASE_ALL_PATH")
        .unwrap_or_else(|_| "/app/library-database-allData.db".to_string());

    let conn = match Connection::open(&db_all_path) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open database: {}", e)).into_response(),
    };

    let db_combined_path = std::env::var("DATABASE_COMBINED_PATH")
        .unwrap_or_else(|_| "/app/combined-library.db".to_string());
    let _ = conn.execute(&format!("ATTACH DATABASE '{}' AS combined", db_combined_path), []);

    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let limit = params.limit.unwrap_or(50).min(200);
    let offset = params.offset.unwrap_or(0);
    let overdue_only = params.overdue_only.unwrap_or(false);

    let mut where_clauses = Vec::new();
    let mut query_params: Vec<String> = Vec::new();

    if overdue_only {
        where_clauses.push("bc.due_date < ?".to_string());
        query_params.push(now.clone());
    }

    if let Some(dept) = &params.department {
        if !dept.trim().is_empty() && dept != "All Departments" {
            where_clauses.push("p.dept_no = (SELECT dept_no FROM department WHERE dept_name = ?)".to_string());
            query_params.push(dept.trim().to_string());
        }
    }

    if let Some(cat) = &params.category {
        if !cat.trim().is_empty() && cat != "All Categories" {
            where_clauses.push("p.cat_no = (SELECT cat_no FROM catagory WHERE cat_name = ?)".to_string());
            query_params.push(cat.trim().to_string());
        }
    }

    if let Some(class_val) = &params.class_name {
        if !class_val.trim().is_empty() && class_val != "All Classes" {
            let classes: Vec<String> = class_val
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
            if !classes.is_empty() {
                let placeholders = vec!["?"; classes.len()].join(", ");
                where_clauses.push(format!("p.class IN ({})", placeholders));
                for c in classes {
                    query_params.push(c);
                }
            }
        }
    }

    if let Some(search) = &params.search_query {
        let trimmed = search.trim();
        if !trimmed.is_empty() {
            where_clauses.push("(LOWER(p.id_no) LIKE ? OR LOWER(p.name) LIKE ?)".to_string());
            query_params.push(format!("%{}%", trimmed.to_lowercase()));
            query_params.push(format!("%{}%", trimmed.to_lowercase()));
        }
    }

    if let Some(year) = &params.study_year {
        if !year.trim().is_empty() && year != "All Years" {
            where_clauses.push("p.study_year = ?".to_string());
            query_params.push(year.trim().to_string());
        }
    }

    if let Some(gen) = &params.gender {
        if !gen.trim().is_empty() && gen != "All" {
            where_clauses.push("p.gender = ?".to_string());
            query_params.push(gen.trim().to_string());
        }
    }

    where_clauses.push("NOT (
        p.cat_no IN (2, 4, 5) AND 
        (p.id_no LIKE '2K%' OR p.id_no LIKE '2k%') AND
        (
          (p.cat_no = 2 AND (2000 + CAST(SUBSTR(p.id_no, 3, 2) AS INTEGER)) < 2023) OR
          (p.cat_no IN (4, 5) AND (2000 + CAST(SUBSTR(p.id_no, 3, 2) AS INTEGER)) < 2025)
        )
    )".to_string());

    let where_sql = if where_clauses.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", where_clauses.join(" AND "))
    };

    let count_sql = format!(
        "SELECT COUNT(*) FROM book_circle bc
         JOIN book b ON bc.acc_no = b.acc_no
         JOIN personal p ON LOWER(bc.id_no) = LOWER(p.id_no)
         LEFT JOIN department d ON p.dept_no = d.dept_no
         LEFT JOIN catagory c ON p.cat_no = c.cat_no
         {}",
        where_sql
    );

    let total: i64 = match conn.query_row(&count_sql, rusqlite::params_from_iter(query_params.iter()), |row| row.get(0)) {
        Ok(t) => t,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Count query failed: {}", e)).into_response(),
    };

    let data_sql = format!(
        "SELECT 
            bc.id_no,
            p.name,
            p.class,
            d.dept_name,
            c.cat_name,
            bc.acc_no,
            b.title,
            b.author,
            bc.due_date,
            p.phone,
            p.e_mail
         FROM book_circle bc
         JOIN book b ON bc.acc_no = b.acc_no
         JOIN personal p ON LOWER(bc.id_no) = LOWER(p.id_no)
         LEFT JOIN department d ON p.dept_no = d.dept_no
         LEFT JOIN catagory c ON p.cat_no = c.cat_no
         {}
         ORDER BY bc.due_date ASC
         LIMIT ? OFFSET ?",
        where_sql
    );

    let mut final_params = query_params.clone();
    final_params.push(limit.to_string());
    final_params.push(offset.to_string());

    let mut stmt = match conn.prepare(&data_sql) {
        Ok(s) => s,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Prepare failed: {}", e)).into_response(),
    };

    let rows = match stmt.query_map(rusqlite::params_from_iter(final_params.iter()), |row| {
        let due_date_str: String = row.get(8)?;
        let days_overdue = calculate_days_overdue(&due_date_str);

        Ok(StudentDueBook {
            id_no: row.get(0)?,
            student_name: row.get(1)?,
            student_class: row.get(2)?,
            department: row.get(3).unwrap_or_default(),
            category: row.get(4).unwrap_or_default(),
            acc_no: row.get(5)?,
            title: row.get(6)?,
            author: row.get(7)?,
            due_date: due_date_str,
            days_overdue,
            phone: row.get(9)?,
            email: row.get(10)?,
        })
    }) {
        Ok(r) => r,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Query failed: {}", e)).into_response(),
    };

    let mut students = Vec::new();
    for student in rows {
        if let Ok(s) = student {
            students.push(s);
        }
    }

    (StatusCode::OK, Json(StudentsDueResponse {
        students,
        total,
        limit,
        offset,
    })).into_response()
}

fn calculate_days_overdue(due_date_str: &str) -> i64 {
    if let Ok(due_dt) = NaiveDateTime::parse_from_str(due_date_str, "%Y-%m-%d %H:%M:%S") {
        let now = Local::now().naive_local();
        (now - due_dt).num_days()
    } else {
        0
    }
}

pub async fn get_filter_options() -> impl IntoResponse {
    let db_all_path = std::env::var("DATABASE_ALL_PATH")
        .unwrap_or_else(|_| "/app/library-database-allData.db".to_string());

    let conn = match Connection::open(&db_all_path) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open database: {}", e)).into_response(),
    };

    let dept_sql = "SELECT dept_name FROM department WHERE dept_name IS NOT NULL AND dept_name != '' ORDER BY dept_name";
    let dept_rows = match conn.prepare(dept_sql) {
        Ok(mut stmt) => match stmt.query_map([], |row| row.get::<_, String>(0)) {
            Ok(rows) => rows.filter_map(Result::ok).collect(),
            Err(_) => Vec::new(),
        },
        Err(_) => Vec::new(),
    };

    let cat_sql = "SELECT cat_name FROM catagory WHERE cat_name IS NOT NULL ORDER BY cat_name";
    let cat_rows = match conn.prepare(cat_sql) {
        Ok(mut stmt) => match stmt.query_map([], |row| row.get::<_, String>(0)) {
            Ok(rows) => rows.filter_map(Result::ok).collect(),
            Err(_) => Vec::new(),
        },
        Err(_) => Vec::new(),
    };

    let dept_meta_sql = "SELECT dept_no, dept_name FROM department WHERE dept_name IS NOT NULL AND dept_name != '' ORDER BY dept_name";
    let dept_meta_rows = match conn.prepare(dept_meta_sql) {
        Ok(mut stmt) => match stmt.query_map([], |row| {
            Ok(IdName {
                id: row.get(0)?,
                name: row.get(1)?,
            })
        }) {
            Ok(rows) => rows.filter_map(Result::ok).collect(),
            Err(_) => Vec::new(),
        },
        Err(_) => Vec::new(),
    };

    let cat_meta_sql = "SELECT cat_no, cat_name FROM catagory WHERE cat_name IS NOT NULL ORDER BY cat_name";
    let cat_meta_rows = match conn.prepare(cat_meta_sql) {
        Ok(mut stmt) => match stmt.query_map([], |row| {
            Ok(IdName {
                id: row.get(0)?,
                name: row.get(1)?,
            })
        }) {
            Ok(rows) => rows.filter_map(Result::ok).collect(),
            Err(_) => Vec::new(),
        },
        Err(_) => Vec::new(),
    };

    #[derive(Serialize)]
    struct IdName {
        id: i32,
        name: String,
    }

    #[derive(Serialize)]
    struct FilterOptions {
        departments: Vec<String>,
        categories: Vec<String>,
        departments_meta: Vec<IdName>,
        categories_meta: Vec<IdName>,
    }

    (StatusCode::OK, Json(FilterOptions {
        departments: dept_rows,
        categories: cat_rows,
        departments_meta: dept_meta_rows,
        categories_meta: cat_meta_rows,
    })).into_response()
}

#[derive(Serialize)]
pub struct MarkReturnedResponse {
    pub success: bool,
    pub message: String,
}

pub async fn mark_book_returned(
    Path((id_no, acc_no)): Path<(String, i64)>,
) -> impl IntoResponse {
    let db_all_path = std::env::var("DATABASE_ALL_PATH")
        .unwrap_or_else(|_| "/app/library-database-allData.db".to_string());

    let conn = match Connection::open(&db_all_path) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open database: {}", e)).into_response(),
    };

    let result = conn.execute(
        "DELETE FROM book_circle WHERE LOWER(id_no) = LOWER(?) AND acc_no = ?",
        rusqlite::params![id_no, acc_no],
    );

    match result {
        Ok(rows_affected) if rows_affected > 0 => {
            (StatusCode::OK, Json(MarkReturnedResponse {
                success: true,
                message: "Book marked as returned successfully".to_string(),
            })).into_response()
        }
        Ok(_) => {
            (StatusCode::NOT_FOUND, Json(MarkReturnedResponse {
                success: false,
                message: "Book loan record not found".to_string(),
            })).into_response()
        }
        Err(e) => {
            (StatusCode::INTERNAL_SERVER_ERROR, Json(MarkReturnedResponse {
                success: false,
                message: format!("Database error: {}", e),
            })).into_response()
        }
    }
}

#[derive(Deserialize)]
pub struct MemberSearchQuery {
    pub roll_no: Option<String>,
    pub reg_no: Option<String>,
    pub dept: Option<String>,
    pub batch: Option<String>,
    pub phone: Option<String>,
    pub name: Option<String>,
}

#[derive(Serialize)]
pub struct MemberDetail {
    pub id_no: String,
    pub reg_no: Option<String>,
    pub name: String,
    pub class: String,
    pub study_year: Option<String>,
    pub dept_name: Option<String>,
    pub cat_name: Option<String>,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub gender: Option<String>,
    pub dob: Option<String>,
    pub parent: Option<String>,
    pub admn_no: Option<String>,
    pub blood_group: Option<String>,
    pub active_member: Option<i64>,
    pub active_borrows: Vec<BorrowedBook>,
}

#[derive(Serialize)]
pub struct BorrowedBook {
    pub acc_no: i64,
    pub title: String,
    pub author: String,
    pub due_date: String,
    pub days_overdue: i64,
}

pub async fn search_member(
    Query(params): Query<MemberSearchQuery>,
) -> impl IntoResponse {
    let db_all_path = std::env::var("DATABASE_ALL_PATH")
        .unwrap_or_else(|_| "/app/library-database-allData.db".to_string());
    let db_combined_path = std::env::var("DATABASE_COMBINED_PATH")
        .unwrap_or_else(|_| "/app/combined-library.db".to_string());

    let conn = match Connection::open(&db_all_path) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open database: {}", e)).into_response(),
    };

    let _ = conn.execute(&format!("ATTACH DATABASE '{}' AS combined", db_combined_path), []);

    let mut where_clauses = Vec::new();
    let mut sql_params: Vec<String> = Vec::new();

    if let Some(roll) = &params.roll_no {
        if !roll.trim().is_empty() {
            where_clauses.push("p.id_no LIKE ?".to_string());
            sql_params.push(format!("%{}%", roll.trim()));
        }
    }

    if let Some(reg) = &params.reg_no {
        if !reg.trim().is_empty() {
            where_clauses.push("p.reg_no LIKE ?".to_string());
            sql_params.push(format!("%{}%", reg.trim()));
        }
    }

    if let Some(dept) = &params.dept {
        if !dept.trim().is_empty() {
            where_clauses.push("d.dept_name LIKE ?".to_string());
            sql_params.push(format!("%{}%", dept.trim()));
        }
    }

    if let Some(batch) = &params.batch {
        if !batch.trim().is_empty() {
            where_clauses.push("p.id_no LIKE ?".to_string());
            sql_params.push(format!("{}%", batch.trim()));
        }
    }

    if let Some(phone) = &params.phone {
        if !phone.trim().is_empty() {
            where_clauses.push("p.phone LIKE ?".to_string());
            sql_params.push(format!("%{}%", phone.trim()));
        }
    }

    if let Some(name) = &params.name {
        if !name.trim().is_empty() {
            where_clauses.push("p.name LIKE ?".to_string());
            sql_params.push(format!("%{}%", name.trim()));
        }
    }

    where_clauses.push("NOT (
        p.cat_no IN (2, 4, 5) AND 
        (p.id_no LIKE '2K%' OR p.id_no LIKE '2k%') AND
        (
          (p.cat_no = 2 AND (2000 + CAST(SUBSTR(p.id_no, 3, 2) AS INTEGER)) < 2023) OR
          (p.cat_no IN (4, 5) AND (2000 + CAST(SUBSTR(p.id_no, 3, 2) AS INTEGER)) < 2025)
        )
    )".to_string());

    let where_sql = if where_clauses.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", where_clauses.join(" AND "))
    };

    let search_sql = format!(
        "SELECT 
            p.id_no,
            p.reg_no,
            p.name,
            p.class,
            p.study_year,
            d.dept_name,
            c.cat_name,
            p.phone,
            p.e_mail,
            p.gender,
            p.dob,
            p.parent,
            p.admn_no,
            p.blood_group,
            p.active_member
         FROM personal p
         LEFT JOIN department d ON p.dept_no = d.dept_no
         LEFT JOIN catagory c ON p.cat_no = c.cat_no
         {}
         ORDER BY p.name ASC
         LIMIT 50",
        where_sql
    );

    let mut stmt = match conn.prepare(&search_sql) {
        Ok(s) => s,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to prepare search statement: {}", e)).into_response(),
    };

    let member_rows = match stmt.query_map(rusqlite::params_from_iter(sql_params.iter()), |row| {
        let id_no: String = row.get(0)?;
        let reg_no: Option<String> = row.get(1)?;
        let name: String = row.get(2)?;
        let class: String = row.get(3)?;
        let study_year: Option<String> = row.get(4)?;
        let dept_name: Option<String> = row.get(5)?;
        let cat_name: Option<String> = row.get(6)?;
        let phone: Option<String> = row.get(7)?;
        let email: Option<String> = row.get(8)?;
        let gender: Option<String> = row.get(9)?;
        let dob: Option<String> = row.get(10)?;
        let parent: Option<String> = row.get(11)?;
        let admn_no: Option<String> = row.get(12)?;
        let blood_group: Option<String> = row.get(13)?;
        let active_member: Option<i64> = row.get(14)?;

        Ok((id_no, reg_no, name, class, study_year, dept_name, cat_name, phone, email, gender, dob, parent, admn_no, blood_group, active_member))
    }) {
        Ok(iter) => iter,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query members: {}", e)).into_response(),
    };

    let mut members = Vec::new();
    for row in member_rows {
        if let Ok((id_no, reg_no, name, class, study_year, dept_name, cat_name, phone, email, gender, dob, parent, admn_no, blood_group, active_member)) = row {
            let mut borrows = Vec::new();
            if let Ok(mut borrow_stmt) = conn.prepare("
                SELECT 
                    bc.acc_no,
                    b.title,
                    b.author,
                    bc.due_date
                FROM book_circle bc
                JOIN book b ON bc.acc_no = b.acc_no
                WHERE LOWER(bc.id_no) = LOWER(?)
                ORDER BY bc.due_date ASC
            ") {
                if let Ok(borrow_rows) = borrow_stmt.query_map([&id_no], |b_row| {
                    let due_date_str: String = b_row.get(3)?;
                    let days_overdue = calculate_days_overdue(&due_date_str);
                    Ok(BorrowedBook {
                        acc_no: b_row.get(0)?,
                        title: b_row.get(1)?,
                        author: b_row.get(2)?,
                        due_date: due_date_str,
                        days_overdue,
                    })
                }) {
                    for b in borrow_rows {
                        if let Ok(b_ok) = b {
                            borrows.push(b_ok);
                        }
                    }
                }
            }

            members.push(MemberDetail {
                id_no,
                reg_no,
                name,
                class,
                study_year,
                dept_name,
                cat_name,
                phone,
                email,
                gender,
                dob,
                parent,
                admn_no,
                blood_group,
                active_member,
                active_borrows: borrows,
            });
        }
    }

    (StatusCode::OK, Json(members)).into_response()
}

#[derive(Deserialize)]
pub struct ReportQuery {
    pub department: Option<String>,
    pub category: Option<String>,
    pub class_name: Option<String>,
    pub study_year: Option<String>,
    pub gender: Option<String>,
    pub id_pattern: Option<String>,
    pub match_type: Option<String>, // "exact", "like", "left", "right"
    pub active_status: Option<String>, // "active", "old", "both"
    pub fine_rate: Option<f64>,
}

#[derive(Serialize)]
pub struct ReportBook {
    pub library: String,
    pub acc_no: i64,
    pub title: String,
    pub author: String,
    pub due_date: String,
    pub overdue_days: i64,
    pub overdue_amount: f64,
}

#[derive(Serialize)]
pub struct ReportMemberGroup {
    pub id_no: String,
    pub name: String,
    pub class: String,
    pub dept_name: String,
    pub cat_name: String,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub gender: Option<String>,
    pub active_member: i64,
    pub books: Vec<ReportBook>,
    pub total_fine: f64,
}

#[derive(Serialize)]
pub struct ReportResponse {
    pub report_title: String,
    pub generated_date: String,
    pub grand_total: f64,
    pub members: Vec<ReportMemberGroup>,
}

pub async fn get_duelist_report(
    Query(params): Query<ReportQuery>,
) -> impl IntoResponse {
    let db_all_path = std::env::var("DATABASE_ALL_PATH")
        .unwrap_or_else(|_| "/app/library-database-allData.db".to_string());
    
    let conn = match Connection::open(&db_all_path) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open database: {}", e)).into_response(),
    };

    let fine_rate = params.fine_rate.unwrap_or(0.5);

    let mut where_clauses = Vec::new();
    let mut sql_params: Vec<String> = Vec::new();

    if let Some(dept) = &params.department {
        if !dept.trim().is_empty() && dept != "All Departments" {
            where_clauses.push("d.dept_name = ?".to_string());
            sql_params.push(dept.trim().to_string());
        }
    }

    if let Some(cat) = &params.category {
        if !cat.trim().is_empty() && cat != "All Categories" {
            where_clauses.push("c.cat_name = ?".to_string());
            sql_params.push(cat.trim().to_string());
        }
    }

    if let Some(class_val) = &params.class_name {
        if !class_val.trim().is_empty() && class_val != "All Classes" {
            let classes: Vec<String> = class_val
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
            if !classes.is_empty() {
                let placeholders = vec!["?"; classes.len()].join(", ");
                where_clauses.push(format!("p.class IN ({})", placeholders));
                for c in classes {
                    sql_params.push(c);
                }
            }
        }
    }

    if let Some(year) = &params.study_year {
        if !year.trim().is_empty() && year != "All Years" {
            where_clauses.push("p.study_year = ?".to_string());
            sql_params.push(year.trim().to_string());
        }
    }

    if let Some(gen) = &params.gender {
        if !gen.trim().is_empty() && gen != "All" {
            where_clauses.push("p.gender = ?".to_string());
            sql_params.push(gen.trim().to_string());
        }
    }

    if let Some(pattern) = &params.id_pattern {
        if !pattern.trim().is_empty() {
            let m_type = params.match_type.as_deref().unwrap_or("left");
            match m_type {
                "exact" => {
                    where_clauses.push("LOWER(p.id_no) = LOWER(?)".to_string());
                    sql_params.push(pattern.trim().to_string());
                }
                "like" => {
                    where_clauses.push("p.id_no LIKE ?".to_string());
                    sql_params.push(format!("%{}%", pattern.trim()));
                }
                "right" => {
                    where_clauses.push("p.id_no LIKE ?".to_string());
                    sql_params.push(format!("%{}", pattern.trim()));
                }
                _ => { // default "left"
                    where_clauses.push("p.id_no LIKE ?".to_string());
                    sql_params.push(format!("{}%", pattern.trim()));
                }
            }
        }
    }

    let active_status = params.active_status.as_deref().unwrap_or("active");
    match active_status {
        "active" => {
            where_clauses.push("p.active_member = 1".to_string());
            where_clauses.push("NOT (
                p.cat_no IN (2, 4, 5) AND 
                (p.id_no LIKE '2K%' OR p.id_no LIKE '2k%') AND
                (
                  (p.cat_no = 2 AND (2000 + CAST(SUBSTR(p.id_no, 3, 2) AS INTEGER)) < 2023) OR
                  (p.cat_no IN (4, 5) AND (2000 + CAST(SUBSTR(p.id_no, 3, 2) AS INTEGER)) < 2025)
                )
            )".to_string());
        }
        "old" => {
            where_clauses.push("p.active_member != 1".to_string());
        }
        _ => {} // "both" -> no active status filter
    }

    let where_sql = if where_clauses.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", where_clauses.join(" AND "))
    };

    let sql = format!(
        "SELECT 
            p.id_no,
            p.name,
            p.class,
            d.dept_name,
            c.cat_name,
            p.phone,
            p.e_mail,
            p.gender,
            p.active_member,
            bc.acc_no,
            b.title,
            b.author,
            bc.due_date,
            p.cat_no,
            b.llib_no
         FROM book_circle bc
         JOIN book b ON bc.acc_no = b.acc_no
         JOIN personal p ON LOWER(bc.id_no) = LOWER(p.id_no)
         LEFT JOIN department d ON p.dept_no = d.dept_no
         LEFT JOIN catagory c ON p.cat_no = c.cat_no
         {}
         ORDER BY p.name ASC, bc.due_date ASC",
        where_sql
    );

    let mut stmt = match conn.prepare(&sql) {
        Ok(s) => s,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to prepare report statement: {}", e)).into_response(),
    };

    let rows = match stmt.query_map(rusqlite::params_from_iter(sql_params.iter()), |row| {
        let id_no: String = row.get(0)?;
        let name: String = row.get(1)?;
        let class: String = row.get(2)?;
        let dept_name: Option<String> = row.get(3)?;
        let cat_name: Option<String> = row.get(4)?;
        let phone: Option<String> = row.get(5)?;
        let email: Option<String> = row.get(6)?;
        let gender: Option<String> = row.get(7)?;
        let active_member: i64 = row.get(8)?;
        let acc_no: i64 = row.get(9)?;
        let title: String = row.get(10)?;
        let author: String = row.get(11)?;
        let due_date: String = row.get(12)?;
        let cat_no: i64 = row.get(13)?;
        let llib_no: Option<i64> = row.get(14)?;

        Ok((id_no, name, class, dept_name.unwrap_or_default(), cat_name.unwrap_or_default(), phone, email, gender, active_member, acc_no, title, author, due_date, cat_no, llib_no))
    }) {
        Ok(iter) => iter,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to execute report query: {}", e)).into_response(),
    };

    use std::collections::HashMap;
    let mut groups_map: HashMap<String, ReportMemberGroup> = HashMap::new();
    let mut grand_total = 0.0;

    for r in rows {
        if let Ok((id_no, name, class, dept_name, cat_name, phone, email, gender, active_member, acc_no, title, author, due_date, cat_no, llib_no)) = r {
            let days_overdue = calculate_days_overdue(&due_date).max(0);
            
            let is_student = cat_no == 2 || cat_no == 4 || cat_no == 5;
            let overdue_amount = if is_student {
                (days_overdue as f64) * fine_rate
            } else {
                0.0
            };

            grand_total += overdue_amount;

            let library_name = match llib_no {
                Some(2) => "KBS LIBRARY".to_string(),
                _ => "KIOT Library".to_string(),
            };

            let book = ReportBook {
                library: library_name,
                acc_no,
                title,
                author,
                due_date,
                overdue_days: days_overdue,
                overdue_amount,
            };

            let entry = groups_map.entry(id_no.clone()).or_insert_with(|| ReportMemberGroup {
                id_no: id_no.clone(),
                name,
                class,
                dept_name,
                cat_name,
                phone,
                email,
                gender,
                active_member,
                books: Vec::new(),
                total_fine: 0.0,
            });

            entry.total_fine += overdue_amount;
            entry.books.push(book);
        }
    }

    let mut members: Vec<ReportMemberGroup> = groups_map.into_values().collect();
    members.sort_by(|a, b| a.name.cmp(&b.name));

    let generated_date = Local::now().format("%d/%m/%Y").to_string();

    (StatusCode::OK, Json(ReportResponse {
        report_title: "Member Duelist".to_string(),
        generated_date,
        grand_total,
        members,
    })).into_response()
}

#[derive(Deserialize)]
pub struct AddMemberPayload {
    pub id_no: String,
    pub name: String,
    pub class: String,
    pub study_year: String,
    pub dept_no: i32,
    pub cat_no: i32,
    pub phone: String,
    pub e_mail: String,
    pub reg_no: String,
    pub gender: String,
}

#[derive(Deserialize)]
pub struct AddBookPayload {
    pub acc_no: i64,
    pub title: String,
    pub author: String,
    pub edition: String,
    pub pub_year: i32,
    pub price: f64,
    pub isbn: String,
    pub subject: String,
    pub location: String,
    pub llib_no: i32,
}

pub async fn add_member(
    Json(payload): Json<AddMemberPayload>,
) -> impl IntoResponse {
    let db_all_path = std::env::var("DATABASE_ALL_PATH")
        .unwrap_or_else(|_| "/app/library-database-allData.db".to_string());

    let conn = match Connection::open(&db_all_path) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open database: {}", e)).into_response(),
    };

    let insert_sql = "
        INSERT INTO personal (
            id_no, name, class, study_year, dept_no, cat_no, 
            lock_login, remarks, password, valid_date, rec_type, 
            address, e_mail, reg_no, gender, active_member, 
            course, blood_group, dob, parent, phone, admn_no, 
            alert_ring, is_club_member, no_book_for_club
        ) VALUES (
            ?, ?, ?, ?, ?, ?, 
            0, 'Added via Admin UI', 'book', '2028-05-31 00:00:00', ?, 
            '-', ?, ?, ?, 1, 
            ?, '-', '2025-10-08 00:00:00', '-', ?, '-', 
            0, 0, 1
        )
    ";

    let rec_type = if payload.class.to_uppercase().contains("STUDENT") { "S" } else { "T" };
    let course = payload.class.clone();

    match conn.execute(
        insert_sql,
        rusqlite::params![
            payload.id_no,
            payload.name,
            payload.class,
            payload.study_year,
            payload.dept_no,
            payload.cat_no,
            rec_type,
            payload.e_mail,
            payload.reg_no,
            payload.gender,
            course,
            payload.phone,
        ],
    ) {
        Ok(_) => (StatusCode::OK, Json(serde_json::json!({ "status": "success", "message": "Member added successfully" }))).into_response(),
        Err(e) => (StatusCode::BAD_REQUEST, format!("Failed to add member: {}", e)).into_response(),
    }
}

pub async fn add_book(
    Json(payload): Json<AddBookPayload>,
) -> impl IntoResponse {
    let db_all_path = std::env::var("DATABASE_ALL_PATH")
        .unwrap_or_else(|_| "/app/library-database-allData.db".to_string());
    let db_combined_path = std::env::var("DATABASE_COMBINED_PATH")
        .unwrap_or_else(|_| "/app/library_database.db".to_string());

    let conn_all = match Connection::open(&db_all_path) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open allData database: {}", e)).into_response(),
    };

    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();

    let book_insert_sql = "
        INSERT INTO book (
            acc_no, title, sub_title, author, edition, pub_no, pub_year, price, 
            price_name, convertion_rate, call_no, page, isbn, gift, gift_note, 
            book_type, damaged, acc_date, keywords, remarks, dept_no, lang_no, 
            lib_no, total_due, current_due, lost, avail, acc_type, ctrl_no, 
            book_size, plates, subject, pur_details, lam_type, origin, country, 
            trace_trans, location, dead, adnl_info, acad_info, return_alert, 
            look_under, illustration, editor, issn, series_name, llib_no, 
            subject_search, cont_page, script_no, vendor_no, edit_date, edit_computer_name
        ) VALUES (
            ?, ?, '-', ?, ?, 1, ?, ?, 
            'Rupees', 1.0, '-', '0', ?, 0, '-', 
            'I', 0, ?, ?, '-', 1, 1, 
            1, 0, 0, 0, 1, 'LIBRARY BUDGET', '0', 
            '-', 'None', ?, '-', 'NORMAL', 'ORIGINAL', 'I', 
            0, ?, 0, '-', 0, 0, 
            '-', '-', '-', '-', '-', ?, 
            0, '-', 0, 1, ?, 'LIB-01'
        )
    ";

    if let Err(e) = conn_all.execute(
        book_insert_sql,
        rusqlite::params![
            payload.acc_no,
            payload.title,
            payload.author,
            payload.edition,
            payload.pub_year,
            payload.price,
            payload.isbn,
            now,
            payload.title,
            payload.subject,
            payload.location,
            payload.llib_no,
            now,
        ],
    ) {
        return (StatusCode::BAD_REQUEST, format!("Failed to insert into allData book table: {}", e)).into_response();
    }

    let conn_comb = match Connection::open(&db_combined_path) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to open library_database: {}", e)).into_response(),
    };

    let books_insert_sql = "
        INSERT INTO Books (
            Accession_Num, Library, Accession_Number, Title, Author, 
            Location___Availability, Circulation_Status, Location_Library, Issue_Criteria, 
            Edition, Publisher, Year_of_Publishing, Price, Classification_Number, 
            Text_Pages, ISBN, Acquisition_Date, Department, Language, Subject, Keywords
        ) VALUES (
            ?, ?, ?, ?, ?, 
            ?, 'Available', ?, 'General', 
            ?, 'Publisher', ?, ?, '-', 
            '0', ?, ?, ?, 'English', ?, ?
        )
    ";

    let library_name = if payload.llib_no == 1 { "KIOT Library" } else { "KBS Library" };
    let acc_no_str = format!("'{}'", payload.acc_no);

    if let Err(e) = conn_comb.execute(
        books_insert_sql,
        rusqlite::params![
            acc_no_str,
            library_name,
            acc_no_str,
            payload.title,
            payload.author,
            payload.location,
            library_name,
            payload.edition,
            payload.pub_year.to_string(),
            payload.price.to_string(),
            payload.isbn,
            now,
            payload.subject,
            payload.subject,
            payload.title,
        ],
    ) {
        return (StatusCode::BAD_REQUEST, format!("Failed to insert into Books table: {}", e)).into_response();
    }

    let unique_books_insert_sql = "
        INSERT INTO unique_books (
            acc_no, title, sub_title, author, edition, pub_no, pub_year, price, 
            price_name, convertion_rate, call_no, page, isbn, gift, gift_note, 
            book_type, damaged, acc_date, keywords, remarks, dept_no, lang_no, 
            lib_no, total_due, current_due, lost, avail, acc_type, ctrl_no, 
            book_size, plates, subject, pur_details, lam_type, origin, country, 
            trace_trans, location, dead, adnl_info, acad_info, return_alert, 
            look_under, illustration, editor, issn, series_name, llib_no, 
            subject_search, cont_page, script_no, vendor_no, edit_date, edit_computer_name,
            all_acc_nos, all_locations, total_copies, available_copies, availability_status, search_blob
        ) VALUES (
            ?, ?, '-', ?, ?, 1, ?, ?, 
            'Rupees', 1.0, '-', '0', ?, 0, '-', 
            'I', 0, ?, ?, '-', 1, 1, 
            1, 0, 0, 0, 1, 'LIBRARY BUDGET', '0', 
            '-', 'None', ?, '-', 'NORMAL', 'ORIGINAL', 'I', 
            0, ?, 0, '-', 0, 0, 
            '-', '-', '-', '-', '-', ?, 
            0, '-', 0, 1, ?, 'LIB-01',
            ?, ?, 1, 1, 'Available', ?
        )
    ";

    let all_acc_nos = payload.acc_no.to_string();
    let all_locations = payload.location.clone();
    let search_blob = format!("{} {} {} {} |{}|", payload.title, payload.author, payload.subject, payload.isbn, payload.acc_no).to_lowercase();

    match conn_comb.execute(
        unique_books_insert_sql,
        rusqlite::params![
            payload.acc_no,
            payload.title,
            payload.author,
            payload.edition,
            payload.pub_year,
            payload.price,
            payload.isbn,
            now,
            payload.title,
            payload.subject,
            payload.location,
            payload.llib_no,
            now,
            all_acc_nos,
            all_locations,
            search_blob,
        ],
    ) {
        Ok(_) => (StatusCode::OK, Json(serde_json::json!({ "status": "success", "message": "Book added successfully to catalog" }))).into_response(),
        Err(e) => (StatusCode::BAD_REQUEST, format!("Failed to insert into unique_books: {}", e)).into_response(),
    }
}