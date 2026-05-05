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
use std::net::{SocketAddr, IpAddr};
use governor::{Quota, RateLimiter, state::keyed::DashMapStateStore, clock::DefaultClock};
use std::num::NonZeroU32;
use rand::Rng;

const LIBRARIAN_KEY: &str = "hellowork.1234"; 
const APP_VERSION: &str = "1.5.3-fix-move";

#[derive(serde::Deserialize)]
struct SendMessageRequest {
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
    let target_url = format!("http://127.0.0.1:8080{}", path_query);
    
    tracing::debug!("[proxy] {} -> {}", method, target_url);
    
    // CLEAR CACHE ON LOGOUT: If we are logging out 'halo', delete the cached QR
    if method == Method::DELETE && path_query.contains("/instance/logout/halo") {
        let _ = std::fs::remove_file("/tmp/whatsapp_qr.json");
        println!("[proxy] Cleared QR cache due to logout of 'halo'");
    }

    let mut proxy_req = state.client.request(method, &target_url);
    
    // Pass through all original headers EXCEPT Cache-related ones to avoid 304 issues
    for (name, value) in req.headers() {
        let n = name.as_str().to_lowercase();
        if n != "host" && n != "if-none-match" && n != "if-modified-since" {
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
            
            // DETECT AND CACHE QR CODE
            if path_query.contains("/instance/connect") {
                if let Ok(v) = serde_json::from_slice::<serde_json::Value>(&bytes) {
                    let qr_data = v.get("qrcode").or(v.get("data").and_then(|d| d.get("qrcode"))).unwrap_or(&v);
                    let code = qr_data.get("code").and_then(|c| c.as_str());
                    let b64 = qr_data.get("base64").and_then(|b| b.as_str());

                    if code.is_some() || b64.is_some() {
                        println!("[proxy][qr] Detected QR code in response. Updating cache...");
                        
                        let cache_obj = serde_json::json!({
                            "code": code,
                            "base64": b64,
                            "timestamp": std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .unwrap_or_default()
                                .as_secs()
                        });
                        let _ = std::fs::write("/tmp/whatsapp_qr.json", cache_obj.to_string());

                        if let Some(c) = code {
                            let js = format!(
                                "const qrt=require('qrcode-terminal');qrt.generate('{}',{{small:true}},(o)=>console.log('\\n[proxy] NEW WHATSAPP QR SCAN NOW:\\n'+o));",
                                c
                            );
                            let _ = std::process::Command::new("node")
                                .arg("-e")
                                .arg(js)
                                .env("NODE_PATH", "/app/evolution/node_modules")
                                .spawn();
                        }
                    }
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
    let instance_name = "halo";
    let evolution_url = "http://127.0.0.1:8080";

    let presence_url = format!("{}/chat/sendPresence/{}", evolution_url, instance_name);
    let _ = state.client.post(&presence_url)
        .header("apikey", LIBRARIAN_KEY)
        .json(&serde_json::json!({
            "number": payload.number,
            "presence": "composing"
        }))
        .send()
        .await;

    let delay_secs = rand::thread_rng().gen_range(3..=6);
    tokio::time::sleep(std::time::Duration::from_secs(delay_secs)).await;

    let message_url = format!("{}/message/sendText/{}", evolution_url, instance_name);
    match state.client.post(&message_url)
        .header("apikey", LIBRARIAN_KEY)
        .json(&serde_json::json!({
            "number": payload.number,
            "text": payload.text
        }))
        .send()
        .await 
    {
        Ok(resp) if resp.status().is_success() => {
            (StatusCode::OK, Json(SendMessageResponse {
                status: "success".to_string(),
                message: "Message sent successfully".to_string(),
            }))
        }
        _ => {
            (StatusCode::BAD_GATEWAY, Json(SendMessageResponse {
                status: "error".to_string(),
                message: "Failed to send message".to_string(),
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
    
    // AUTO-PROVISION 'halo' instance in background if it doesn't exist
    let client_clone = state.client.clone();
    tokio::spawn(async move {
        println!("[auto-provision] Waiting for Evolution API to stabilize...");
        tokio::time::sleep(std::time::Duration::from_secs(15)).await;
        
        for attempt in 1..=5 {
            println!("[auto-provision] Attempt {} to create 'halo' instance...", attempt);
            let create_url = "http://127.0.0.1:8080/instance/create";
            let resp = client_clone.post(create_url)
                .header("apikey", LIBRARIAN_KEY)
                .json(&serde_json::json!({
                    "instanceName": "halo",
                    "qrcode": true,
                    "integration": "WHATSAPP-BAILEYS"
                }))
                .send()
                .await;

            match resp {
                Ok(r) if r.status().is_success() || r.status() == StatusCode::CONFLICT => {
                    println!("[auto-provision] Instance 'halo' created or already exists.");
                    break;
                }
                Ok(r) => {
                    let status = r.status();
                    let text = r.text().await.unwrap_or_default();
                    println!("[auto-provision] Create failed ({}): {}", status, text);
                }
                Err(e) => {
                    println!("[auto-provision] Error calling Evolution API: {}", e);
                }
            }
            tokio::time::sleep(std::time::Duration::from_secs(10)).await;
        }
    });

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
                Ok(content) => (StatusCode::OK, content).into_response(),
                Err(_) => (StatusCode::NOT_FOUND, "QR not ready".to_string()).into_response(),
            }
        }))
        .route("/api/admin/db-check", get(|| async {
            let db_path = "/app/evolution/prisma/evolution.db";
            let output = std::process::Command::new("sqlite3")
                .arg(db_path)
                .arg("SELECT name, connectionStatus, number FROM Instance;")
                .output();

            match output {
                Ok(out) => {
                    let res = String::from_utf8_lossy(&out.stdout).to_string();
                    let err = String::from_utf8_lossy(&out.stderr).to_string();
                    (StatusCode::OK, format!("Out: {}\nErr: {}", res, err)).into_response()
                },
                Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed: {}", e)).into_response(),
            }
        }))
        .route("/api/health", get(|| async { "ok" }))
        .route("/api/version", get(|| async { APP_VERSION }))
        .route("/", get(|| async { format!("Librarian AI Nuclear Gateway v{}", APP_VERSION) }))
        
        .route("/instance/*path", any(proxy_handler))
        .route("/message/*path", any(proxy_handler))
        .route("/chat/*path", any(proxy_handler))
        .route("/group/*path", any(proxy_handler))
        .route("/webhook/*path", any(proxy_handler))
        
        .nest_service("/whatsapp", ServeDir::new("/app/evolution/public")
            .fallback(ServeFile::new("/app/evolution/public/index.html")))
        .fallback_service(static_files)
        .with_state(state)
        .layer(middleware::from_fn(api_key_middleware))
        .layer(cors)
        .layer(TraceLayer::new_for_http());

    println!("[backend] Running on http://0.0.0.0:7860");

    let listener = tokio::net::TcpListener::bind("0.0.0.0:7860").await.unwrap();
    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>()).await.unwrap();
}
