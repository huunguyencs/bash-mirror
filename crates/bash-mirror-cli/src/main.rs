mod dashboard;
mod server;
mod web_dashboard;

use anyhow::Result;
use bash_mirror_core::auth::PairingManager;
use bash_mirror_core::session_mgr::SessionManager;
use bash_mirror_core::tls::generate_tls;
use clap::Parser;
use dashboard::{DashboardAction, DashboardState};
use server::{ServerConfig, ServerEvent};
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

    /// Disable TLS (not recommended, use for development only)
    #[arg(long)]
    no_tls: bool,

    /// Token expiry time in seconds
    #[arg(long, default_value = "300")]
    token_ttl: u64,

    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,

    /// IP address to bind to (default: LAN IP, use 0.0.0.0 for all interfaces)
    #[arg(long)]
    bind: Option<IpAddr>,

    /// Maximum concurrent connections
    #[arg(long, default_value = "8")]
    max_connections: usize,

    /// Auth timeout in seconds
    #[arg(long, default_value = "10")]
    auth_timeout: u64,

    /// Maximum concurrent PTY sessions
    #[arg(long, default_value = "4")]
    max_sessions: usize,

    /// Disable auto-opening dashboard in browser
    #[arg(long)]
    no_open: bool,

    /// Dashboard web UI port (0 = random)
    #[arg(long, default_value = "0")]
    dashboard_port: u16,
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
    let lan_ip = local_ip_address::local_ip().unwrap_or(IpAddr::V4(Ipv4Addr::LOCALHOST));

    // Bind address: use --bind if provided, otherwise bind to LAN IP
    let bind_ip = cli.bind.unwrap_or(lan_ip);

    // Generate TLS certificate (unless --no-tls)
    let tls_info = if cli.no_tls {
        None
    } else {
        match generate_tls(&lan_ip.to_string()) {
            Ok(info) => Some(info),
            Err(e) => {
                eprintln!("Warning: TLS generation failed ({}), falling back to plain WS", e);
                None
            }
        }
    };

    let tls_enabled = tls_info.is_some();
    let cert_fingerprint = tls_info
        .as_ref()
        .map(|t| t.fingerprint.clone())
        .unwrap_or_default();
    let tls_acceptor = tls_info.map(|t| t.acceptor);

    // Bind listener (pass directly to server to avoid TOCTOU race)
    let bind_addr = SocketAddr::new(bind_ip, cli.port);
    let listener = tokio::net::TcpListener::bind(bind_addr).await?;
    let actual_addr = listener.local_addr()?;
    let port = actual_addr.port();

    // Generate auth token
    let pairing = Arc::new(Mutex::new(PairingManager::new(Duration::from_secs(cli.token_ttl))));
    let (token, short_code) = {
        let mut pm = pairing.lock().await;
        let info = pm.generate_token();
        (info.token.to_string(), info.short_code.clone())
    };

    let ws_scheme = if tls_enabled { "wss" } else { "ws" };
    info!("bash-mirror starting on {}://{}:{}", ws_scheme, lan_ip, port);

    // Shared state
    let session_mgr = Arc::new(Mutex::new(SessionManager::new(cli.shell.clone(), cli.max_sessions)));

    // Event channels
    let (event_tx, event_rx) = mpsc::unbounded_channel::<ServerEvent>();

    // Broadcast channel for log events (web dashboard SSE)
    let (log_tx, _log_rx) = tokio::sync::broadcast::channel::<String>(256);
    let (action_tx, mut action_rx) = mpsc::unbounded_channel::<DashboardAction>();

    // Server config
    let server_config = ServerConfig {
        tls_acceptor,
        max_connections: cli.max_connections,
        auth_timeout_secs: cli.auth_timeout,
        log_broadcast: Some(log_tx.clone()),
    };

    // Start WebSocket server
    let server_session_mgr = session_mgr.clone();
    let server_pairing = pairing.clone();
    let server_event_tx = event_tx.clone();

    let server_handle = tokio::spawn(async move {
        if let Err(e) = server::run_server(
            listener,
            server_session_mgr,
            server_pairing,
            server_event_tx,
            server_config,
        )
        .await
        {
            eprintln!("Server error: {}", e);
        }
    });

    // Start web dashboard
    let dashboard_state = web_dashboard::DashboardState {
        pairing: pairing.clone(),
        sessions: session_mgr.clone(),
        log_tx: log_tx.clone(),
        server_url: format!("{}://{}:{}", ws_scheme, lan_ip, port),
        lan_ip,
        port,
        cert_fingerprint: cert_fingerprint.clone(),
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

    if cli.no_tui {
        // Simple mode: print connection info and wait
        println!("\n  bash-mirror v0.1.0");
        println!("  ==================\n");
        println!("  URL:   {}://{}:{}", ws_scheme, lan_ip, port);
        println!("  Token: {}", token);
        println!("  Code:  {}", short_code);
        if tls_enabled {
            println!("  TLS:   enabled (fingerprint: {}...)", &cert_fingerprint[..20]);
        } else {
            println!("  TLS:   disabled (use --no-tls only for development)");
        }
        println!("  Dashboard: {}", dashboard_url);
        println!();

        // Print QR code
        let qr_payload = PairingManager::qr_payload(lan_ip, port, &token, &cert_fingerprint);
        if let Err(e) = qr2term::print_qr(&qr_payload) {
            eprintln!("Failed to generate QR code: {}", e);
        }

        println!("\n  Waiting for connections... (Ctrl+C to quit)");
        println!("  Send SIGUSR1 to rotate token: kill -USR1 {}\n", std::process::id());

        // SIGUSR1 handler for token rotation
        let signal_pairing = pairing.clone();
        tokio::spawn(async move {
            let mut sig = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::user_defined1())
                .expect("failed to register SIGUSR1 handler");
            loop {
                sig.recv().await;
                let mut pm = signal_pairing.lock().await;
                let new_token = pm.generate_token();
                println!("\n  Token rotated!");
                println!("  New Token: {}", &*new_token.token);
                println!("  New Code:  {}", new_token.short_code);
                println!("  Expires in {}s\n", new_token.ttl.as_secs());
            }
        });

        // Wait for Ctrl+C
        tokio::signal::ctrl_c().await?;
    } else {
        // TUI dashboard mode
        let mut dashboard_state = DashboardState::new(lan_ip, port);
        dashboard_state.token = Some(token.clone());
        dashboard_state.token_remaining_secs = cli.token_ttl;
        dashboard_state.push_log(format!("Server started on {}://{}:{}", ws_scheme, lan_ip, port));
        dashboard_state.push_log(format!("Token: {}... (code: {})", &token[..8], short_code));
        if tls_enabled {
            dashboard_state.push_log("TLS enabled".into());
        }

        // Handle dashboard actions in background
        let action_pairing = pairing.clone();
        let action_event_tx = event_tx.clone();
        tokio::spawn(async move {
            while let Some(action) = action_rx.recv().await {
                match action {
                    DashboardAction::Quit => break,
                    DashboardAction::RegenerateToken => {
                        let mut pm = action_pairing.lock().await;
                        let new_token = pm.generate_token();
                        let tok_display = new_token.token[..8].to_string();
                        let _ = action_event_tx.send(ServerEvent::Log(format!(
                            "Token regenerated: {}...",
                            tok_display
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
