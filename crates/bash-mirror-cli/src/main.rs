mod dashboard;
mod server;

use anyhow::Result;
use bash_mirror_core::auth::PairingManager;
use bash_mirror_core::session_mgr::SessionManager;
use clap::Parser;
use dashboard::{DashboardAction, DashboardState};
use server::ServerEvent;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, Mutex};
use tracing::info;

#[derive(Parser)]
#[command(name = "bash-mirror", version, about = "Control your terminal from your phone")]
struct Cli {
    /// Port to listen on (0 = random)
    #[arg(short, long, default_value = "0")]
    port: u16,

    /// Shell to use
    #[arg(short, long, env = "SHELL", default_value = "/bin/zsh")]
    shell: String,

    /// Allow multiple device connections
    #[arg(long)]
    multi: bool,

    /// Disable TUI dashboard
    #[arg(long)]
    no_tui: bool,

    /// Token expiry time in seconds
    #[arg(long, default_value = "300")]
    token_ttl: u64,

    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    if cli.no_tui {
        // Set up logging only in non-TUI mode (TUI handles its own display)
        tracing_subscriber::fmt()
            .with_max_level(if cli.verbose {
                tracing::Level::DEBUG
            } else {
                tracing::Level::INFO
            })
            .init();
    }

    // Detect LAN IP
    let ip = local_ip_address::local_ip().unwrap_or(IpAddr::V4(Ipv4Addr::LOCALHOST));

    // Bind to get the actual port (important when port=0)
    let bind_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), cli.port);
    let listener = tokio::net::TcpListener::bind(bind_addr).await?;
    let actual_addr = listener.local_addr()?;
    let port = actual_addr.port();
    drop(listener); // We'll re-bind in the server

    // Generate auth token
    let mut pairing = PairingManager::new(Duration::from_secs(cli.token_ttl));
    let token_info = pairing.generate_token();
    let token = token_info.token.clone();
    let short_code = token_info.short_code.clone();

    info!("bash-mirror starting on {}:{}", ip, port);

    // Shared state
    let session_mgr = Arc::new(Mutex::new(SessionManager::new(cli.shell.clone())));
    let auth_token: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(Some(token.clone())));

    // Event channels
    let (event_tx, event_rx) = mpsc::unbounded_channel::<ServerEvent>();
    let (action_tx, mut action_rx) = mpsc::unbounded_channel::<DashboardAction>();

    // Start WebSocket server
    let server_session_mgr = session_mgr.clone();
    let server_auth_token = auth_token.clone();
    let server_event_tx = event_tx.clone();
    let server_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), port);

    let server_handle = tokio::spawn(async move {
        if let Err(e) = server::run_server(
            server_addr,
            server_session_mgr,
            server_auth_token,
            server_event_tx,
        )
        .await
        {
            eprintln!("Server error: {}", e);
        }
    });

    if cli.no_tui {
        // Simple mode: print connection info and wait
        println!("\n  bash-mirror v0.1.0");
        println!("  ==================\n");
        println!("  URL:   ws://{}:{}", ip, port);
        println!("  Token: {}", token);
        println!("  Code:  {}\n", short_code);

        // Print QR code
        let qr_payload = format!("bashmirror://{}:{}?token={}", ip, port, token);
        if let Err(e) = qr2term::print_qr(&qr_payload) {
            eprintln!("Failed to generate QR code: {}", e);
        }

        println!("\n  Waiting for connections... (Ctrl+C to quit)\n");

        // Wait for Ctrl+C
        tokio::signal::ctrl_c().await?;
    } else {
        // TUI dashboard mode
        let mut dashboard_state = DashboardState::new(ip, port);
        dashboard_state.token = Some(token.clone());
        dashboard_state.token_remaining_secs = cli.token_ttl;
        dashboard_state.push_log(format!("Server started on ws://{}:{}", ip, port));
        dashboard_state.push_log(format!("Token: {} (code: {})", &token[..8], short_code));

        // Handle dashboard actions in background
        let action_auth_token = auth_token.clone();
        let action_event_tx = event_tx.clone();
        tokio::spawn(async move {
            let mut pairing = PairingManager::new(Duration::from_secs(cli.token_ttl));
            while let Some(action) = action_rx.recv().await {
                match action {
                    DashboardAction::Quit => break,
                    DashboardAction::RegenerateToken => {
                        let new_token = pairing.generate_token();
                        let tok = new_token.token.clone();
                        *action_auth_token.lock().await = Some(tok.clone());
                        let _ = action_event_tx.send(ServerEvent::Log(format!(
                            "Token regenerated: {}...",
                            &tok[..8]
                        )));
                    }
                    DashboardAction::DisconnectAll => {
                        let _ = action_event_tx
                            .send(ServerEvent::Log("Disconnect all requested".into()));
                    }
                }
            }
        });

        // Run the TUI (blocks until quit)
        dashboard::run_dashboard(dashboard_state, event_rx, action_tx).await?;
    }

    server_handle.abort();
    Ok(())
}
