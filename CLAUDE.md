# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is bash-mirror?

A remote terminal tool that lets you control a macOS/Linux shell from an iOS device over LAN. A Rust CLI runs a WebSocket server with PTY sessions; a SwiftUI iOS app connects, authenticates via QR code/token, and renders the terminal using xterm.js in a WKWebView.

## Build & Run

```bash
# Build all Rust crates
cargo build

# Run the CLI server (TUI dashboard by default)
cargo run -p bash-mirror-cli

# Run without TUI (plain stdout)
cargo run -p bash-mirror-cli -- --no-tui

# Run with options
cargo run -p bash-mirror-cli -- --port 8080 --shell /bin/bash --verbose

# Check / lint
cargo check
cargo clippy --workspace
```

The iOS app uses XcodeGen (`project.yml` at `ios/BashMirror/`). Regenerate the Xcode project with `xcodegen generate` from that directory, then build in Xcode. Deployment target is iOS 26.0.

## Architecture

### Rust workspace (`crates/`)

Three crates in a Cargo workspace:

- **bash-mirror-proto** — Shared JSON protocol types. `ClientMessage` and `ServerMessage` enums use `#[serde(tag = "type")]` for tagged JSON serialization. This crate has no async runtime dependency.
- **bash-mirror-core** — Server-side logic: PTY session management (`PtySession` spawns via `portable-pty`, with dedicated reader/writer threads bridged to tokio channels), `SessionManager` (HashMap of sessions keyed by short UUID), `PairingManager` (one-time token auth with SHA-256-derived 6-digit short codes), and self-signed TLS generation (`rcgen` + `rustls`).
- **bash-mirror-cli** — Binary crate (`bash-mirror`). Runs a tokio-tungstenite WebSocket server. Has a ratatui TUI dashboard showing connection info, devices, sessions, and logs. Server events flow via `mpsc::UnboundedChannel<ServerEvent>` from the WS handler to the dashboard.

### iOS app (`ios/BashMirror/`)

SwiftUI app with:
- `ScannerView` — QR code scanner for pairing
- `ManualConnectView` — manual IP/token entry
- `TerminalView` / `TerminalContainerView` — xterm.js terminal rendered in WKWebView
- `WebSocketService` — handles WS connection and protocol message serialization
- `ConnectionManager` — orchestrates connection lifecycle
- Custom keyboard views (`CommandPadView`, `FullKeyboardView`)

Terminal resources (xterm.js, xterm.css, xterm-addon-fit.js, terminal.html) are bundled as app resources.

## Protocol

All messages are JSON with a `"type"` discriminator field. Connection flow:
1. Client sends `Auth { token }` → server replies `AuthOk` or `AuthFail`
2. Client sends `SessionCreate` → server replies `SessionCreated { session, shell }`
3. Client sends `Input { session, data }` → server streams `Output { session, data }` (base64-encoded PTY output)
4. Client can `Resize`, `Ping`, `SessionList`, `SessionClose`

## Key Patterns

- PTY I/O uses blocking OS threads (`std::thread`) for read/write, bridged to async via `mpsc::UnboundedChannel`. This is necessary because `portable-pty` uses synchronous `Read`/`Write` traits.
- Auth tokens are one-time use — `validate_token` consumes the token on success.
- The QR payload format is `bashmirror://{ip}:{port}?token={token}&fp={cert_fingerprint}`.
- TLS is prepared in core (`tls.rs`) but not yet wired into the WS server — currently plain WebSocket.
