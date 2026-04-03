# Web Dashboard & Error UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local web management dashboard for the bash-mirror server (token/QR, sessions, live logs) and fix silent auth error handling on iOS.

**Architecture:** The web dashboard is an axum HTTP server running alongside the existing WebSocket server on a separate port bound to 127.0.0.1. It shares `Arc<Mutex<PairingManager>>` and `Arc<Mutex<SessionManager>>` with the WS server, and receives log events via a `tokio::sync::broadcast` channel. The frontend is a single HTML file bundled via `include_str!`. The iOS fix simplifies auth error display by removing timing-dependent `onChange` logic in favor of direct `authError != nil` checks and `onAppear`.

**Tech Stack:** Rust (axum, tokio, serde_json, qrcode), SwiftUI (iOS 26.0+)

**Build commands:**
- Rust: `cargo build -p bash-mirror-cli`
- iOS: `xcodebuild -project ios/BashMirror/BashMirror.xcodeproj -scheme BashMirror -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" -derivedDataPath /tmp/bash-mirror-build build`

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| **Modify** | `crates/bash-mirror-cli/Cargo.toml` | Add axum, qrcode, tower-http deps |
| **Create** | `crates/bash-mirror-cli/src/web_dashboard.rs` | Axum HTTP server: routes, handlers, SSE, shared state |
| **Create** | `crates/bash-mirror-cli/src/dashboard_html.html` | Single-page HTML/CSS/JS dashboard frontend |
| **Modify** | `crates/bash-mirror-cli/src/main.rs` | Add CLI flags, spawn web dashboard, set up broadcast channel |
| **Modify** | `crates/bash-mirror-cli/src/server.rs` | Clone broadcast sender for log forwarding |
| **Modify** | `ios/BashMirror/BashMirror/BashMirrorApp.swift` | Fix ScannerContainerView error display |
| **Modify** | `ios/BashMirror/BashMirror/Views/ManualConnectView.swift` | Fix early dismiss, show errors properly |

---

## Track A: iOS Error UX Fix (Tasks 1-2)

These are independent of the web dashboard and can be done first or in parallel.

### Task 1: Fix ScannerContainerView error display

**Files:**
- Modify: `ios/BashMirror/BashMirror/BashMirrorApp.swift`

The current approach uses `@State private var showError` with `onChange(of: connectionManager.authError)`, which doesn't trigger reliably when the view reappears after a sheet dismissal. Fix: remove `showError` state and use `connectionManager.authError != nil` directly.

- [ ] **Step 1: Remove showError state and simplify error display**

In `ScannerContainerView`, remove the line:
```swift
    @State private var showError = false
```

Replace the error banner condition:
```swift
                    // Auth error
                    if showError, let error = connectionManager.authError {
```
with:
```swift
                    // Auth error
                    if let error = connectionManager.authError {
```

Remove the `.onTapGesture` that sets `showError = false` — keep only the `authError = nil`:
```swift
                        .onTapGesture {
                            connectionManager.authError = nil
                        }
```

Replace the `.onChange(of: connectionManager.authError)` block:
```swift
        .onChange(of: connectionManager.authError) {
            if connectionManager.authError != nil {
                showError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    showError = false
                    connectionManager.authError = nil
                }
            }
        }
```
with a simpler auto-dismiss using `.task`:
```swift
        .task(id: connectionManager.authError) {
            guard connectionManager.authError != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            connectionManager.authError = nil
        }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project ios/BashMirror/BashMirror.xcodeproj -scheme BashMirror \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" \
  -derivedDataPath /tmp/bash-mirror-build build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/BashMirror/BashMirror/BashMirrorApp.swift
git commit -m "fix(ios): show auth error reliably on connection screen

Removed showError state that caused timing issues with onChange.
Now uses authError != nil directly with .task for auto-dismiss."
```

---

### Task 2: Fix ManualConnectView early dismiss

**Files:**
- Modify: `ios/BashMirror/BashMirror/Views/ManualConnectView.swift`

Currently `dismiss()` is called immediately when tapping Connect, before the async auth completes. If auth fails, the sheet is already gone and the error banner is never seen. Fix: remove `dismiss()` from the button action, add `onChange(of: connectionManager.state)` that dismisses only on `.connected`.

- [ ] **Step 1: Remove dismiss from connect button, add state-based dismiss**

Find the connect button action (around line 104-107):
```swift
                    Button(action: {
                        guard let portNum = Int(port) else { return }
                        connectionManager.connect(host: host, port: portNum, token: token)
                        dismiss()
                    }) {
```

Remove `dismiss()`:
```swift
                    Button(action: {
                        guard let portNum = Int(port) else { return }
                        connectionManager.connect(host: host, port: portNum, token: token)
                    }) {
```

Add a dismiss-on-success modifier. Find `.presentationBackground(Theme.Colors.background)` and add before it:
```swift
        .onChange(of: connectionManager.state) {
            if connectionManager.state == .connected {
                dismiss()
            }
        }
```

- [ ] **Step 2: Make ConnectionState conform to Equatable**

Check if `ConnectionState` already conforms to `Equatable`. If not, update it in `ConnectionManager.swift`. Find:
```swift
enum ConnectionState {
    case disconnected
    case connecting
    case connected
}
```
Add `Equatable`:
```swift
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project ios/BashMirror/BashMirror.xcodeproj -scheme BashMirror \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" \
  -derivedDataPath /tmp/bash-mirror-build build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ios/BashMirror/BashMirror/Views/ManualConnectView.swift ios/BashMirror/BashMirror/Services/ConnectionManager.swift
git commit -m "fix(ios): dismiss manual connect only on successful auth

Don't dismiss the sheet when tapping Connect — wait for the server
to respond. If auth fails, the error banner shows on the form.
If auth succeeds, onChange detects .connected and dismisses."
```

---

## Track B: Web Dashboard (Tasks 3-7)

### Task 3: Add dependencies to Cargo.toml

**Files:**
- Modify: `crates/bash-mirror-cli/Cargo.toml`

- [ ] **Step 1: Add axum, qrcode, tower, and open deps**

Add to the `[dependencies]` section:
```toml
axum = { version = "0.8", features = ["json"] }
tower-http = { version = "0.6", features = ["cors"] }
qrcode = "0.14"
open = "5"
```

- [ ] **Step 2: Build to verify deps resolve**

```bash
cargo build -p bash-mirror-cli 2>&1 | tail -5
```
Expected: downloads deps and builds successfully.

- [ ] **Step 3: Commit**

```bash
git add crates/bash-mirror-cli/Cargo.toml Cargo.lock
git commit -m "chore(cli): add axum, qrcode, tower-http, open dependencies"
```

---

### Task 4: Create dashboard HTML frontend

**Files:**
- Create: `crates/bash-mirror-cli/src/dashboard_html.html`

- [ ] **Step 1: Create the single-page HTML dashboard**

Create `crates/bash-mirror-cli/src/dashboard_html.html` with a complete single-page dashboard. The HTML must be self-contained (inline CSS + JS, no external dependencies).

Key requirements:
- Dark theme matching the app aesthetic (#0A0A0F background, #22D3EE cyan accents, monospace font)
- **Header section**: "bash-mirror" title, server URL, uptime counter
- **Token section**: Current token (copyable click-to-copy), short code, QR code as inline SVG, countdown timer, "Rotate Token" button
- **Sessions section**: Table of active sessions (ID, shell, status) with "Close" button per row
- **Devices section**: List of connected device addresses
- **Logs section**: Scrolling log viewer, auto-scrolls to bottom
- JavaScript logic:
  - On load: `fetch('/api/status')` to populate all sections
  - QR code: fetch from `/api/qr` and inject SVG
  - "Rotate Token" button: `POST /api/rotate-token`, then refresh status
  - "Close Session" button: `POST /api/sessions/{id}/close`, then refresh
  - SSE: `new EventSource('/api/logs/stream')` for live log updates
  - Token countdown: `setInterval` that decrements remaining seconds
  - Polling: `setInterval` every 5s to refresh `/api/status` for session/device changes and token expiry

The HTML should be approximately 300-400 lines. Use CSS variables for theming. Use `fetch` for API calls. No frameworks.

- [ ] **Step 2: Commit**

```bash
git add crates/bash-mirror-cli/src/dashboard_html.html
git commit -m "feat(cli): add web dashboard HTML frontend"
```

---

### Task 5: Create web dashboard Rust module

**Files:**
- Create: `crates/bash-mirror-cli/src/web_dashboard.rs`

- [ ] **Step 1: Create the web dashboard module**

Create `crates/bash-mirror-cli/src/web_dashboard.rs` with the following structure:

```rust
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, Json, Sse},
    routing::{get, post},
    Router,
};
use axum::extract::Path;
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

// Shared state passed to all handlers
#[derive(Clone)]
pub struct DashboardState {
    pub pairing: Arc<Mutex<PairingManager>>,
    pub sessions: Arc<Mutex<SessionManager>>,
    pub log_tx: broadcast::Sender<String>,
    pub server_url: String,
    pub started_at: Instant,
}

// API response types
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
    let sessions = sm.list_sessions().into_iter().map(|s| SessionEntry {
        id: s.id,
        shell: s.shell,
        alive: s.alive,
    }).collect();
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
            let _ = state.log_tx.send(format!("Session {} closed via web dashboard", id));
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

    // Build the QR payload — use the server URL
    let qr_data = format!("{}?token={}", state.server_url, token);
    let code = QrCode::new(qr_data.as_bytes()).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let svg_str = code.render::<svg::Color>()
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

/// Start the web dashboard server. Returns the bound address.
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
```

Note: This requires the `async-stream` crate. Add it to Cargo.toml:
```toml
async-stream = "0.3"
```

- [ ] **Step 2: Add `mod web_dashboard;` to main.rs**

At the top of `crates/bash-mirror-cli/src/main.rs`, add:
```rust
mod web_dashboard;
```

- [ ] **Step 3: Add async-stream dep and build**

```bash
cargo build -p bash-mirror-cli 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add crates/bash-mirror-cli/src/web_dashboard.rs crates/bash-mirror-cli/src/main.rs crates/bash-mirror-cli/Cargo.toml Cargo.lock
git commit -m "feat(cli): add web dashboard axum module with API handlers"
```

---

### Task 6: Wire dashboard into main.rs

**Files:**
- Modify: `crates/bash-mirror-cli/src/main.rs`

- [ ] **Step 1: Add CLI flags**

In the `Cli` struct, add after `auth_timeout`:
```rust
    /// Disable auto-opening dashboard in browser
    #[arg(long)]
    no_open: bool,

    /// Dashboard web UI port (0 = random)
    #[arg(long, default_value = "0")]
    dashboard_port: u16,
```

- [ ] **Step 2: Add broadcast channel and start dashboard**

In `main()`, after the event channels are created (`let (event_tx, event_rx) = ...`), add a broadcast channel for logs:
```rust
    // Broadcast channel for log events (web dashboard SSE)
    let (log_tx, _) = tokio::sync::broadcast::channel::<String>(256);
```

After the server is spawned (after the `tokio::spawn` for `server::run_server`), before the `if cli.no_tui` block, add the web dashboard startup:
```rust
    // Start web dashboard
    let dashboard_state = web_dashboard::DashboardState {
        pairing: pairing.clone(),
        sessions: session_mgr.clone(),
        log_tx: log_tx.clone(),
        server_url: format!("{}://{}:{}", ws_scheme, lan_ip, port),
        started_at: std::time::Instant::now(),
    };

    let dashboard_addr = web_dashboard::start_dashboard(
        dashboard_state,
        cli.dashboard_port,
    ).await?;

    let dashboard_url = format!("http://{}", dashboard_addr);
    info!("Web dashboard: {}", dashboard_url);

    if !cli.no_open {
        let _ = open::that(&dashboard_url);
    }
```

- [ ] **Step 3: Forward server events to broadcast channel**

Find where `ServerEvent::Log` is handled in the TUI action handler. Also add log forwarding in the event processing. In the headless mode block, after the SIGUSR1 handler setup, add a log forwarding task:

```rust
        // Forward server events to broadcast channel for web dashboard
        let log_fwd_tx = log_tx.clone();
        let mut log_fwd_rx = event_tx.subscribe(); // This won't work — event_tx is mpsc, not broadcast
```

Actually, the event channel is `mpsc::unbounded_channel`. We can't subscribe to it from multiple places. Instead, have the dashboard send logs directly via `log_tx.send()`. The server events that matter (client connected, session created, etc.) already go through the event channel. For the web dashboard, we'll add `log_tx.send()` calls at the key points in `main.rs` where events are already handled, and also pass `log_tx` to the server for forwarding.

Simpler approach: in the headless mode event-wait section, also forward events to the broadcast channel. But since we're in `ctrl_c().await`, there's no event processing in headless mode.

Simplest approach: pass `log_tx` to `server::run_server` and have it send log messages alongside the existing event_tx sends. Add `log_tx: broadcast::Sender<String>` to `ServerConfig`:

In `server.rs`, add to `ServerConfig`:
```rust
    pub log_broadcast: Option<broadcast::Sender<String>>,
```

In the server's key log points (client connected, authenticated, disconnected, session created/closed), add:
```rust
if let Some(ref tx) = config.log_broadcast {
    let _ = tx.send(format!("..."));
}
```

Update `ServerConfig` construction in `main.rs`:
```rust
    let server_config = ServerConfig {
        tls_acceptor,
        max_connections: cli.max_connections,
        auth_timeout_secs: cli.auth_timeout,
        log_broadcast: Some(log_tx.clone()),
    };
```

- [ ] **Step 4: Build**

```bash
cargo build -p bash-mirror-cli 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add crates/bash-mirror-cli/src/main.rs crates/bash-mirror-cli/src/server.rs
git commit -m "feat(cli): wire web dashboard into server startup with log broadcasting"
```

---

### Task 7: Integration test — run server and verify dashboard

**Files:** None (verification only)

- [ ] **Step 1: Build clean**

```bash
cargo build -p bash-mirror-cli 2>&1 | tail -3
```

- [ ] **Step 2: Start server and verify dashboard opens**

```bash
cargo run -p bash-mirror-cli -- --no-tui --no-tls --port 8765
```

Expected:
- Server starts, prints token info
- Web dashboard URL printed (e.g., `http://127.0.0.1:XXXXX`)
- Browser auto-opens to the dashboard
- Dashboard shows: token, QR code, countdown, empty sessions list, log viewer

- [ ] **Step 3: Test token rotation**

On the dashboard page, click "Rotate Token". Verify:
- New token and code appear
- QR code updates
- Countdown resets
- Log shows "Token rotated via web dashboard"

- [ ] **Step 4: Test with --no-open**

```bash
cargo run -p bash-mirror-cli -- --no-tui --no-tls --port 8765 --no-open
```

Verify browser does NOT auto-open, but the URL is still printed and accessible manually.

- [ ] **Step 5: Commit any fixes needed**

```bash
git add -A crates/bash-mirror-cli/
git commit -m "fix(cli): polish web dashboard integration"
```

---

## Summary

| Task | Track | What | Files |
|------|-------|------|-------|
| 1 | iOS | Fix scanner error display timing | `BashMirrorApp.swift` |
| 2 | iOS | Fix manual connect early dismiss | `ManualConnectView.swift`, `ConnectionManager.swift` |
| 3 | Rust | Add axum/qrcode deps | `Cargo.toml` |
| 4 | Rust | Create dashboard HTML frontend | `dashboard_html.html` |
| 5 | Rust | Create web dashboard Rust module | `web_dashboard.rs` |
| 6 | Rust | Wire dashboard into main.rs | `main.rs`, `server.rs` |
| 7 | Rust | Integration test | (verification) |

**Parallelism:** Track A (Tasks 1-2) and Track B (Tasks 3-7) are fully independent and can be executed in parallel. Within Track B, tasks must be sequential.
