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

const LIBRARIAN_KEY: &str = "LIB_AI_2024_SECURE_TOKEN"; 
const APP_VERSION: &str = "1.3.1-whatsapp-integrated";

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
    let path_query = req.uri().path_and_query().map(|pq| pq.as_str()).unwrap_or("");
    let target_url = format!("http://127.0.0.1:8080{}", path_query);
    
    let mut proxy_req = state.client.request(method, &target_url);
    
    for (name, value) in req.headers() {
        if name != header::HOST {
            proxy_req = proxy_req.header(name, value);
        }
    }

    // SIGN REQUEST: Use the master key to authorize internal proxy requests
    proxy_req = proxy_req.header("apikey", LIBRARIAN_KEY);

    let body_bytes = axum::body::to_bytes(req.into_body(), 15 * 1024 * 1024).await.unwrap_or_default();
    let proxy_req = proxy_req.body(body_bytes);

    match proxy_req.send().await {
        Ok(resp) => {
            let status = StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
            let mut builder = Response::builder().status(status);
            for (name, value) in resp.headers() {
                builder = builder.header(name, value);
            }
            let bytes = resp.bytes().await.unwrap_or_default();
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
    let api_key = "hellowork.1234";
    let evolution_url = "http://127.0.0.1:8080";

    let presence_url = format!("{}/chat/sendPresence/{}", evolution_url, instance_name);
    let _ = state.client.post(&presence_url)
        .header("apikey", api_key)
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
        .header("apikey", api_key)
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
                message: "Message sent successfully with anti-ban protection".to_string(),
            }))
        }
        _ => {
            (StatusCode::BAD_GATEWAY, Json(SendMessageResponse {
                status: "error".to_string(),
                message: "Failed to send message via Evolution API".to_string(),
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
    
    // BOLD EXEMPTION: Allow all Evolution API routes to bypass security
    if path.starts_with("/instance/") || 
       path.starts_with("/message/") || 
       path.starts_with("/chat/") || 
       path.starts_with("/group/") || 
       path.starts_with("/webhook/") || 
       path.starts_with("/typebot/") || 
       path.starts_with("/chatwoot/") ||
       path.starts_with("/whatsapp/") ||
       path == "/instance/fetchInstances" { // Explicit for fetch
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
            // Addition: Check 'apikey' header specifically for WhatsApp routes
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

    let quota = Quota::per_minute(NonZeroU32::new(60).unwrap());
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
        // CORE API ROUTES
        .route("/api/search", post(routes::search::search))
        .route("/api/list", post(routes::search::list_books))
        .route("/api/advanced-search", post(routes::search::advanced_search))
        .route("/api/overdue", get(routes::overdue::get_overdue_books))
        .route("/api/whatsapp/send", post(send_message))
        .route("/api/health", get(|| async { "ok" }))
        .route("/api/version", get(|| async { APP_VERSION }))
        
        // BASE ROUTE
        .route("/", get(|| async { 
            format!("Librarian AI Backend Gateway v{}\nStatus: Running", APP_VERSION) 
        }))
        
        // WHATSAPP PROXIES
        .route("/instance/*path", any(proxy_handler))
        .route("/message/*path", any(proxy_handler))
        .route("/chat/*path", any(proxy_handler))
        .route("/group/*path", any(proxy_handler))
        .route("/webhook/*path", any(proxy_handler))
        .route("/typebot/*path", any(proxy_handler))
        .route("/chatwoot/*path", any(proxy_handler))
        
        // STATIC ASSETS
        .nest_service("/whatsapp", ServeDir::new("/app/evolution/public")
            .fallback(ServeFile::new("/app/evolution/public/index.html")))
        .fallback_service(static_files)
        
        // STATE AND MIDDLEWARE
        .with_state(state)
        .layer(middleware::from_fn(api_key_middleware))
        .layer(cors)
        .layer(TraceLayer::new_for_http());

    println!("[backend] Running on http://0.0.0.0:7860");
    let listener = tokio::net::TcpListener::bind("0.0.0.0:7860").await.unwrap();
    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>()).await.unwrap();
}
