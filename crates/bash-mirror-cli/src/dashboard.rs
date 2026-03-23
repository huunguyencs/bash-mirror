use crate::server::ServerEvent;
use crossterm::{
    event::{self, Event, KeyCode, KeyEvent, KeyModifiers},
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
    ExecutableCommand,
};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame, Terminal,
};
use std::io::stdout;
use std::net::IpAddr;
use std::time::Duration;
use tokio::sync::mpsc;

pub struct DashboardState {
    pub ip: IpAddr,
    pub port: u16,
    pub token: Option<String>,
    pub token_remaining_secs: u64,
    pub connected_clients: Vec<ConnectedClient>,
    pub active_sessions: Vec<SessionDisplay>,
    pub logs: Vec<String>,
    pub quit: bool,
    pub regenerate_token: bool,
}

#[derive(Clone)]
pub struct ConnectedClient {
    pub addr: String,
    pub device_id: String,
    pub sessions: usize,
}

#[derive(Clone)]
pub struct SessionDisplay {
    pub id: String,
    pub shell: String,
    pub alive: bool,
}

impl DashboardState {
    pub fn new(ip: IpAddr, port: u16) -> Self {
        Self {
            ip,
            port,
            token: None,
            token_remaining_secs: 0,
            connected_clients: Vec::new(),
            active_sessions: Vec::new(),
            logs: Vec::new(),
            quit: false,
            regenerate_token: false,
        }
    }

    pub fn push_log(&mut self, msg: String) {
        let timestamp = chrono_lite_now();
        self.logs.push(format!("{} {}", timestamp, msg));
        if self.logs.len() > 100 {
            self.logs.remove(0);
        }
    }

    pub fn apply_event(&mut self, event: ServerEvent) {
        match event {
            ServerEvent::ClientConnected { addr } => {
                self.push_log(format!("Client connected from {}", addr));
            }
            ServerEvent::ClientDisconnected { addr } => {
                self.connected_clients.retain(|c| c.addr != addr.to_string());
                self.push_log(format!("Client disconnected: {}", addr));
            }
            ServerEvent::ClientAuthenticated { addr, device_id } => {
                self.connected_clients.push(ConnectedClient {
                    addr: addr.to_string(),
                    device_id: device_id.clone(),
                    sessions: 0,
                });
                self.push_log(format!("Authenticated: {} ({})", device_id, addr));
            }
            ServerEvent::SessionCreated { session_id } => {
                self.active_sessions.push(SessionDisplay {
                    id: session_id.clone(),
                    shell: "shell".into(),
                    alive: true,
                });
                self.push_log(format!("Session created: {}", session_id));
            }
            ServerEvent::SessionClosed { session_id } => {
                self.active_sessions.retain(|s| s.id != session_id);
                self.push_log(format!("Session closed: {}", session_id));
            }
            ServerEvent::Log(msg) => {
                self.push_log(msg);
            }
        }
    }
}

fn chrono_lite_now() -> String {
    // Simple timestamp without pulling in chrono
    let duration = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let secs = duration.as_secs() % 86400;
    let hours = secs / 3600;
    let mins = (secs % 3600) / 60;
    let s = secs % 60;
    format!("{:02}:{:02}:{:02}", hours, mins, s)
}

pub async fn run_dashboard(
    mut state: DashboardState,
    mut event_rx: mpsc::UnboundedReceiver<ServerEvent>,
    action_tx: mpsc::UnboundedSender<DashboardAction>,
) -> anyhow::Result<()> {
    stdout().execute(EnterAlternateScreen)?;
    enable_raw_mode()?;

    let backend = ratatui::backend::CrosstermBackend::new(stdout());
    let mut terminal = Terminal::new(backend)?;
    terminal.clear()?;

    loop {
        if state.quit {
            break;
        }

        // Drain server events
        while let Ok(ev) = event_rx.try_recv() {
            state.apply_event(ev);
        }

        terminal.draw(|f| render_dashboard(f, &state))?;

        // Poll for keyboard input with timeout
        if event::poll(Duration::from_millis(100))? {
            if let Event::Key(KeyEvent {
                code, modifiers, ..
            }) = event::read()?
            {
                match (code, modifiers) {
                    (KeyCode::Char('q'), _) | (KeyCode::Char('c'), KeyModifiers::CONTROL) => {
                        state.quit = true;
                        let _ = action_tx.send(DashboardAction::Quit);
                    }
                    (KeyCode::Char('r'), _) => {
                        state.regenerate_token = true;
                        let _ = action_tx.send(DashboardAction::RegenerateToken);
                    }
                    (KeyCode::Char('d'), _) => {
                        let _ = action_tx.send(DashboardAction::DisconnectAll);
                    }
                    _ => {}
                }
            }
        }
    }

    disable_raw_mode()?;
    stdout().execute(LeaveAlternateScreen)?;
    Ok(())
}

#[derive(Debug)]
pub enum DashboardAction {
    Quit,
    RegenerateToken,
    DisconnectAll,
}

fn render_dashboard(f: &mut Frame, state: &DashboardState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints([
            Constraint::Length(7),  // connection info
            Constraint::Length(5),  // connected devices
            Constraint::Length(5),  // active sessions
            Constraint::Min(5),    // logs
            Constraint::Length(1), // footer
        ])
        .split(f.area());

    // Connection Info
    render_connection_info(f, chunks[0], state);

    // Connected Devices
    render_connected_devices(f, chunks[1], state);

    // Active Sessions
    render_active_sessions(f, chunks[2], state);

    // Logs
    render_logs(f, chunks[3], state);

    // Footer
    render_footer(f, chunks[4]);
}

fn render_connection_info(f: &mut Frame, area: Rect, state: &DashboardState) {
    let block = Block::default()
        .title(" bash-mirror v0.1.0 — Connection Info ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan));

    let token_display = match &state.token {
        Some(t) => {
            let short = &t[..6.min(t.len())];
            format!(
                "Token: {}... (expires: {}s)",
                short, state.token_remaining_secs
            )
        }
        None => "Token: generating...".into(),
    };

    let text = vec![
        Line::from(vec![
            Span::styled("  IP: ", Style::default().fg(Color::Gray)),
            Span::styled(state.ip.to_string(), Style::default().fg(Color::White)),
            Span::raw("    "),
            Span::styled("Port: ", Style::default().fg(Color::Gray)),
            Span::styled(
                state.port.to_string(),
                Style::default().fg(Color::White),
            ),
        ]),
        Line::from(vec![
            Span::styled("  ", Style::default()),
            Span::styled(token_display, Style::default().fg(Color::Yellow)),
        ]),
        Line::from(vec![
            Span::styled("  URL: ", Style::default().fg(Color::Gray)),
            Span::styled(
                format!("ws://{}:{}", state.ip, state.port),
                Style::default().fg(Color::Green),
            ),
        ]),
    ];

    let paragraph = Paragraph::new(text).block(block);
    f.render_widget(paragraph, area);
}

fn render_connected_devices(f: &mut Frame, area: Rect, state: &DashboardState) {
    let block = Block::default()
        .title(" Connected Devices ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Blue));

    let items: Vec<ListItem> = if state.connected_clients.is_empty() {
        vec![ListItem::new(Span::styled(
            "  No devices connected",
            Style::default().fg(Color::DarkGray),
        ))]
    } else {
        state
            .connected_clients
            .iter()
            .map(|c| {
                ListItem::new(Line::from(vec![
                    Span::styled("  ", Style::default()),
                    Span::styled(&c.device_id, Style::default().fg(Color::White)),
                    Span::styled(
                        format!("  ({}) ", c.addr),
                        Style::default().fg(Color::DarkGray),
                    ),
                ]))
            })
            .collect()
    };

    let list = List::new(items).block(block);
    f.render_widget(list, area);
}

fn render_active_sessions(f: &mut Frame, area: Rect, state: &DashboardState) {
    let block = Block::default()
        .title(" Active Sessions ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Magenta));

    let items: Vec<ListItem> = if state.active_sessions.is_empty() {
        vec![ListItem::new(Span::styled(
            "  No active sessions",
            Style::default().fg(Color::DarkGray),
        ))]
    } else {
        state
            .active_sessions
            .iter()
            .map(|s| {
                let status_color = if s.alive { Color::Green } else { Color::Red };
                let status_text = if s.alive { "Running" } else { "Exited" };
                ListItem::new(Line::from(vec![
                    Span::styled(
                        format!("  [{}] ", s.id),
                        Style::default().fg(Color::Yellow),
                    ),
                    Span::styled(&s.shell, Style::default().fg(Color::White)),
                    Span::styled("  ", Style::default()),
                    Span::styled(status_text, Style::default().fg(status_color)),
                ]))
            })
            .collect()
    };

    let list = List::new(items).block(block);
    f.render_widget(list, area);
}

fn render_logs(f: &mut Frame, area: Rect, state: &DashboardState) {
    let block = Block::default()
        .title(" Log ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray));

    let visible_count = (area.height as usize).saturating_sub(2);
    let start = state.logs.len().saturating_sub(visible_count);
    let items: Vec<ListItem> = state.logs[start..]
        .iter()
        .map(|log| {
            ListItem::new(Span::styled(
                format!("  {}", log),
                Style::default().fg(Color::Gray),
            ))
        })
        .collect();

    let list = List::new(items).block(block);
    f.render_widget(list, area);
}

fn render_footer(f: &mut Frame, area: Rect) {
    let footer = Paragraph::new(Line::from(vec![
        Span::styled(" [q] ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
        Span::styled("Quit  ", Style::default().fg(Color::Gray)),
        Span::styled("[r] ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
        Span::styled("Regenerate token  ", Style::default().fg(Color::Gray)),
        Span::styled("[d] ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
        Span::styled("Disconnect all", Style::default().fg(Color::Gray)),
    ]));
    f.render_widget(footer, area);
}
