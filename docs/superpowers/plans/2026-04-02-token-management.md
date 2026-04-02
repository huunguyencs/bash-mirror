# Token Management Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add distinct auth error messages, SIGUSR1 token rotation for headless mode, and surface auth errors in the iOS app so users know what went wrong and what to do.

**Architecture:** The `AuthResult` enum replaces `bool` in `PairingManager::validate_token()`. The server maps each variant to a distinct reason string sent via the existing `AuthFail` message. A SIGUSR1 signal handler calls `generate_token()` in headless mode. The iOS app adds `authError` to `ConnectionManager` and displays it on both ManualConnectView and ScannerContainerView.

**Tech Stack:** Rust (tokio, tokio-tungstenite), SwiftUI (iOS 26.0+)

**Build commands:**
- Rust: `cargo build -p bash-mirror-cli` / `cargo test -p bash-mirror-core`
- iOS: `xcodebuild -project ios/BashMirror/BashMirror.xcodeproj -scheme BashMirror -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" -derivedDataPath /tmp/bash-mirror-build build 2>&1 | tail -3`

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| **Modify** | `crates/bash-mirror-core/src/auth.rs` | Add `AuthResult` enum, change `validate_token` return type |
| **Modify** | `crates/bash-mirror-cli/src/server.rs:231-257` | Match on `AuthResult`, send distinct reason strings |
| **Modify** | `crates/bash-mirror-cli/src/main.rs:156-179` | Add SIGUSR1 handler in headless mode |
| **Modify** | `ios/BashMirror/BashMirror/Services/ConnectionManager.swift:117-119` | Add `authError`, map reason strings to user messages |
| **Modify** | `ios/BashMirror/BashMirror/Views/ManualConnectView.swift` | Add error banner between token field and connect button |
| **Modify** | `ios/BashMirror/BashMirror/BashMirrorApp.swift` (ScannerContainerView) | Add error banner for QR auth failures |

---

## Task 1: Add AuthResult Enum to PairingManager

**Files:**
- Modify: `crates/bash-mirror-core/src/auth.rs`

- [ ] **Step 1: Add the AuthResult enum**

Add above the `PairingManager` struct (after the `impl PairingToken` block, around line 32):

```rust
#[derive(Debug, Clone, PartialEq)]
pub enum AuthResult {
    Valid,
    Expired,
    Invalid,
    NoToken,
}
```

- [ ] **Step 2: Change validate_token to return AuthResult**

Replace the `validate_token` method (lines 61-96) with:

```rust
    pub fn validate_token(&mut self, token: &str) -> AuthResult {
        match &self.active_token {
            None => {
                debug!("validate_token: no active token");
                AuthResult::NoToken
            }
            Some(active) if active.is_expired() => {
                debug!(
                    "validate_token: token expired ({}s ago)",
                    active.created_at.elapsed().as_secs().saturating_sub(active.ttl.as_secs())
                );
                self.active_token = None; // clean up expired token
                AuthResult::Expired
            }
            Some(active) => {
                let active_bytes = active.token.as_bytes();
                let input_bytes = token.as_bytes();
                debug!(
                    "validate_token: stored len={} first8={:?}, input len={} first8={:?}",
                    active_bytes.len(),
                    String::from_utf8_lossy(&active_bytes[..active_bytes.len().min(8)]),
                    input_bytes.len(),
                    String::from_utf8_lossy(&input_bytes[..input_bytes.len().min(8)]),
                );
                if active_bytes.len() == input_bytes.len()
                    && active_bytes.ct_eq(input_bytes).into()
                {
                    self.active_token = None; // one-time use
                    AuthResult::Valid
                } else {
                    debug!("validate_token: mismatch (len match={})", active_bytes.len() == input_bytes.len());
                    AuthResult::Invalid
                }
            }
        }
    }
```

- [ ] **Step 3: Build to verify**

```bash
cargo build -p bash-mirror-core 2>&1 | tail -5
```

This will fail because `server.rs` still expects `bool`. That's expected — we fix it in Task 2.

- [ ] **Step 4: Commit**

```bash
git add crates/bash-mirror-core/src/auth.rs
git commit -m "feat(core): add AuthResult enum with distinct token validation outcomes"
```

---

## Task 2: Update Server to Send Distinct Error Reasons

**Files:**
- Modify: `crates/bash-mirror-cli/src/server.rs:231-257`

- [ ] **Step 1: Add use import**

At the top of `server.rs`, ensure the import includes `AuthResult`:

```rust
use bash_mirror_core::auth::{AuthResult, PairingManager};
```

(Replace the existing `use bash_mirror_core::auth::PairingManager;` line.)

- [ ] **Step 2: Replace the auth validation block**

Replace lines 231-257 (the `Ok(ClientMessage::Auth { token })` match arm) with:

```rust
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
```

- [ ] **Step 3: Build the full workspace**

```bash
cargo build 2>&1 | tail -5
```
Expected: `Finished` with no errors.

- [ ] **Step 4: Commit**

```bash
git add crates/bash-mirror-cli/src/server.rs
git commit -m "feat(cli): send distinct auth failure reasons (expired/invalid/consumed)"
```

---

## Task 3: Add SIGUSR1 Token Rotation for Headless Mode

**Files:**
- Modify: `crates/bash-mirror-cli/src/main.rs:156-179`

- [ ] **Step 1: Replace the headless mode block**

Replace the `if cli.no_tui { ... }` block (lines 156-179) with:

```rust
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
                println!("  New Token: {}", new_token.token);
                println!("  New Code:  {}", new_token.short_code);
                println!("  Expires in {}s\n", new_token.ttl.as_secs());
            }
        });

        // Wait for Ctrl+C
        tokio::signal::ctrl_c().await?;
```

- [ ] **Step 2: Build and verify**

```bash
cargo build -p bash-mirror-cli 2>&1 | tail -3
```
Expected: `Finished` with no errors.

- [ ] **Step 3: Quick manual test**

```bash
# Terminal 1: start server
cargo run -p bash-mirror-cli -- --no-tui --no-tls --port 8765 &
SERVER_PID=$!
sleep 2

# Terminal 2: send SIGUSR1
kill -USR1 $SERVER_PID

# Verify new token printed
sleep 1
kill $SERVER_PID
```
Expected: Server prints "Token rotated!" with a new token and code.

- [ ] **Step 4: Commit**

```bash
git add crates/bash-mirror-cli/src/main.rs
git commit -m "feat(cli): add SIGUSR1 handler for token rotation in headless mode"
```

---

## Task 4: iOS — Add authError to ConnectionManager

**Files:**
- Modify: `ios/BashMirror/BashMirror/Services/ConnectionManager.swift`

- [ ] **Step 1: Add authError property**

After the existing `@Published var errorMessage: String?` (line 14), add:

```swift
    @Published var authError: String?
```

- [ ] **Step 2: Update the authFail handler**

Replace the `case .authFail` handler (lines 117-119) with:

```swift
        case .authFail(let reason):
            state = .disconnected
            switch reason {
            case "token_expired":
                authError = "Token expired — generate a new one on the server"
            case "token_invalid":
                authError = "Invalid token — check and try again"
            case "token_consumed":
                authError = "Token already used — generate a new one on the server"
            default:
                authError = "Authentication failed: \(reason)"
            }
```

- [ ] **Step 3: Clear authError when starting a new connection**

At the top of the `connect(host:port:token:fingerprint:)` method, after `state = .connecting`, add:

```swift
        authError = nil
```

Also at the top of `connectFromQR(_:)`, before the guard, add:

```swift
        authError = nil
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project ios/BashMirror/BashMirror.xcodeproj -scheme BashMirror \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" \
  -derivedDataPath /tmp/bash-mirror-build build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/BashMirror/BashMirror/Services/ConnectionManager.swift
git commit -m "feat(ios): add authError with distinct messages for each failure type"
```

---

## Task 5: iOS — Error Banner on ManualConnectView

**Files:**
- Modify: `ios/BashMirror/BashMirror/Views/ManualConnectView.swift`

- [ ] **Step 1: Add error banner between token helper text and connect button**

In ManualConnectView, find the comment `// Connect button` and add this block just before it:

```swift
                // Auth error banner
                if let error = connectionManager.authError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.danger)
                        Text(error)
                            .font(Theme.Fonts.captionSmall)
                            .foregroundColor(Theme.Colors.danger)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.danger.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radii.input)
                            .stroke(Theme.Colors.danger.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(Theme.Radii.input)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
```

- [ ] **Step 2: Clear error when user edits fields**

Add `.onChange` modifiers to the VStack in the body, just before the `.presentationBackground` modifier:

```swift
        .onChange(of: host) { connectionManager.authError = nil }
        .onChange(of: port) { connectionManager.authError = nil }
        .onChange(of: token) { connectionManager.authError = nil }
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
git add ios/BashMirror/BashMirror/Views/ManualConnectView.swift
git commit -m "feat(ios): show auth error banner on manual connect form"
```

---

## Task 6: iOS — Error Banner on Connection Screen (QR flow)

**Files:**
- Modify: `ios/BashMirror/BashMirror/BashMirrorApp.swift` (ScannerContainerView)

- [ ] **Step 1: Add error banner and auto-dismiss state**

In ScannerContainerView, add a state variable at the top of the struct:

```swift
    @State private var showError = false
```

- [ ] **Step 2: Add error banner below the "Camera ready" indicator**

After the `HStack` containing the "Camera ready" indicator (the status dot), add:

```swift
                    // Auth error
                    if showError, let error = connectionManager.authError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.Colors.danger)
                            Text(error)
                                .font(Theme.Fonts.captionSmall)
                                .foregroundColor(Theme.Colors.danger)
                                .lineLimit(2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.danger.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radii.input)
                                .stroke(Theme.Colors.danger.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(Theme.Radii.input)
                        .padding(.horizontal, 32)
                        .onTapGesture {
                            connectionManager.authError = nil
                            showError = false
                        }
                    }
```

- [ ] **Step 3: Add onChange to show/auto-dismiss error**

Add this modifier to the outer ZStack (before `.sheet`):

```swift
        .onChange(of: connectionManager.authError) {
            if connectionManager.authError != nil {
                showError = true
                // Auto-dismiss after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    showError = false
                    connectionManager.authError = nil
                }
            }
        }
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project ios/BashMirror/BashMirror.xcodeproj -scheme BashMirror \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" \
  -derivedDataPath /tmp/bash-mirror-build build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/BashMirror/BashMirror/BashMirrorApp.swift
git commit -m "feat(ios): show auto-dismissing auth error on connection screen"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | `AuthResult` enum in PairingManager | `auth.rs` |
| 2 | Distinct error reasons in server | `server.rs` |
| 3 | SIGUSR1 token rotation (headless) | `main.rs` |
| 4 | `authError` in ConnectionManager | `ConnectionManager.swift` |
| 5 | Error banner on ManualConnectView | `ManualConnectView.swift` |
| 6 | Error banner on ScannerContainerView | `BashMirrorApp.swift` |
