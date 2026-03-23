# bash-mirror

Control your terminal from your phone. Run a lightweight server on your Mac or Linux machine, scan a QR code, and get a full interactive shell on your iOS device over LAN.

![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Rust](https://img.shields.io/badge/rust-2021-orange)
![iOS](https://img.shields.io/badge/iOS-26.0+-black)
![License](https://img.shields.io/badge/license-MIT-green)

## How It Works

```
┌──────────────┐     WebSocket (LAN)     ┌──────────────────┐
│   iPhone     │ ◄──────────────────────► │  Mac / Linux     │
│              │                          │                  │
│  xterm.js    │   JSON protocol over WS  │  PTY sessions    │
│  terminal    │ ◄──────────────────────► │  (zsh/bash/...)  │
│  in WKWebView│                          │                  │
└──────────────┘                          └──────────────────┘
     iOS App                               bash-mirror CLI
```

1. Start `bash-mirror` on your computer — it launches a WebSocket server and displays a QR code
2. Open the iOS app and scan the QR code (or enter the IP/token manually)
3. The app authenticates with a one-time token and creates a PTY session
4. You get a fully interactive terminal on your phone, rendered with xterm.js

## Tech Stack

### Server (Rust)

| Crate | Purpose |
|-------|---------|
| [tokio](https://tokio.rs) | Async runtime |
| [tokio-tungstenite](https://github.com/snapview/tokio-tungstenite) | WebSocket server |
| [portable-pty](https://docs.rs/portable-pty) | Cross-platform PTY management |
| [ratatui](https://ratatui.rs) + [crossterm](https://docs.rs/crossterm) | TUI dashboard |
| [rcgen](https://docs.rs/rcgen) + [rustls](https://docs.rs/rustls) | Self-signed TLS certificate generation |
| [clap](https://docs.rs/clap) | CLI argument parsing |
| [qr2term](https://docs.rs/qr2term) | QR code display in terminal |

### iOS App (Swift)

| Technology | Purpose |
|------------|---------|
| SwiftUI | Native UI framework |
| WKWebView + [xterm.js](https://xtermjs.org) | Terminal rendering |
| AVFoundation | QR code scanning |
| URLSessionWebSocketTask | WebSocket client |

## Prerequisites

- **Rust** 1.70+ — [Install](https://rustup.rs)
- **Xcode** 15+ with iOS 26.0 SDK (for the iOS app)
- **XcodeGen** (optional, for regenerating the Xcode project) — `brew install xcodegen`

## Setup

### Server

```bash
# Clone the repository
git clone https://github.com/user/bash-mirror.git
cd bash-mirror

# Build
cargo build --release

# The binary is at target/release/bash-mirror
```

### iOS App

```bash
cd ios/BashMirror

# Regenerate Xcode project (if needed)
xcodegen generate

# Open in Xcode
open BashMirror.xcodeproj
```

Set your development team in Xcode signing settings, then build and run on a physical device (camera required for QR scanning).

## Usage

### Start the server

```bash
# Default: TUI dashboard, random port, uses $SHELL
bash-mirror

# Specify port and shell
bash-mirror --port 8080 --shell /bin/bash

# Headless mode (no TUI, prints connection info to stdout)
bash-mirror --no-tui

# Verbose logging
bash-mirror --verbose

# Custom token expiry (default: 300s)
bash-mirror --token-ttl 600
```

### TUI Dashboard

When running with the TUI (default), the dashboard shows:

- **Connection info** — IP, port, WebSocket URL, and auth token
- **Connected devices** — currently paired phones
- **Active sessions** — running PTY sessions with status
- **Log** — timestamped event stream

Keyboard shortcuts:

| Key | Action |
|-----|--------|
| `q` | Quit |
| `r` | Regenerate auth token |
| `d` | Disconnect all devices |

### Connect from iOS

1. Open the BashMirror app
2. **Scan QR** — point the camera at the QR code shown in the terminal
3. **Or connect manually** — enter the IP address, port, and token displayed by the server

Once connected, you have a full interactive terminal. The app supports:

- Touch-based text selection
- Custom command pad with common shortcuts
- Full keyboard input
- Terminal resize (adapts to screen orientation)

## Protocol

Communication uses JSON messages over WebSocket with a `"type"` discriminator:

```
Client                          Server
  │                               │
  │──── Auth { token } ──────────►│
  │◄─── AuthOk { device_id } ────│
  │                               │
  │──── SessionCreate ───────────►│
  │◄─── SessionCreated { id } ───│
  │                               │
  │──── Input { session, data } ─►│
  │◄─── Output { session, data } ─│  (base64-encoded)
  │                               │
  │──── Resize { cols, rows } ───►│
  │──── Ping { timestamp } ──────►│
  │◄─── Pong { timestamp } ──────│
  │                               │
  │──── SessionClose { id } ─────►│
  │◄─── SessionClosed { id } ────│
```

## Project Structure

```
bash-mirror/
├── crates/
│   ├── bash-mirror-proto/    # Shared protocol types (no async deps)
│   ├── bash-mirror-core/     # PTY sessions, auth, TLS, session management
│   └── bash-mirror-cli/      # Binary: WebSocket server + TUI dashboard
└── ios/
    └── BashMirror/           # SwiftUI iOS app
        ├── Views/            # SwiftUI views (scanner, terminal, keyboard)
        ├── Services/         # WebSocket + connection management
        ├── Models/           # Protocol message types
        └── Resources/        # xterm.js, terminal.html, CSS
```

## Security

- **One-time tokens** — auth tokens are consumed on first use and expire after a configurable TTL (default 5 minutes)
- **LAN-only** — designed for local network use; binds to `0.0.0.0` but intended for trusted networks
- **TLS ready** — self-signed certificate generation is built in (rcgen + rustls), certificate fingerprint is included in the QR payload for pinning
- **No data persistence** — no session data is stored on disk; everything lives in memory

## License

MIT
