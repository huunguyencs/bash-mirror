use anyhow::Result;
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use bash_mirror_core::auth::{AuthResult, PairingManager};
use bash_mirror_core::session_mgr::SessionManager;
use bash_mirror_proto::{ClientMessage, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::net::TcpListener;
use tokio::sync::{mpsc, Mutex};
use tokio_rustls::TlsAcceptor;
use tokio_tungstenite::accept_hdr_async;
use tracing::{error, info, warn};
use tungstenite::handshake::server::{Request, Response};
use tungstenite::Message;

/// Events emitted by the server for the dashboard
#[derive(Debug, Clone)]
pub enum ServerEvent {
    ClientConnected { addr: SocketAddr },
    ClientDisconnected { addr: SocketAddr },
    ClientAuthenticated { addr: SocketAddr, device_id: String },
    SessionCreated { session_id: String },
    SessionClosed { session_id: String },
    Log(String),
}

/// Server configuration
pub struct ServerConfig {
    pub tls_acceptor: Option<TlsAcceptor>,
    pub max_connections: usize,
    pub auth_timeout_secs: u64,
}

/// Rate limiter tracking failed auth attempts per IP
struct RateLimiter {
    attempts: HashMap<IpAddr, (u32, Instant)>,
    max_attempts: u32,
    window: Duration,
}

impl RateLimiter {
    fn new(max_attempts: u32, window: Duration) -> Self {
        Self {
            attempts: HashMap::new(),
            max_attempts,
            window,
        }
    }

    fn is_blocked(&mut self, ip: IpAddr) -> bool {
        if let Some((count, first_attempt)) = self.attempts.get(&ip) {
            if first_attempt.elapsed() > self.window {
                self.attempts.remove(&ip);
                return false;
            }
            *count >= self.max_attempts
        } else {
            false
        }
    }

    fn record_failure(&mut self, ip: IpAddr) {
        let entry = self.attempts.entry(ip).or_insert((0, Instant::now()));
        if entry.1.elapsed() > self.window {
            *entry = (1, Instant::now());
        } else {
            entry.0 += 1;
        }
    }

    fn clear(&mut self, ip: IpAddr) {
        self.attempts.remove(&ip);
    }
}

/// Drop guard that decrements connection count
struct ConnectionGuard {
    counter: Arc<AtomicUsize>,
}

impl Drop for ConnectionGuard {
    fn drop(&mut self) {
        self.counter.fetch_sub(1, Ordering::Relaxed);
    }
}

pub async fn run_server(
    listener: TcpListener,
    session_mgr: Arc<Mutex<SessionManager>>,
    pairing: Arc<Mutex<PairingManager>>,
    event_tx: mpsc::UnboundedSender<ServerEvent>,
    config: ServerConfig,
) -> Result<()> {
    let addr = listener.local_addr()?;
    info!("Server listening on {}", addr);
    let _ = event_tx.send(ServerEvent::Log(format!("Listening on {}", addr)));

    let active_connections = Arc::new(AtomicUsize::new(0));
    let rate_limiter = Arc::new(Mutex::new(RateLimiter::new(5, Duration::from_secs(60))));

    loop {
        let (stream, peer_addr) = listener.accept().await?;

        // Check connection limit
        let current = active_connections.fetch_add(1, Ordering::Relaxed);
        if current >= config.max_connections {
            active_connections.fetch_sub(1, Ordering::Relaxed);
            warn!("Connection limit reached, rejecting {}", peer_addr);
            let _ = event_tx.send(ServerEvent::Log(format!(
                "Rejected {} (connection limit)",
                peer_addr
            )));
            drop(stream);
            continue;
        }

        // Check rate limit
        {
            let mut rl = rate_limiter.lock().await;
            if rl.is_blocked(peer_addr.ip()) {
                active_connections.fetch_sub(1, Ordering::Relaxed);
                warn!("Rate limited, rejecting {}", peer_addr);
                let _ = event_tx.send(ServerEvent::Log(format!(
                    "Rejected {} (rate limited)",
                    peer_addr
                )));
                drop(stream);
                continue;
            }
        }

        let _guard = ConnectionGuard {
            counter: active_connections.clone(),
        };
        let session_mgr = session_mgr.clone();
        let pairing = pairing.clone();
        let event_tx = event_tx.clone();
        let tls_acceptor = config.tls_acceptor.clone();
        let auth_timeout = config.auth_timeout_secs;
        let rate_limiter = rate_limiter.clone();

        tokio::spawn(async move {
            let _guard = _guard; // move guard into task

            let result = if let Some(acceptor) = tls_acceptor {
                match acceptor.accept(stream).await {
                    Ok(tls_stream) => {
                        accept_and_handle(tls_stream, peer_addr, session_mgr, pairing, event_tx, auth_timeout, rate_limiter).await
                    }
                    Err(e) => {
                        error!("TLS handshake failed from {}: {}", peer_addr, e);
                        return;
                    }
                }
            } else {
                accept_and_handle(stream, peer_addr, session_mgr, pairing, event_tx, auth_timeout, rate_limiter).await
            };

            if let Err(e) = result {
                error!("Connection handler error for {}: {}", peer_addr, e);
            }
        });
    }
}

async fn accept_and_handle<S>(
    stream: S,
    peer_addr: SocketAddr,
    session_mgr: Arc<Mutex<SessionManager>>,
    pairing: Arc<Mutex<PairingManager>>,
    event_tx: mpsc::UnboundedSender<ServerEvent>,
    auth_timeout: u64,
    rate_limiter: Arc<Mutex<RateLimiter>>,
) -> Result<()>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    // WebSocket handshake with Origin validation
    let ws = accept_hdr_async(stream, |req: &Request, resp: Response| {
        // Reject requests with suspicious browser Origins
        if let Some(origin) = req.headers().get("origin") {
            if let Ok(origin_str) = origin.to_str() {
                // Allow null origin (non-browser) and file:// (local apps)
                if origin_str != "null" && !origin_str.starts_with("file://") {
                    warn!("Rejected WebSocket from browser origin: {}", origin_str);
                    let resp = Response::builder()
                        .status(tungstenite::http::StatusCode::FORBIDDEN)
                        .body(None)
                        .unwrap();
                    return Err(resp);
                }
            }
        }
        // No Origin header = native app (iOS URLSession, websocat, etc.) — allow
        Ok(resp)
    })
    .await?;

    handle_connection(ws, peer_addr, session_mgr, pairing, event_tx, auth_timeout, rate_limiter).await
}

async fn handle_connection<S>(
    ws: tokio_tungstenite::WebSocketStream<S>,
    peer_addr: SocketAddr,
    session_mgr: Arc<Mutex<SessionManager>>,
    pairing: Arc<Mutex<PairingManager>>,
    event_tx: mpsc::UnboundedSender<ServerEvent>,
    auth_timeout_secs: u64,
    rate_limiter: Arc<Mutex<RateLimiter>>,
) -> Result<()>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let _ = event_tx.send(ServerEvent::ClientConnected { addr: peer_addr });
    info!("Client connected: {}", peer_addr);

    let (mut ws_tx, mut ws_rx) = ws.split();

    // Wait for Auth message with timeout
    let auth_result = tokio::time::timeout(
        Duration::from_secs(auth_timeout_secs),
        async {
            loop {
                match ws_rx.next().await {
                    Some(Ok(Message::Text(text))) => match serde_json::from_str::<ClientMessage>(&text) {
                        Ok(ClientMessage::Auth { token }) => {
                            let auth_result = {
                                let mut pm = pairing.lock().await;
                                pm.validate_token(&token)
                            };
                            match auth_result {
                                AuthResult::Valid => {
                                    let device_id = format!("device-{}", &peer_addr);
                                    let msg = ServerMessage::AuthOk {
                                        device_id: device_id.clone(),
                                    };
                                    ws_tx
                                        .send(Message::Text(serde_json::to_string(&msg)?))
                                        .await?;
                                    let _ = event_tx.send(ServerEvent::ClientAuthenticated {
                                        addr: peer_addr,
                                        device_id,
                                    });
                                    return Ok::<bool, anyhow::Error>(true);
                                }
                                result => {
                                    let reason = match result {
                                        AuthResult::Expired => "token_expired",
                                        AuthResult::Invalid => "token_invalid",
                                        AuthResult::NoToken => "token_consumed",
                                        AuthResult::Valid => unreachable!(),
                                    };
                                    let msg = ServerMessage::AuthFail {
                                        reason: reason.into(),
                                    };
                                    ws_tx
                                        .send(Message::Text(serde_json::to_string(&msg)?))
                                        .await?;
                                    return Ok(false);
                                }
                            }
                        }
                        _ => {
                            let msg = ServerMessage::Error {
                                code: "auth_required".into(),
                                message: "first message must be Auth".into(),
                            };
                            ws_tx
                                .send(Message::Text(serde_json::to_string(&msg)?))
                                .await?;
                            return Ok(false);
                        }
                    },
                    Some(Ok(Message::Ping(data))) => {
                        ws_tx.send(Message::Pong(data)).await?;
                    }
                    _ => return Ok(false),
                }
            }
        },
    )
    .await;

    let authenticated = match auth_result {
        Ok(Ok(true)) => {
            rate_limiter.lock().await.clear(peer_addr.ip());
            true
        }
        Ok(Ok(false)) => {
            rate_limiter.lock().await.record_failure(peer_addr.ip());
            false
        }
        Ok(Err(e)) => {
            warn!("Auth error from {}: {}", peer_addr, e);
            rate_limiter.lock().await.record_failure(peer_addr.ip());
            false
        }
        Err(_) => {
            warn!("Auth timeout for {}", peer_addr);
            false
        }
    };

    if !authenticated {
        info!("Client {} failed authentication", peer_addr);
        let _ = event_tx.send(ServerEvent::ClientDisconnected { addr: peer_addr });
        return Ok(());
    }

    info!("Client {} authenticated", peer_addr);

    // Channel for sending PTY output back to WebSocket
    let (pty_out_tx, mut pty_out_rx) = mpsc::unbounded_channel::<(String, Vec<u8>)>();

    // Main message loop
    loop {
        tokio::select! {
            msg = ws_rx.next() => {
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        match serde_json::from_str::<ClientMessage>(&text) {
                            Ok(client_msg) => {
                                handle_client_message(
                                    client_msg,
                                    &mut ws_tx,
                                    &session_mgr,
                                    &event_tx,
                                    &pty_out_tx,
                                ).await?;
                            }
                            Err(e) => {
                                warn!("Invalid message from {}: {}", peer_addr, e);
                                let msg = ServerMessage::Error {
                                    code: "parse_error".into(),
                                    message: e.to_string(),
                                };
                                ws_tx.send(Message::Text(serde_json::to_string(&msg)?)).await?;
                            }
                        }
                    }
                    Some(Ok(Message::Ping(data))) => {
                        ws_tx.send(Message::Pong(data)).await?;
                    }
                    Some(Ok(Message::Close(_))) | None => {
                        info!("Client {} disconnected", peer_addr);
                        break;
                    }
                    Some(Err(e)) => {
                        warn!("WebSocket error from {}: {}", peer_addr, e);
                        break;
                    }
                    _ => {}
                }
            }

            pty_data = pty_out_rx.recv() => {
                if let Some((session_id, data)) = pty_data {
                    let encoded = BASE64.encode(&data);
                    let msg = ServerMessage::Output {
                        session: session_id,
                        data: encoded,
                    };
                    if ws_tx.send(Message::Text(serde_json::to_string(&msg)?)).await.is_err() {
                        break;
                    }
                }
            }
        }
    }

    let _ = event_tx.send(ServerEvent::ClientDisconnected { addr: peer_addr });
    Ok(())
}

async fn handle_client_message<S>(
    msg: ClientMessage,
    ws_tx: &mut futures_util::stream::SplitSink<tokio_tungstenite::WebSocketStream<S>, Message>,
    session_mgr: &Arc<Mutex<SessionManager>>,
    event_tx: &mpsc::UnboundedSender<ServerEvent>,
    pty_out_tx: &mpsc::UnboundedSender<(String, Vec<u8>)>,
) -> Result<()>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    match msg {
        ClientMessage::Auth { .. } => {
            let msg = ServerMessage::Error {
                code: "already_authenticated".into(),
                message: "already authenticated".into(),
            };
            ws_tx
                .send(Message::Text(serde_json::to_string(&msg)?))
                .await?;
        }

        ClientMessage::SessionCreate => {
            let mut mgr = session_mgr.lock().await;
            match mgr.create_session() {
                Ok((session_id, shell)) => {
                    if let Some(mut output_rx) = mgr.take_output_rx(&session_id) {
                        let tx = pty_out_tx.clone();
                        let sid = session_id.clone();
                        tokio::spawn(async move {
                            while let Some(data) = output_rx.recv().await {
                                if tx.send((sid.clone(), data)).is_err() {
                                    break;
                                }
                            }
                        });
                    }

                    let _ = event_tx.send(ServerEvent::SessionCreated {
                        session_id: session_id.clone(),
                    });

                    let msg = ServerMessage::SessionCreated {
                        session: session_id,
                        shell,
                    };
                    ws_tx
                        .send(Message::Text(serde_json::to_string(&msg)?))
                        .await?;
                }
                Err(e) => {
                    let msg = ServerMessage::Error {
                        code: "session_create_failed".into(),
                        message: e.to_string(),
                    };
                    ws_tx
                        .send(Message::Text(serde_json::to_string(&msg)?))
                        .await?;
                }
            }
        }

        ClientMessage::SessionClose { session } => {
            let mut mgr = session_mgr.lock().await;
            match mgr.close_session(&session) {
                Ok(()) => {
                    let _ = event_tx.send(ServerEvent::SessionClosed {
                        session_id: session.clone(),
                    });
                    let msg = ServerMessage::SessionClosed { session };
                    ws_tx
                        .send(Message::Text(serde_json::to_string(&msg)?))
                        .await?;
                }
                Err(e) => {
                    let msg = ServerMessage::Error {
                        code: "session_close_failed".into(),
                        message: e.to_string(),
                    };
                    ws_tx
                        .send(Message::Text(serde_json::to_string(&msg)?))
                        .await?;
                }
            }
        }

        ClientMessage::SessionList => {
            let mut mgr = session_mgr.lock().await;
            let sessions = mgr.list_sessions();
            let msg = ServerMessage::SessionList { sessions };
            ws_tx
                .send(Message::Text(serde_json::to_string(&msg)?))
                .await?;
        }

        ClientMessage::Input { session, data } => {
            let mgr = session_mgr.lock().await;
            if let Err(e) = mgr.write_to_session(&session, data.as_bytes()) {
                warn!("Failed to write to session {}: {}", session, e);
            }
        }

        ClientMessage::Resize {
            session,
            cols,
            rows,
        } => {
            let mgr = session_mgr.lock().await;
            if let Err(e) = mgr.resize_session(&session, cols, rows) {
                warn!("Failed to resize session {}: {}", session, e);
            }
        }

        ClientMessage::Ping { timestamp } => {
            let msg = ServerMessage::Pong { timestamp };
            ws_tx
                .send(Message::Text(serde_json::to_string(&msg)?))
                .await?;
        }
    }

    Ok(())
}
