use anyhow::Result;
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use bash_mirror_core::session_mgr::SessionManager;
use bash_mirror_proto::{ClientMessage, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::{mpsc, Mutex};
use tokio_tungstenite::accept_async;
use tracing::{error, info, warn};
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

pub async fn run_server(
    addr: SocketAddr,
    session_mgr: Arc<Mutex<SessionManager>>,
    auth_token: Arc<Mutex<Option<String>>>,
    event_tx: mpsc::UnboundedSender<ServerEvent>,
) -> Result<()> {
    let listener = TcpListener::bind(addr).await?;
    info!("Server listening on {}", addr);
    let _ = event_tx.send(ServerEvent::Log(format!("Listening on {}", addr)));

    loop {
        let (stream, peer_addr) = listener.accept().await?;
        let session_mgr = session_mgr.clone();
        let auth_token = auth_token.clone();
        let event_tx = event_tx.clone();

        tokio::spawn(async move {
            match accept_async(stream).await {
                Ok(ws) => {
                    if let Err(e) =
                        handle_connection(ws, peer_addr, session_mgr, auth_token, event_tx).await
                    {
                        error!("Connection handler error for {}: {}", peer_addr, e);
                    }
                }
                Err(e) => {
                    error!("WebSocket handshake failed from {}: {}", peer_addr, e);
                }
            }
        });
    }
}

async fn handle_connection<S>(
    ws: tokio_tungstenite::WebSocketStream<S>,
    peer_addr: SocketAddr,
    session_mgr: Arc<Mutex<SessionManager>>,
    auth_token: Arc<Mutex<Option<String>>>,
    event_tx: mpsc::UnboundedSender<ServerEvent>,
) -> Result<()>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let _ = event_tx.send(ServerEvent::ClientConnected { addr: peer_addr });
    info!("Client connected: {}", peer_addr);

    let (mut ws_tx, mut ws_rx) = ws.split();

    // Wait for Auth message first
    let authenticated = loop {
        match ws_rx.next().await {
            Some(Ok(Message::Text(text))) => match serde_json::from_str::<ClientMessage>(&text) {
                Ok(ClientMessage::Auth { token }) => {
                    let valid = {
                        let tok = auth_token.lock().await;
                        tok.as_ref().map(|t| t == &token).unwrap_or(false)
                    };
                    if valid {
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
                        break true;
                    } else {
                        let msg = ServerMessage::AuthFail {
                            reason: "invalid or expired token".into(),
                        };
                        ws_tx
                            .send(Message::Text(serde_json::to_string(&msg)?))
                            .await?;
                        break false;
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
                    break false;
                }
            },
            Some(Ok(Message::Ping(data))) => {
                ws_tx.send(Message::Pong(data)).await?;
            }
            _ => break false,
        }
    };

    if !authenticated {
        info!("Client {} failed authentication", peer_addr);
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
