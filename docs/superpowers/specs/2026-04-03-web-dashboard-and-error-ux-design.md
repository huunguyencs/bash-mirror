# Web Dashboard & Error UX — Design Spec

**Date:** 2026-04-03
**Goal:** Add a local web management dashboard for the server and fix silent auth error handling on iOS.

---

## 1. Web Management Dashboard

### Overview
A single-page web dashboard served by the bash-mirror server on a separate HTTP port. Provides token management, session visibility, and live logs without needing the TUI.

### Access
- Served on `http://localhost:{dashboard_port}` (random port, printed at startup)
- Auto-opens in the default browser on startup (suppress with `--no-open` flag)
- Only binds to `127.0.0.1` (localhost only — not exposed to LAN for security)

### UI Sections (single page)

**Header:**
- "bash-mirror" title + server version
- Connection URL (`ws://` or `wss://` with host:port)
- Uptime counter

**Token & QR:**
- Current token (full string, copyable)
- Short code (6-digit)
- QR code rendered as SVG (using a JS QR library or server-rendered)
- Time remaining countdown (live, updates every second)
- "Rotate Token" button — calls POST `/api/rotate-token`, refreshes display
- Token status: "Active (Xs remaining)" or "Expired" in red

**Active Sessions:**
- Table: Session ID, Shell, Status (alive/exited), Created at
- "Close" button per session — calls POST `/api/sessions/{id}/close`
- "New Session" button — disabled (sessions are created by clients, not server)

**Connected Devices:**
- List of connected device addresses + device IDs

**Live Logs:**
- Scrolling log viewer (newest at bottom, auto-scroll)
- Streams logs via Server-Sent Events (SSE) at `GET /api/logs/stream`
- Shows last 100 log entries on page load

### API Endpoints

| Method | Path | Action |
|--------|------|--------|
| GET | `/` | Serve the dashboard HTML page |
| GET | `/api/status` | JSON: token info, sessions, devices, connection info |
| POST | `/api/rotate-token` | Generate new token, return new token info |
| POST | `/api/sessions/{id}/close` | Close a specific session |
| GET | `/api/logs/stream` | SSE stream of log events |

### Tech Stack
- **Server:** `axum` (lightweight, already tokio-based) for HTTP + SSE
- **Frontend:** Single HTML file with inline CSS/JS (no build step, no npm). Vanilla JS. Bundled as a `include_str!` in the binary.
- **QR rendering:** `qrcode` crate generating SVG string, served via API
- **SSE:** `axum::response::Sse` with `tokio::sync::broadcast` channel

### Architecture
- New crate: NO — add a `dashboard` module to `bash-mirror-cli`
- The web dashboard runs alongside the WebSocket server on a separate `TcpListener`
- Shares the same `Arc<Mutex<PairingManager>>`, `Arc<Mutex<SessionManager>>`, and event channel
- New CLI flags: `--no-open` (suppress browser auto-open), `--dashboard-port` (default: 0 = random)

### Security
- Dashboard binds to `127.0.0.1` only (never exposed to LAN)
- No authentication needed (local access only)
- Token is visible on the dashboard (this is intentional — it's the management interface)

---

## 2. iOS Auth Error UX Fix

### Problem
When a QR scan or manual connect results in `AuthFail`, the app transitions back to the connection screen but shows no error. The `authError` is set asynchronously after the scanner sheet dismissal, and the SwiftUI `onChange` handler doesn't reliably fire during view transitions.

### Root Cause
The flow is:
1. `connectFromQR(code)` — clears `authError`, sets `state = .connecting`
2. Scanner sheet dismissed (`showScanner = false`)
3. ContentView shows `ProgressView("Connecting...")`
4. WebSocket connects, server sends `AuthFail`
5. `handleMessage` sets `state = .disconnected` and `authError = "..."`
6. ContentView switches back to `ScannerContainerView`
7. `ScannerContainerView` appears fresh — `showError` is `false`, and `onChange` may not trigger because the view just appeared

### Fix
Instead of relying on `onChange` in ScannerContainerView, check `authError` on appear:

1. **ScannerContainerView**: Add `.onAppear` that checks if `connectionManager.authError` is non-nil and shows the banner
2. **Remove the `showError` state variable** — just use `connectionManager.authError != nil` directly as the condition. This is simpler and doesn't have the timing issue.
3. **Auto-dismiss**: Use `.task` with a delay instead of `DispatchQueue.main.asyncAfter`, tied to the authError value

### Also fix for ManualConnectView
The manual connect sheet stays open (it doesn't dismiss on auth failure since we removed the auto-dismiss). The error banner should just appear on the form. But currently `dismiss()` is called inside the connect button action BEFORE the async auth completes. Fix: don't dismiss on button tap — dismiss only on successful connection via an `onChange(of: connectionManager.state)`.

### Files affected
- `ios/BashMirror/BashMirror/BashMirrorApp.swift` — ScannerContainerView error display fix
- `ios/BashMirror/BashMirror/Views/ManualConnectView.swift` — don't dismiss early, dismiss on success

---

## Summary

| Feature | Scope |
|---------|-------|
| Web dashboard | New axum HTTP server, single-page HTML dashboard, REST API, SSE logs |
| iOS error fix | Fix timing of error display on both scanner and manual connect screens |
