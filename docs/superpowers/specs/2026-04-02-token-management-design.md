# Token Management Improvements — Design Spec

**Date:** 2026-04-02
**Goal:** Improve token expiration UX, add token rotation without server restart, and surface auth errors clearly in the iOS app.

---

## 1. Server — Distinct Auth Results

### Current behavior
`PairingManager::validate_token()` returns `bool`. The server sends a generic `"invalid or expired token"` for all failures.

### New behavior
Replace the bool return with an enum:

```rust
pub enum AuthResult {
    Valid,
    Expired,       // token exists but TTL has passed
    Invalid,       // token doesn't match the active token
    NoToken,       // no active token (already consumed or never generated)
}
```

`validate_token()` returns `AuthResult` instead of `bool`. On `Valid`, the token is still consumed (one-time use).

The server maps each variant to a distinct `AuthFail` reason string:

| AuthResult | `reason` field | Meaning |
|------------|---------------|---------|
| `Expired` | `"token_expired"` | Token existed but TTL passed |
| `Invalid` | `"token_invalid"` | Token doesn't match |
| `NoToken` | `"token_consumed"` | No active token available |

### Files affected
- `crates/bash-mirror-core/src/auth.rs` — add `AuthResult` enum, change `validate_token` return type
- `crates/bash-mirror-cli/src/server.rs` — match on `AuthResult` variants, send distinct reason strings

---

## 2. Server — Token Rotation

### TUI trigger
In the dashboard event loop, handle a new key `r`:
- Call `pairing_manager.generate_token()`
- Update the dashboard display with new token/code
- Log: `"Token rotated (new code: XXXXXX)"`

### Signal trigger (headless)
Register a `SIGUSR1` handler using `tokio::signal::unix::signal(SignalKind::user_defined1())`:
- Call `pairing_manager.generate_token()`
- Print new token, code, and remaining TTL to stdout
- Log: `"Token rotated via SIGUSR1 (new code: XXXXXX)"`

### Behavior
- Rotation immediately invalidates the old token (replaced in `active_token`)
- New token gets a fresh TTL countdown
- Works in both TUI and `--no-tui` modes (TUI key only works when TUI is active, signal works always)

### Files affected
- `crates/bash-mirror-cli/src/main.rs` — register SIGUSR1 handler, pass pairing manager to signal handler
- `crates/bash-mirror-cli/src/dashboard.rs` — handle `r` key press, call rotate, update display

---

## 3. iOS — Auth Error on Manual Connect Form

### ConnectionManager changes
Add a new published property:
```swift
@Published var authError: String?
```

When `AuthFail` is received, map the reason to a user-friendly message:

| Server reason | User-facing message |
|---------------|-------------------|
| `"token_expired"` | "Token expired — generate a new one on the server" |
| `"token_invalid"` | "Invalid token — check and try again" |
| `"token_consumed"` | "Token already used — generate a new one on the server" |
| other/unknown | "Authentication failed: \(reason)" |

Set `state = .disconnected` and `authError = message`.

Clear `authError` when `connect()` is called (new attempt).

### ManualConnectView changes
Add an error banner between the Token field helper text and the Connect button:
- Only visible when `connectionManager.authError` is non-nil
- Red background tint (`Theme.Colors.danger.opacity(0.1)`)
- Red border (`Theme.Colors.danger.opacity(0.3)`)
- Warning icon (SF Symbol `exclamationmark.triangle`) + error text
- Font: `Theme.Fonts.captionSmall`, color: `Theme.Colors.danger`
- Rounded corners: `Theme.Radii.input`
- Clears when user edits any field (host, port, or token)

### Files affected
- `ios/BashMirror/BashMirror/Services/ConnectionManager.swift` — add `authError`, map reasons
- `ios/BashMirror/BashMirror/Views/ManualConnectView.swift` — add error banner

---

## 4. iOS — Auth Error on Connection Screen (QR flow)

### ScannerContainerView changes
When `connectionManager.authError` is non-nil and the view is showing (QR scan failed auth):
- Show a red error banner below the "Camera ready" indicator
- Same styling as ManualConnectView error banner
- Auto-dismisses after 5 seconds or when user taps it
- Clears `authError` on dismiss

### Files affected
- `ios/BashMirror/BashMirror/BashMirrorApp.swift` (ScannerContainerView is defined here)

---

## Protocol — No Changes Needed

The existing `AuthFail { reason: String }` message type already supports distinct reason strings. No protocol changes required — only the content of the `reason` field changes.

---

## Testing

### Server
- Unit test `validate_token` returns `AuthResult::Expired` after TTL passes
- Unit test `validate_token` returns `AuthResult::NoToken` after token consumed
- Unit test `validate_token` returns `AuthResult::Invalid` for wrong token
- Unit test `generate_token` replaces old token (rotation)
- Integration: verify distinct reason strings arrive over WebSocket

### iOS
- Verify error banner appears on ManualConnectView when auth fails
- Verify error clears when user edits a field
- Verify error banner appears on ScannerContainerView for QR auth failure
- Verify correct message mapping for each reason type
