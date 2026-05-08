use axum::Json;
use serde::{Deserialize, Serialize};
use crate::sidecar::{self, Book};

#[derive(Deserialize)]
pub struct SearchRequest {
    pub prompt:  String,
    pub library: Option<String>,
    pub top_k:   Option<u32>,
}

#[derive(Deserialize)]
pub struct ListRequest {
    pub library: String,
    pub query:   Option<String>,
}

#[derive(Deserialize)]
pub struct AdvancedSearchRequest {
    pub acc_no: Option<String>,
    pub title:  Option<String>,
    pub author: Option<String>,
    pub isbn:   Option<String>,
}

#[derive(Serialize)]
pub struct SearchResponse {
    pub books:    Vec<Book>,
    pub reply:    String,
    pub error:    Option<String>,
}

pub async fn search(Json(req): Json<SearchRequest>) -> Json<SearchResponse> {
    let library = req.library.unwrap_or("all".into());
    let top_k   = req.top_k.unwrap_or(5);

    match sidecar::search(&req.prompt, &library, top_k).await {
        Ok(data) => Json(SearchResponse {
            books: data.books,
            reply: data.reply,
            error: None,
        }),
        Err(e) => Json(SearchResponse {
            books: vec![],
            reply: String::new(),
            error: Some(e),
        }),
    }
}

pub async fn list_books(Json(req): Json<ListRequest>) -> Json<SearchResponse> {
    match sidecar::list_books(&req.library, req.query.as_deref()).await {
        Ok(books) => Json(SearchResponse {
            books,
            reply: String::new(),
            error: None,
        }),
        Err(e) => Json(SearchResponse {
            books: vec![],
            reply: String::new(),
            error: Some(e),
        }),
    }
}

pub async fn advanced_search(Json(req): Json<AdvancedSearchRequest>) -> Json<SearchResponse> {
    match sidecar::advanced_search(req.acc_no.as_deref(), req.title.as_deref(), req.author.as_deref(), req.isbn.as_deref()).await {
        Ok(books) => Json(SearchResponse {
            books,
            reply: String::new(),
            error: None,
        }),
        Err(e) => Json(SearchResponse {
            books: vec![],
            reply: String::new(),
            error: Some(e),
        }),
    }
}
