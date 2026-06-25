use serde::{Deserialize, Serialize};

fn get_sidecar_url() -> String {
    std::env::var("SIDECAR_URL").unwrap_or_else(|_| "http://localhost:8001".to_string())
}

#[derive(Serialize)]
struct SearchPayload {
    prompt:  String,
    library: String,
    top_k:   u32,
}

#[derive(Serialize)]
struct ListPayload {
    library: String,
    query:   Option<String>,
}

#[derive(Deserialize, Serialize, Clone)]
pub struct Book {
    pub accession_num: String,
    pub title:         String,
    pub author:        String,
    pub library:       String,
    pub shelf:         String,
    pub status:        String,
    pub edition:       String,
    pub publisher:     String,
    pub year:          String,
    pub price:         String,
    pub isbn:          String,
    pub dept:          String,
    pub subject:       String,
    pub description:   String,
    pub cover_url:     Option<String>,
    pub available:     bool,
    pub similarity:    f64,
}

#[derive(Deserialize)]
pub struct SidecarResponse {
    pub books: Vec<Book>,
    pub reply: String,
}

pub async fn search(
    prompt: &str,
    library: &str,
    top_k: u32,
) -> Result<SidecarResponse, String> {
    let client = reqwest::Client::new();
    let res = client
        .post(format!("{}/api/search", get_sidecar_url()))
        .json(&SearchPayload {
            prompt:  prompt.to_string(),
            library: library.to_string(),
            top_k,
        })
        .send()
        .await
        .map_err(|e| e.to_string())?;

    res.json::<SidecarResponse>()
        .await
        .map_err(|e| e.to_string())
}

pub async fn list_books(
    library: &str,
    query: Option<&str>,
) -> Result<Vec<Book>, String> {
    let client = reqwest::Client::new();
    let res = client
        .post(format!("{}/api/list", get_sidecar_url()))
        .json(&ListPayload {
            library: library.to_string(),
            query: query.map(|s| s.to_string()),
        })
        .send()
        .await
        .map_err(|e| e.to_string())?;

    res.json::<Vec<Book>>()
        .await
        .map_err(|e| e.to_string())
}

#[derive(Serialize)]
struct AdvancedSearchPayload {
    acc_no: Option<String>,
    title:  Option<String>,
    author: Option<String>,
    isbn:   Option<String>,
}

pub async fn advanced_search(
    acc_no: Option<&str>,
    title:  Option<&str>,
    author: Option<&str>,
    isbn:   Option<&str>,
) -> Result<Vec<Book>, String> {
    let payload = AdvancedSearchPayload {
        acc_no: acc_no.map(|s| s.to_string()),
        title:  title.map(|s| s.to_string()),
        author: author.map(|s| s.to_string()),
        isbn:   isbn.map(|s| s.to_string()),
    };
    
    println!("[backend] Calling sidecar /advanced-search for Acc: {:?}, Title: {:?}", payload.acc_no, payload.title);

    let client = reqwest::Client::new();
    let res = client
        .post(format!("{}/api/advanced-search", get_sidecar_url()))
        .json(&payload)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !res.status().is_success() {
        let status = res.status();
        let err_body = res.text().await.unwrap_or_default();
        return Err(format!("Sidecar error ({}): {}", status, err_body));
    }

    res.json::<Vec<Book>>()
        .await
        .map_err(|e| e.to_string())
}

#[derive(Serialize)]
struct BatchPayload {
    acc_nos: Vec<String>,
}

pub async fn get_books_batch(acc_nos: Vec<String>) -> Result<Vec<Book>, String> {
    let client = reqwest::Client::new();
    let res = client
        .post(format!("{}/api/books/batch", get_sidecar_url()))
        .json(&BatchPayload { acc_nos })
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !res.status().is_success() {
        let status = res.status();
        let err_body = res.text().await.unwrap_or_default();
        return Err(format!("Sidecar batch error ({}): {}", status, err_body));
    }

    res.json::<Vec<Book>>()
        .await
        .map_err(|e| e.to_string())
}

#[derive(Serialize)]
struct SettingPayload {
    key: String,
    value: String,
}

#[derive(Deserialize, Serialize)]
pub struct SettingResponse {
    pub key: String,
    pub value: String,
}

pub async fn get_setting(key: &str) -> Result<SettingResponse, String> {
    let client = reqwest::Client::new();
    let res = client
        .get(format!("{}/api/settings/{}", get_sidecar_url(), key))
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !res.status().is_success() {
        let status = res.status();
        let err_body = res.text().await.unwrap_or_default();
        return Err(format!("Sidecar setting error ({}): {}", status, err_body));
    }

    res.json::<SettingResponse>()
        .await
        .map_err(|e| e.to_string())
}

pub async fn set_setting(key: &str, value: &str) -> Result<(), String> {
    let client = reqwest::Client::new();
    let payload = SettingPayload {
        key: key.to_string(),
        value: value.to_string(),
    };
    let res = client
        .post(format!("{}/api/settings", get_sidecar_url()))
        .json(&payload)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !res.status().is_success() {
        let status = res.status();
        let err_body = res.text().await.unwrap_or_default();
        return Err(format!("Sidecar setting error ({}): {}", status, err_body));
    }

    Ok(())
}


