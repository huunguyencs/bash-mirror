# bash-mirror — Technical Documentation

Detailed technical reference for the bash-mirror remote terminal system. For a quick overview, see [README.md](../README.md).

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Rust Workspace](#rust-workspace)
  - [bash-mirror-proto](#bash-mirror-proto)
  - [bash-mirror-core](#bash-mirror-core)
  - [bash-mirror-cli](#bash-mirror-cli)
- [iOS App](#ios-app)
- [Protocol Reference](#protocol-reference)
- [Authentication & Pairing](#authentication--pairing)
- [TLS & Certificate Pinning](#tls--certificate-pinning)
- [PTY Session Management](#pty-session-management)
- [Web Dashboard](#web-dashboard)
- [CLI Reference](#cli-reference)
- [Build & Development](#build--development)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  iOS Device                                                     │
│  ┌───────────────────────────────────────────────┐              │
│  │  SwiftUI App                                  │              │
│  │  ┌──────────────┐  ┌────────────────────────┐ │              │
│  │  │ ScannerView  │  │ TerminalContainerView  │ │              │
│  │  │ (QR/manual)  │  │  ┌──────────────────┐  │ │              │
│  │  └──────┬───────┘  │  │ WKWebView        │  │ │              │
│  │         │          │  │  xterm.js         │  │ │              │
│  │         ▼          │  │  FitAddon         │  │ │              │
│  │  ConnectionManager │  └────────┬─────────┘  │ │              │
│  │         │          │           │ JS Bridge   │ │              │
│  │         ▼          │           ▼             │ │              │
│  │  WebSocketService ◄────────────┘             │ │              │
│  └─────────┬─────────────────────────────────────┘              │
│            │  WSS (TLS + cert pinning)                          │
└────────────┼────────────────────────────────────────────────────┘
             │  LAN (Wi-Fi)
┌────────────┼────────────────────────────────────────────────────┐
│  Mac/Linux │                                                    │
│  ┌─────────▼──────────────────────────────────────────────────┐ │
│  │  bash-mirror-cli                                           │ │
│  │  ┌──────────────────┐  ┌────────────────────────────────┐  │ │
│  │  │ tokio-tungstenite│  │ ratatui TUI Dashboard          │  │ │
│  │  │ WebSocket Server │  │ (connection info, sessions,    │  │ │
│  │  └────────┬─────────┘  │  devices, logs)                │  │ │
│  │           │            └────────────────────────────────┘  │ │
│  │  ┌────────▼─────────────────────────────────────────────┐  │ │
│  │  │ bash-mirror-core                                     │  │ │
│  │  │  PairingManager ── SessionManager ── PtySession(s)   │  │ │
│  │  │  (one-time auth)   (HashMap<id>)    (OS threads)     │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                        ▲                                        │
│                        │ fork/exec                               │
│                   ┌────┴────┐                                   │
│                   │ /bin/zsh│  (or /bin/bash, etc.)              │
│                   └─────────┘                                   │
└─────────────────────────────────────────────────────────────────┘
```

**Data flow**: User types on iOS keyboard → JS bridge → WebSocketService → WSS → server → PTY stdin. PTY stdout → server → WSS → WebSocketService → JS bridge → xterm.js renders output.

---

## Rust Workspace

Three crates in a Cargo workspace (`crates/`):

### bash-mirror-proto

**Purpose**: Shared JSON protocol types. Zero async dependencies.

**Dependencies**: `serde`, `serde_json`

Defines two tagged enums using `#[serde(tag = "type")]`:

- `ClientMessage` — messages the iOS app sends to the server
- `ServerMessage` — messages the server sends to the iOS app

This crate is imported by both `bash-mirror-core` and `bash-mirror-cli`, and its types mirror the Swift `ProtocolMessages.swift` on the iOS side.

### bash-mirror-core

**Purpose**: Server-side logic — PTY management, authentication, TLS, session lifecycle.

| Dependency | Version | Purpose |
|---|---|---|
| portable-pty | 0.8 | Cross-platform PTY spawning |
| tokio | 1 (full) | Async runtime, channels |
| rcgen | 0.13 | Self-signed X.509 cert generation |
| rustls | 0.23 | TLS implementation |
| tokio-rustls | 0.26 | Async TLS acceptor |
| rand | 0.8 | Secure token generation |
| uuid | 1 (v4) | Session ID generation |
| sha2 | 0.10 | Token → short code derivation |
| subtle | 2 | Constant-time token comparison |
| zeroize | 1 (derive) | Secure memory clearing for tokens |
| local-ip-address | 0.6 | LAN IP auto-detection |
| qr2term | 0.3 | Terminal QR code display |
| base64 | 0.22 | PTY output encoding |
| libc | 0.2 | EIO detection on macOS |

**Modules**:

- `auth.rs` — `PairingManager`: token generation, validation, QR payload formatting
- `tls.rs` — Self-signed TLS cert generation with fingerprint
- `session_mgr.rs` — `SessionManager`: create/close/list PTY sessions
- `pty_session.rs` — `PtySession`: spawn shell, reader/writer threads, resize

### bash-mirror-cli

**Purpose**: Binary crate. WebSocket server, TUI dashboard, web dashboard.

| Dependency | Version | Purpose |
|---|---|---|
| tokio-tungstenite | 0.24 | WebSocket server |
| clap | 4 (derive) | CLI argument parsing |
| ratatui | 0.29 | TUI dashboard rendering |
| crossterm | 0.28 | Terminal control for TUI |
| axum | 0.8 | Web dashboard HTTP server |
| tower-http | 0.6 (cors) | CORS for web dashboard |
| qrcode | 0.14 | SVG QR code generation |
| open | 5 | Auto-open browser for dashboard |
| async-stream | 0.3 | SSE log streaming |

**Modules**:

- `main.rs` — Entry point, CLI parsing, server startup orchestration
- `server.rs` — WebSocket connection handler, message routing, auth enforcement
- `dashboard.rs` — ratatui TUI (connection info, devices, sessions, logs)
- `web_dashboard.rs` — axum HTTP server (REST API + SSE logs + QR SVG endpoint)

---

## iOS App

**Platform**: iOS 26.0+ | **Language**: Swift 5.9 | **UI**: SwiftUI | **Build**: XcodeGen

### Source Structure

```
ios/BashMirror/BashMirror/
├── BashMirrorApp.swift           # App entry point
├── Views/
│   ├── ScannerView.swift         # AVFoundation QR scanner
│   ├── ManualConnectView.swift   # Manual IP/token entry form
│   ├── TerminalView.swift        # WKWebView hosting xterm.js
│   ├── TerminalContainerView.swift
│   ├── Keyboard/
│   │   ├── CommandPadView.swift  # Quick-access command buttons
│   │   └── FullKeyboardView.swift # Full keyboard with special keys
│   └── Theme.swift               # Colors, fonts, spacing constants
├── Services/
│   ├── ConnectionManager.swift   # Connection lifecycle orchestration
│   └── WebSocketService.swift    # URLSessionWebSocketTask + cert pinning
├── Models/
│   └── ProtocolMessages.swift    # ClientMessage / ServerMessage (Codable)
└── Resources/
    ├── terminal.html             # xterm.js host page
    ├── xterm.js                  # Terminal emulator library
    ├── xterm.css                 # Terminal styles
    └── xterm-addon-fit.js        # Auto-fit addon
```

### Key Components

**ConnectionManager** (`@ObservableObject`)

Central state machine for the connection lifecycle:

| State | Description |
|---|---|
| `.disconnected` | No active connection |
| `.connecting` | WebSocket handshake + auth in progress |
| `.connected` | Authenticated, sessions can be created |

Published properties: `state`, `sessions: [String]`, `activeSessionId`, `authError`

Methods:
- `connectFromQR(_:)` — Parses `bashmirror://` URL, extracts host/port/token/fingerprint
- `connect(host:port:token:fingerprint:)` — Opens WSS connection, sends Auth
- `createSession()` / `closeSession(_:)` — PTY session lifecycle
- `sendInput(session:data:)` / `sendResize(session:cols:rows:)` — Terminal I/O
- `registerTerminalOutput(session:handler:)` — Binds output callback per session

**WebSocketService** (`URLSessionWebSocketDelegate`)

Handles WebSocket transport and TLS certificate pinning:

- `connect(url:token:fingerprint:)` — Creates URLSessionWebSocketTask, immediately sends Auth
- Certificate pinning via `urlSession(_:didReceive:completionHandler:)` — computes SHA-256 fingerprint of server cert, compares against expected fingerprint from QR payload
- Receive loop decodes JSON into `ServerMessage` enum

**TerminalView** (WKWebView + JavaScript Bridge)

Loads `terminal.html` containing xterm.js (v5, Dracula theme, 5000-line scrollback). Communication between Swift and JavaScript uses `webkit.messageHandlers`:

| Handler | Direction | Purpose |
|---|---|---|
| `terminalInput` | JS → Swift | User keystrokes |
| `terminalResize` | JS → Swift | Terminal dimensions `{cols, rows}` |
| `terminalReady` | JS → Swift | JS initialization complete signal |

Swift calls into JS via `evaluateJavaScript`:
- `termWrite(base64)` — Decode and write PTY output
- `fitTerminal()` — Refit on rotation/resize
- `clearTerminal()` — ANSI clear

**Keyboard Views**

- `FullKeyboardView` — QWERTY layout with special keys (Tab, Ctrl, Esc, arrows), number toggle, shift, and symbol row (`~ \` | / - = [ ]`)
- `CommandPadView` — Quick-access buttons for common commands

### URL Scheme

The app registers the `bashmirror://` URL scheme (in Info.plist). QR codes encode connection info in this format, allowing the scanner to trigger connection automatically.

---

## Protocol Reference

All messages are JSON objects with a `"type"` discriminator field. Data payloads (terminal I/O) are base64-encoded for binary safety.

### Client → Server

| Type | Fields | Description |
|---|---|---|
| `Auth` | `token: String` | Authenticate with one-time token (must be first message) |
| `SessionCreate` | — | Request a new PTY session |
| `SessionClose` | `session: String` | Terminate a session |
| `SessionList` | — | List active sessions |
| `Input` | `session: String, data: String` | Send keystroke data (base64) to PTY stdin |
| `Resize` | `session: String, cols: u16, rows: u16` | Resize terminal |
| `Ping` | `timestamp: u64` | Heartbeat (ms since epoch) |

### Server → Client

| Type | Fields | Description |
|---|---|---|
| `AuthOk` | `device_id: String` | Authentication succeeded |
| `AuthFail` | `reason: String` | Auth failed (`token_expired`, `token_invalid`, `token_consumed`) |
| `SessionCreated` | `session: String, shell: String` | New session ready |
| `SessionClosed` | `session: String` | Session terminated by client |
| `SessionExited` | `session: String, code: i32` | Shell process exited naturally |
| `SessionList` | `sessions: [{id, shell, alive}]` | Active session list |
| `Output` | `session: String, data: String` | PTY output (base64) |
| `Pong` | `timestamp: u64` | Heartbeat response |
| `Error` | `code: String, message: String` | Error (`auth_required`, `session_not_found`, ...) |

### Connection Flow

```
Client                              Server
  │                                   │
  │─── [WebSocket handshake] ────────►│
  │◄── [101 Switching Protocols] ─────│
  │                                   │
  │─── Auth { token } ──────────────►│  (must arrive within 10s)
  │◄── AuthOk { device_id } ─────────│  (token consumed)
  │                                   │
  │─── SessionCreate ────────────────►│
  │◄── SessionCreated { id, shell } ──│  (PTY spawned)
  │                                   │
  │─── Input { session, data } ──────►│  ┐
  │◄── Output { session, data } ──────│  │ interactive loop
  │─── Resize { session, cols, rows }►│  │
  │─── Ping { ts } ─────────────────►│  │
  │◄── Pong { ts } ──────────────────│  ┘
  │                                   │
  │◄── SessionExited { id, code } ────│  (shell exited naturally)
  │                                   │
  │─── SessionClose { id } ──────────►│
  │◄── SessionClosed { id } ──────────│
```

---

## Authentication & Pairing

### Token Lifecycle

1. **Generation**: Server generates a 32-character hex token (128 bits of randomness via `rand`)
2. **Display**: Token and a 6-digit short code are shown in the TUI/web dashboard and encoded in the QR payload
3. **Delivery**: QR scan or manual entry on iOS
4. **Validation**: Constant-time comparison (`subtle::ConstantTimeEq`) prevents timing attacks
5. **Consumption**: Token is consumed on successful auth — single-use only
6. **Expiry**: Configurable TTL (default 300s), checked on validation
7. **Memory safety**: Token stored in `Zeroizing<String>` (wiped from memory on drop)

### Short Code Derivation

```
SHA-256(token) → take first 4 bytes as big-endian u32 → mod 1,000,000 → zero-pad to 6 digits
```

Example: token `a1b2c3d4...` → SHA-256 → bytes `[0xF3, 0x2A, ...]` → `0xF32A...` → `407234`

### QR Payload Format

```
bashmirror://{lan_ip}:{port}?token={token}&fp={cert_fingerprint}
```

Example:
```
bashmirror://192.168.1.100:8765?token=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4&fp=aa:bb:cc:dd:...
```

The iOS app registers the `bashmirror://` URL scheme, so scanning the QR triggers automatic connection with TLS fingerprint pinning.

### Auth Results

| Result | Cause | Server Action |
|---|---|---|
| `Valid` | Token matches, not expired | Token consumed, `AuthOk` sent |
| `Expired` | Token TTL exceeded | Token cleared, `AuthFail` sent |
| `Invalid` | Wrong token value | `AuthFail` sent |
| `NoToken` | No active token on server | `AuthFail` sent |

---

## TLS & Certificate Pinning

### Certificate Generation

On startup (unless `--no-tls`), the server generates a self-signed X.509 certificate:

- **Generator**: `rcgen` crate
- **Key type**: PKCS#8 (rustls-compatible)
- **Subject Alternative Names**: `localhost`, `bash-mirror.local`, LAN IP address
- **Output**: DER-encoded certificate + private key → `TlsAcceptor`

### Fingerprint

- **Algorithm**: SHA-256 of the DER-encoded certificate
- **Format**: Colon-separated hex (e.g., `aa:bb:cc:dd:ee:ff:...`)
- **Distribution**: Embedded in QR payload (`fp` parameter)
- **Display**: Shown in TUI dashboard for manual verification

### iOS Certificate Pinning

The `WebSocketService` implements `URLSessionDelegate` to validate the server certificate:

1. Extract server certificate from TLS challenge
2. Compute SHA-256 fingerprint (colon-separated hex)
3. Compare against expected fingerprint from QR payload
4. **Match**: Accept connection with server credential
5. **Mismatch**: Cancel authentication challenge (connection fails)
6. **No fingerprint** (manual connect without FP): Trust any certificate (development fallback)

---

## PTY Session Management

### Threading Model

```
┌──────────────────────────┐
│  tokio async runtime     │
│                          │
│  WebSocket handler ──────┼──── mpsc::UnboundedChannel ──► writer_thread (std::thread)
│       (reads Input)      │         (input bytes)             │
│                          │                                   ▼
│                          │                              PTY master
│                          │                              (write side)
│  Output sender ◄─────────┼──── mpsc::UnboundedChannel ◄── reader_thread (std::thread)
│  (sends to client)       │         (output bytes)            │
│                          │                                   ▲
│                          │                              PTY master
│                          │                              (read side)
└──────────────────────────┘
```

PTY I/O uses **blocking OS threads** bridged to async tokio via `mpsc::UnboundedChannel`. This is necessary because `portable-pty` exposes synchronous `Read`/`Write` traits that cannot be used directly in async contexts.

### Reader Thread

- Reads PTY output in 4096-byte chunks
- Sends each chunk through the unbounded channel
- Exits on: EOF (0 bytes), EIO (slave closed — expected on macOS), or other errors
- Interrupted system calls are retried (spurious wakeups)

### Writer Thread

- Blocks on `mpsc::UnboundedReceiver::blocking_recv()`
- Writes received bytes to PTY master with full flush
- Exits when channel closes (session dropped)

### Session Lifecycle

1. `SessionManager::create_session()` → spawns `PtySession` with `portable-pty`
2. PTY environment: `TERM=xterm-256color`, configured shell, initial size 80x24
3. Reader and writer threads start immediately
4. Output receiver is transferred to the WebSocket handler via `take_output_rx()`
5. `check_exited()` is called periodically to detect shell exits (polls `try_wait()`)
6. On exit: `SessionExited` sent to client, session removed from manager
7. On close: `PtySession::kill()` sends SIGKILL, session cleaned up

### Limits

- `max_sessions` (default: 4) — enforced in `create_session()`
- Session IDs: UUID v4 (full 36-character format)

---

## Web Dashboard

An axum-based HTTP dashboard that runs alongside the WebSocket server (separate port). Auto-opens in the default browser on startup.

### Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/` | Dashboard HTML page (embedded) |
| GET | `/api/status` | Server status, token info, session list |
| POST | `/api/token/rotate` | Generate a new auth token |
| DELETE | `/api/sessions/:id` | Close a specific session |
| GET | `/api/qr` | QR code as SVG (bashmirror:// format) |
| GET | `/api/logs` | SSE stream of server log events |

### Status Response

```json
{
  "server_url": "wss://192.168.1.100:8765",
  "uptime_secs": 3600,
  "token": {
    "token": "a1b2c3d4...",
    "short_code": "407234",
    "remaining_secs": 245,
    "expired": false
  },
  "sessions": [
    { "id": "uuid-1", "shell": "/bin/zsh", "alive": true }
  ]
}
```

### Log Streaming

The `/api/logs` endpoint uses Server-Sent Events (SSE) backed by a `broadcast::Sender<String>`. Server events (connections, disconnections, session creation, errors) are broadcast in real time.

---

## CLI Reference

```
bash-mirror [OPTIONS]
```

| Flag | Default | Description |
|---|---|---|
| `-p, --port <PORT>` | `0` (random) | WebSocket server port |
| `-s, --shell <SHELL>` | `$SHELL` or `/bin/zsh` | Shell executable |
| `--multi` | `false` | Allow multiple simultaneous device connections |
| `--no-tui` | `false` | Disable TUI dashboard, print to stdout |
| `--no-tls` | `false` | Disable TLS (development only) |
| `--token-ttl <SECS>` | `300` | Token expiry in seconds |
| `-v, --verbose` | `false` | Enable DEBUG-level logging |
| `--bind <IP>` | auto-detected LAN IP | Bind address |
| `--max-connections <N>` | `8` | Max concurrent WebSocket connections |
| `--auth-timeout <SECS>` | `10` | Seconds to wait for Auth message |
| `--max-sessions <N>` | `4` | Max concurrent PTY sessions |
| `--no-open` | `false` | Don't auto-open web dashboard in browser |
| `--dashboard-port <PORT>` | `0` (random) | Web dashboard HTTP port |

### Examples

```bash
# Defaults: TUI dashboard, random port, $SHELL, TLS enabled
bash-mirror

# Custom port and shell
bash-mirror --port 8765 --shell /bin/bash

# Headless with debug logs
bash-mirror --no-tui --verbose

# Allow multiple phones, longer token TTL
bash-mirror --multi --token-ttl 600

# Bind to all interfaces
bash-mirror --bind 0.0.0.0

# Development: no TLS, no browser auto-open
bash-mirror --no-tls --no-open
```

---

## Build & Development

### Prerequisites

- **Rust** 1.70+ — [rustup.rs](https://rustup.rs)
- **Xcode** 15+ with iOS 26.0 SDK
- **XcodeGen** — `brew install xcodegen`

### Build Commands

```bash
# Build all Rust crates
cargo build

# Release build
cargo build --release

# Install CLI globally
cargo install --path crates/bash-mirror-cli --locked

# Run the server (dev)
cargo run -p bash-mirror-cli

# Lint
cargo clippy --workspace

# Check without building
cargo check
```

### iOS Build

```bash
cd ios/BashMirror

# Regenerate Xcode project from project.yml
xcodegen generate

# Open in Xcode
open BashMirror.xcodeproj
```

Build and run on a physical device (QR scanning requires a camera). Set your development team in Xcode signing settings.

### Development Tips

- Use `--no-tls --no-tui --verbose` for easier debugging
- The web dashboard is useful for monitoring without the TUI
- Token short codes make manual testing easier than typing full tokens
- `--token-ttl 3600` gives you an hour before token expires during development
- Both devices must be on the same LAN (Wi-Fi network)
