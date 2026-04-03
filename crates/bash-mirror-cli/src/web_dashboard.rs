use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, Json, Sse},
    routing::{get, post},
    Router,
};
use axum::response::sse::{Event, KeepAlive};
use bash_mirror_core::auth::PairingManager;
use bash_mirror_core::session_mgr::SessionManager;
use futures_util::stream::Stream;
use qrcode::{QrCode, render::svg};
use serde::Serialize;
use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{broadcast, Mutex};

#[derive(Clone)]
pub struct DashboardState {
    pub pairing: Arc<Mutex<PairingManager>>,
    pub sessions: Arc<Mutex<SessionManager>>,
    pub log_tx: broadcast::Sender<String>,
    pub server_url: String,
    pub lan_ip: std::net::IpAddr,
    pub port: u16,
    pub cert_fingerprint: String,
    pub started_at: Instant,
}

#[derive(Serialize)]
struct StatusResponse {
    server_url: String,
    uptime_secs: u64,
    token: Option<TokenInfo>,
    sessions: Vec<SessionEntry>,
}

#[derive(Serialize)]
struct TokenInfo {
    token: String,
    short_code: String,
    remaining_secs: u64,
    expired: bool,
}

#[derive(Serialize)]
struct SessionEntry {
    id: String,
    shell: String,
    alive: bool,
}

#[derive(Serialize)]
struct RotateResponse {
    token: String,
    short_code: String,
    remaining_secs: u64,
}

pub fn create_router(state: DashboardState) -> Router {
    Router::new()
        .route("/", get(serve_html))
        .route("/api/status", get(get_status))
        .route("/api/rotate-token", post(rotate_token))
        .route("/api/sessions/{id}/close", post(close_session))
        .route("/api/qr", get(get_qr))
        .route("/api/logs/stream", get(logs_stream))
        .with_state(state)
}

async fn serve_html() -> Html<&'static str> {
    Html(include_str!("dashboard_html.html"))
}

async fn get_status(State(state): State<DashboardState>) -> Json<StatusResponse> {
    let pm = state.pairing.lock().await;
    let token_info = pm.current_token().map(|t| TokenInfo {
        token: t.token.to_string(),
        short_code: t.short_code.clone(),
        remaining_secs: t.remaining_secs(),
        expired: t.is_expired(),
    });
    drop(pm);

    let mut sm = state.sessions.lock().await;
    let sessions = sm
        .list_sessions()
        .into_iter()
        .map(|s| SessionEntry {
            id: s.id,
            shell: s.shell,
            alive: s.alive,
        })
        .collect();
    drop(sm);

    Json(StatusResponse {
        server_url: state.server_url.clone(),
        uptime_secs: state.started_at.elapsed().as_secs(),
        token: token_info,
        sessions,
    })
}

async fn rotate_token(State(state): State<DashboardState>) -> Json<RotateResponse> {
    let mut pm = state.pairing.lock().await;
    let new_token = pm.generate_token();
    let resp = RotateResponse {
        token: new_token.token.to_string(),
        short_code: new_token.short_code.clone(),
        remaining_secs: new_token.ttl.as_secs(),
    };
    let _ = state.log_tx.send("Token rotated via web dashboard".into());
    drop(pm);
    Json(resp)
}

async fn close_session(
    State(state): State<DashboardState>,
    Path(id): Path<String>,
) -> StatusCode {
    let mut sm = state.sessions.lock().await;
    match sm.close_session(&id) {
        Ok(_) => {
            let _ = state
                .log_tx
                .send(format!("Session {} closed via web dashboard", id));
            StatusCode::OK
        }
        Err(_) => StatusCode::NOT_FOUND,
    }
}

async fn get_qr(State(state): State<DashboardState>) -> Result<Html<String>, StatusCode> {
    let pm = state.pairing.lock().await;
    let token = match pm.current_token() {
        Some(t) => t.token.to_string(),
        None => return Err(StatusCode::NOT_FOUND),
    };
    drop(pm);

    let qr_data = PairingManager::qr_payload(state.lan_ip, state.port, &token, &state.cert_fingerprint);
    let code = QrCode::new(qr_data.as_bytes()).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let svg_str = code
        .render::<svg::Color>()
        .min_dimensions(200, 200)
        .dark_color(svg::Color("#22D3EE"))
        .light_color(svg::Color("#0A0A0F"))
        .build();
    Ok(Html(svg_str))
}

async fn logs_stream(
    State(state): State<DashboardState>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let mut rx = state.log_tx.subscribe();
    let stream = async_stream::stream! {
        while let Ok(msg) = rx.recv().await {
            yield Ok(Event::default().data(msg));
        }
    };
    Sse::new(stream).keep_alive(KeepAlive::default())
}

pub async fn start_dashboard(
    state: DashboardState,
    port: u16,
) -> anyhow::Result<SocketAddr> {
    let app = create_router(state);
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    let actual_addr = listener.local_addr()?;
    tokio::spawn(async move {
        axum::serve(listener, app).await.ok();
    });
    Ok(actual_addr)
}
