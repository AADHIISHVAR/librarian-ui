mod sidecar;
mod routes;
use axum::{
    Router, 
    routing::post, 
    routing::get,
    routing::any,
    http::{Request, StatusCode, header, Method},
    middleware::{self, Next},
    response::{Response, IntoResponse},
    extract::{ConnectInfo, State},
    body::Body,
    Json,
};
use tower_http::cors::CorsLayer;
use tower_http::services::{ServeDir, ServeFile};
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use std::sync::Arc;
use std::io::Read;
use flate2::read::GzDecoder;
use std::net::{SocketAddr, IpAddr};
use governor::{Quota, RateLimiter, state::keyed::DashMapStateStore, clock::DefaultClock};
use std::num::NonZeroU32;
use rand::Rng;

const LIBRARIAN_KEY: &str = "hellowork.1234"; 
const APP_VERSION: &str = "1.5.3-fix-move";

#[derive(serde::Deserialize)]
struct SendMessageRequest {
    pub instance: String,
    pub number: String,
    pub text: String,
}

#[derive(serde::Serialize)]
struct SendMessageResponse {
    pub status: String,
    pub message: String,
}

type IpRateLimiter = RateLimiter<IpAddr, DashMapStateStore<IpAddr>, DefaultClock>;

struct RateLimitState {
    limiter: IpRateLimiter,
}

struct AppState {
    rate_limit: Arc<RateLimitState>,
    client: reqwest::Client,
}

async fn proxy_handler(
    State(state): State<Arc<AppState>>,
    method: Method,
    req: Request<Body>,
) -> Response {
    let path_query = req
        .uri()
        .path_and_query()
        .map(|pq| pq.as_str().to_owned())
        .unwrap_or_default();
    let target_url = format!("http://20.6.122.244:8080{}", path_query);
    
    tracing::debug!("[proxy] {} -> {}", method, target_url);
    
    // CLEAR CACHE ON LOGOUT: If we are logging out an instance, delete the cached QR
    if method == Method::DELETE && path_query.contains("/instance/logout/") {
        let _ = std::fs::remove_file("/tmp/whatsapp_qr.json");
        println!("[proxy] Cleared QR cache due to instance logout");
    }

    let mut proxy_req = state.client.request(method, &target_url)
        .header("Accept-Encoding", "identity");
    
    // Pass through all original headers EXCEPT Cache-related ones to avoid 304 issues
    for (name, value) in req.headers() {
        let n = name.as_str().to_lowercase();
        if n != "host" && n != "if-none-match" && n != "if-modified-since" && n != "apikey" {
            proxy_req = proxy_req.header(name, value);
        }
    }

    // SIGN REQUEST: Use the master key to authorize internal proxy requests
    proxy_req = proxy_req.header("apikey", LIBRARIAN_KEY);

    let body_bytes = axum::body::to_bytes(req.into_body(), 20 * 1024 * 1024).await.unwrap_or_default();
    let proxy_req = proxy_req.body(body_bytes);

    match proxy_req.send().await {
        Ok(resp) => {
            let status = StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
            let mut builder = Response::builder()
                .status(status)
                // Force NO CACHE on every response to fix 304 loops
                .header("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate")
                .header("Pragma", "no-cache")
                .header("Expires", "0");
                
            for (name, value) in resp.headers() {
                if name.as_str().to_lowercase() != "cache-control" {
                    builder = builder.header(name, value);
                }
            }
            let bytes = resp.bytes().await.unwrap_or_default();
            
            // HANDLE GZIP COMPRESSION: If the response is gzipped, decompress it before parsing
            let decoded_bytes = if bytes.starts_with(&[0x1f, 0x8b]) {
                tracing::info!("[proxy] Gzip compression detected. Decompressing...");
                let mut decoder = GzDecoder::new(&bytes[..]);
                let mut decompressed = Vec::new();
                if decoder.read_to_end(&mut decompressed).is_ok() {
                    decompressed
                } else {
                    tracing::error!("[proxy] Gzip decompression failed");
                    bytes.to_vec()
                }
            } else {
                bytes.to_vec()
            };
            
            // DETECT AND CACHE QR CODE (Using decoded bytes)
            if path_query.contains("/instance/connect") {
                tracing::info!("[proxy] Checking for QR in response from: {}", target_url);
                if let Ok(v) = serde_json::from_slice::<serde_json::Value>(&decoded_bytes) {
                    let qr_data = v.get("qrcode").or(v.get("data").and_then(|d| d.get("qrcode"))).unwrap_or(&v);
                    let code = qr_data.get("code").and_then(|c| c.as_str());
                    let b64 = qr_data.get("base64").and_then(|b| b.as_str());
            
                    if code.is_some() || b64.is_some() {
                        println!("[proxy][qr] Detected QR code in response. Updating cache...");
                        
                        let cache_obj = serde_json::json!({
                            "instance": path_query.split('/').nth(2).unwrap_or("unknown"),
                            "code": code,
                            "base64": b64,
                            "timestamp": std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .unwrap_or_default()
                                .as_secs()
                        });
                        let _ = std::fs::write("/tmp/whatsapp_qr.json", cache_obj.to_string());
            
                        if let Some(c) = code {
                            let qr_js_str = serde_json::to_string(c).unwrap_or_else(|_| "\"\"".to_string());
                            tracing::info!("[proxy] Rendering QR code to terminal...");
                        }
                    } else {
                        tracing::warn!("[proxy][qr] No QR found in response body. Body: {:?}", String::from_utf8_lossy(&decoded_bytes));
                    }
                } else {
                    tracing::warn!("[proxy][qr] Response body is not valid JSON. Body: {:?}", String::from_utf8_lossy(&decoded_bytes));
                }
            }
            builder.body(Body::from(bytes)).unwrap().into_response()
        }
        Err(e) => {
            tracing::error!("Proxy error: {}", e);
            (StatusCode::BAD_GATEWAY, format!("Proxy error: {}", e)).into_response()
        }
    }
}

async fn send_message(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<SendMessageRequest>,
) -> impl IntoResponse {
    let instance_name = payload.instance;
    let evolution_url = "http://20.6.122.244:8080";

    let message_url = format!("{}/message/sendText/{}", evolution_url, instance_name);
    
    // Updated payload according to Evolution API v2 specifications
    let evolution_payload = serde_json::json!({
        "number": payload.number,
        "options": {
            "delay": 1200,
            "presence": "composing"
        },
        "textMessage": {
            "text": payload.text
        }
    });

    match state.client.post(&message_url)
        .header("apikey", LIBRARIAN_KEY)
        .json(&evolution_payload)
        .send()
        .await 
    {
        Ok(resp) if resp.status().is_success() => {
            (StatusCode::OK, Json(SendMessageResponse {
                status: "success".to_string(),
                message: "Message sent successfully".to_string(),
            }))
        }
        Ok(resp) => {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            tracing::error!("[send_message] Evolution API error ({}): {}", status, body);
            (StatusCode::BAD_GATEWAY, Json(SendMessageResponse {
                status: "error".to_string(),
                message: format!("Evolution API error ({}): {}", status, body),
            }))
        }
        Err(e) => {
            tracing::error!("Proxy error: {}", e);
            (StatusCode::BAD_GATEWAY, Json(SendMessageResponse {
                status: "error".to_string(),
                message: format!("Network error: {}", e),
            }))
        }
    }
}

async fn rate_limit_middleware(
    connect_info: Option<ConnectInfo<SocketAddr>>,
    State(state): State<Arc<AppState>>,
    req: Request<axum::body::Body>,
    next: Next,
) -> Result<Response, StatusCode> {
    let ip = req.headers()
        .get("x-forwarded-for")
        .and_then(|h| h.to_str().ok())
        .and_then(|s| s.split(',').next())
        .and_then(|s| s.trim().parse::<IpAddr>().ok())
        .or_else(|| connect_info.map(|ci| ci.0.ip()))
        .unwrap_or_else(|| "127.0.0.1".parse().unwrap());

    if state.rate_limit.limiter.check_key(&ip).is_ok() {
        Ok(next.run(req).await)
    } else {
        tracing::warn!("Rate limit exceeded for IP: {}", ip);
        Err(StatusCode::TOO_MANY_REQUESTS)
    }
}

async fn api_key_middleware(req: Request<axum::body::Body>, next: Next) -> Result<Response, StatusCode> {
    let path = req.uri().path();
    
    // NUCLEAR EXEMPTION: Trust every path that sounds like WhatsApp, Health, OR SEARCH for troubleshooting
    if path == "/" ||
       path == "/api/health" ||
       path == "/api/version" ||
       path == "/api/search" ||
       path == "/api/list" ||
       path == "/api/advanced-search" ||
       path.contains("/instance") || 
       path.contains("/message") || 
       path.contains("/chat") || 
       path.contains("/group") || 
       path.contains("/webhook") || 
       path.contains("/whatsapp") {
        return Ok(next.run(req).await);
    }

    if req.method() == axum::http::Method::OPTIONS {
        return Ok(next.run(req).await);
    }

    let auth_header = req.headers()
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "))
        .or_else(|| {
            req.headers()
                .get("x-librarian-key")
                .and_then(|h| h.to_str().ok())
        })
        .or_else(|| {
            req.headers()
                .get("apikey")
                .and_then(|h| h.to_str().ok())
        });

    match auth_header {
        Some(key) if key == LIBRARIAN_KEY => Ok(next.run(req).await),
        _ => {
            tracing::warn!("Unauthorized: Missing or invalid API key");
            Err(StatusCode::UNAUTHORIZED)
        }
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "library_backend=debug,tower_http=debug".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cors = CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods(tower_http::cors::Any)
        .allow_headers(tower_http::cors::Any);

    let quota = Quota::per_minute(NonZeroU32::new(120).unwrap());
    let rate_limit_state = Arc::new(RateLimitState {
        limiter: RateLimiter::keyed(quota),
    });

    let state = Arc::new(AppState {
        rate_limit: rate_limit_state,
        client: reqwest::Client::new(),
    });

    println!("[backend] v{} Starting...", APP_VERSION);
 
    let static_files = ServeDir::new("/app/dist")
        .fallback(ServeFile::new("/app/dist/index.html"));
 
    let app = Router::new()
        .route("/api/search", post(routes::search::search))
        .route("/api/list", post(routes::search::list_books))
        .route("/api/advanced-search", post(routes::search::advanced_search))
        .route("/api/overdue", get(routes::overdue::get_overdue_books))
        .route("/api/whatsapp/send", post(send_message))
        .route("/api/whatsapp/qr", get(|| async {
            match std::fs::read_to_string("/tmp/whatsapp_qr.json") {
                Ok(content) => {
                    Response::builder()
                        .status(StatusCode::OK)
                        .header(header::CONTENT_TYPE, "application/json")
                        .body(Body::from(content))
                        .unwrap()
                        .into_response()
                },
                Err(_) => (StatusCode::NOT_FOUND, "QR not ready".to_string()).into_response(),
            }
        }))
        .route("/api/admin/db-check", get(|| async {
            // Removed local DB check as API is now on Azure
            (StatusCode::OK, "Database check is now handled by Azure VM".to_string()).into_response()
        }))

        .route("/api/health", get(|| async { "ok" }))
        .route("/api/version", get(|| async { APP_VERSION }))
        .route("/", get(|| async { format!("Librarian AI Nuclear Gateway v{}", APP_VERSION) }))
        
        .route("/instance/*path", any(proxy_handler))
        .route("/message/*path", any(proxy_handler))
        .route("/chat/*path", any(proxy_handler))
        .route("/group/*path", any(proxy_handler))
        .route("/webhook/*path", any(proxy_handler))
        // Removed .nest_service("/whatsapp", ...) as the local files were deleted
        .fallback_service(static_files)
        .with_state(state)
        .layer(middleware::from_fn(api_key_middleware))
        .layer(cors)
        .layer(TraceLayer::new_for_http());

    println!("[backend] Running on http://0.0.0.0:7860");
 
    let listener = tokio::net::TcpListener::bind("0.0.0.0:7860").await.unwrap();
    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>()).await.unwrap();
}
