# BashMirror iOS UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign all iOS UI screens to match the new dark OLED terminal aesthetic created in Paper, using JetBrains Mono font, cyan/green accent colors, refined layout with proper spacing, and an enhanced keyboard with combined key shortcuts (Ctrl+C, Ctrl+Z, etc.).

**Architecture:** Visual refactor + keyboard UX enhancement. All changes are in SwiftUI views, a new theme file, and keyboard views. The existing `Color(hex:)` extension is reused. A new `Theme.swift` centralizes all design tokens (colors, fonts, spacing). The keyboard is enhanced with a swipeable command shortcuts bar for combined key presses. We may adopt additional SwiftUI approaches (custom shapes, view modifiers, `@ViewBuilder` patterns) to achieve production-grade quality matching the Paper designs.

**Tech Stack:** SwiftUI, iOS 26.0+, XcodeGen, xterm.js (terminal.html untouched)

**Additional Libraries/Approaches to Consider:**
- Custom SwiftUI `ViewModifier` for themed input fields and buttons (DRY across screens)
- `@ViewBuilder` helper functions for reusable themed components
- Custom `Shape` for scanner frame corners (L-shaped corner overlays)
- `matchedGeometryEffect` for smooth session tab switching animations
- `sensoryFeedback` modifier (iOS 17+) instead of raw `UIImpactFeedbackGenerator`
- Swipeable keyboard modes: QWERTY / Command Pad (existing `CommandPadView` integrated)

**Simulator Verification:** After each visual task, verify with:
```bash
SIM_ID=4229443C-791F-4C25-9E07-AC8248BC68FF
xcodebuild -project ios/BashMirror/BashMirror.xcodeproj -scheme BashMirror \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" \
  -derivedDataPath /tmp/bash-mirror-build build 2>&1 | tail -3
xcrun simctl install $SIM_ID /tmp/bash-mirror-build/Build/Products/Debug-iphonesimulator/BashMirror.app
xcrun simctl launch $SIM_ID com.nguyenvanhuu.bashmirror
sleep 2
xcrun simctl io $SIM_ID screenshot /tmp/bash-mirror-screen.png
```
Then read `/tmp/bash-mirror-screen.png` to visually verify.

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| **Create** | `BashMirror/Theme.swift` | Centralized design tokens: colors, fonts, spacing, radii + reusable view modifiers |
| **Modify** | `BashMirror/BashMirrorApp.swift` | Update ContentView background + redesign ScannerContainerView |
| **Modify** | `BashMirror/Views/ManualConnectView.swift` | Redesign manual connect form with dark themed inputs |
| **Modify** | `BashMirror/Views/TerminalContainerView.swift` | Redesign SessionTabBar + keyboard toggle + keyboard mode switching |
| **Modify** | `BashMirror/Views/Keyboard/FullKeyboardView.swift` | Restyle keyboard + add combined key shortcuts bar |
| **Modify** | `BashMirror/Views/Keyboard/CommandPadView.swift` | Restyle existing command pad with theme + integrate into keyboard |
| **No change** | `BashMirror/Views/TerminalView.swift` | WKWebView wrapper — no visual changes needed |
| **No change** | `BashMirror/Views/ScannerView.swift` | AVFoundation camera — no visual changes needed |
| **No change** | `BashMirror/Services/*` | Business logic untouched |
| **No change** | `BashMirror/Models/*` | Protocol types untouched |
| **No change** | `BashMirror/Extensions.swift` | Color(hex:) already works for our needs |
| **No change** | `BashMirror/terminal.html` | xterm.js theme is separate from app UI |

---

## Task 1: Create Theme.swift — Design Tokens

**Files:**
- Create: `ios/BashMirror/BashMirror/Theme.swift`

- [ ] **Step 1: Create Theme.swift with all design tokens**

```swift
import SwiftUI

enum Theme {
    // MARK: - Colors
    enum Colors {
        static let background = Color(hex: "0A0A0F")
        static let surface = Color(hex: "111827")
        static let surfaceLight = Color(hex: "1E293B")
        static let terminal = Color(hex: "0D1117")

        static let textPrimary = Color(hex: "E2E8F0")
        static let textSecondary = Color(hex: "94A3B8")
        static let textTertiary = Color(hex: "64748B")
        static let textMuted = Color(hex: "475569")

        static let accent = Color(hex: "22D3EE")       // cyan
        static let accentDim = Color(hex: "22D3EE").opacity(0.12)
        static let accentBorder = Color(hex: "22D3EE").opacity(0.25)

        static let success = Color(hex: "10B981")       // green
        static let danger = Color(hex: "EF4444")         // red
        static let warning = Color(hex: "F97316")        // orange

        static let keyBackground = Color(hex: "1E293B")
        static let keyboardBackground = Color(hex: "111827")
        static let keyboardBorder = Color(hex: "1E293B")
    }

    // MARK: - Fonts
    enum Fonts {
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .custom("JetBrains Mono", size: size).weight(weight)
        }

        static let title = mono(32, weight: .bold)
        static let subtitle = mono(13, weight: .medium)
        static let body = mono(15)
        static let bodySmall = mono(13)
        static let caption = mono(12)
        static let captionSmall = mono(11)
        static let micro = mono(10, weight: .medium)
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }

    // MARK: - Radii
    enum Radii {
        static let key: CGFloat = 6
        static let input: CGFloat = 10
        static let button: CGFloat = 12
        static let card: CGFloat = 14
        static let scanner: CGFloat = 24
    }
}

// MARK: - Reusable View Modifiers

struct ThemedInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.body)
            .foregroundColor(Theme.Colors.textPrimary)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radii.input)
                    .stroke(Theme.Colors.surfaceLight, lineWidth: 1.5)
            )
            .cornerRadius(Theme.Radii.input)
    }
}

struct ThemedPrimaryButtonModifier: ViewModifier {
    var isEnabled: Bool = true

    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.body.weight(.semibold))
            .foregroundColor(Theme.Colors.background)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.4))
            .cornerRadius(Theme.Radii.button)
    }
}

struct ThemedOutlineButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.body.weight(.medium))
            .foregroundColor(Theme.Colors.accent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radii.button)
                    .stroke(Theme.Colors.accentBorder, lineWidth: 1.5)
            )
    }
}

struct ThemedSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Fonts.caption.weight(.medium))
            .foregroundColor(Theme.Colors.accent)
            .tracking(2)
    }
}

extension View {
    func themedInput() -> some View { modifier(ThemedInputModifier()) }
    func themedPrimaryButton(isEnabled: Bool = true) -> some View { modifier(ThemedPrimaryButtonModifier(isEnabled: isEnabled)) }
    func themedOutlineButton() -> some View { modifier(ThemedOutlineButtonModifier()) }
}
```

- [ ] **Step 2: Register JetBrains Mono font or add fallback**

JetBrains Mono is not bundled in the app. For now, use a system monospaced fallback. Update the `mono` function:

```swift
static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}
```

> Note: To use the actual JetBrains Mono, you'd need to bundle the .ttf files and register them in Info.plist. This is optional and can be done later. The system monospaced font is visually close enough for now.

- [ ] **Step 3: Add Theme.swift to XcodeGen sources**

No action needed — `project.yml` already includes all files under `BashMirror/` (excluding Resources). Theme.swift will be auto-discovered.

- [ ] **Step 4: Build to verify compilation**

```bash
xcodebuild -project ios/BashMirror/BashMirror.xcodeproj -scheme BashMirror \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" \
  -derivedDataPath /tmp/bash-mirror-build build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/BashMirror/BashMirror/Theme.swift
git commit -m "feat(ios): add Theme.swift with centralized design tokens"
```

---

## Task 2: Redesign ContentView + ScannerContainerView

**Files:**
- Modify: `ios/BashMirror/BashMirror/BashMirrorApp.swift`

The redesign replaces the basic scanner screen with the new branded connection screen from the Paper design: "REMOTE TERMINAL" subtitle, glowing "bash-mirror" title, scanner area with terminal icon, status indicator, two distinct CTAs, and version footer.

- [ ] **Step 1: Update ContentView background color**

Replace line 34:
```swift
// Old:
Color(hex: "1a1a2e").ignoresSafeArea()
// New:
Theme.Colors.background.ignoresSafeArea()
```

- [ ] **Step 2: Redesign ScannerContainerView**

Replace the entire `ScannerContainerView` struct (lines 49-84) with:

```swift
struct ScannerContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showManualEntry = false

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header branding
                VStack(spacing: 8) {
                    Text("REMOTE TERMINAL")
                        .font(Theme.Fonts.subtitle)
                        .foregroundColor(Theme.Colors.accent)
                        .tracking(4)

                    Text("bash-mirror")
                        .font(Theme.Fonts.title)
                        .foregroundColor(.white)

                    Text("Control your shell from anywhere")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .padding(.top, 4)
                }
                .padding(.top, 60)

                // Scanner area
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radii.scanner)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "0F1019"), Color(hex: "111827")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radii.scanner)
                                    .stroke(Theme.Colors.accentBorder, lineWidth: 2)
                            )

                        VStack(spacing: 16) {
                            Image(systemName: "chevron.right.square")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(Theme.Colors.accent)

                            Text("Point camera at\nQR code on terminal")
                                .font(Theme.Fonts.bodySmall)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .multilineTextAlignment(.center)
                        }

                        // Actual scanner overlay (invisible but functional)
                        ScannerView { code in
                            connectionManager.connectFromQR(code)
                        }
                        .opacity(0.01) // Hidden but active for camera capture
                    }
                    .frame(width: 280, height: 280)

                    // Status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.Colors.accent)
                            .frame(width: 8, height: 8)
                            .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 4)
                        Text("Camera ready")
                            .font(Theme.Fonts.captionSmall)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .padding(.top, 40)

                // CTAs
                VStack(spacing: 12) {
                    Button(action: {
                        // Scanner is always active above; this is a visual affordance
                    }) {
                        Text("Scan QR Code")
                            .font(Theme.Fonts.body.weight(.semibold))
                            .foregroundColor(Theme.Colors.background)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.Colors.accent)
                            .cornerRadius(Theme.Radii.button)
                    }

                    Button(action: { showManualEntry = true }) {
                        Text("Connect Manually")
                            .font(Theme.Fonts.body.weight(.medium))
                            .foregroundColor(Theme.Colors.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radii.button)
                                    .stroke(Theme.Colors.accentBorder, lineWidth: 1.5)
                            )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)

                Spacer()

                // Footer
                VStack(spacing: 4) {
                    Text("Secured with one-time tokens")
                        .font(Theme.Fonts.captionSmall)
                        .foregroundColor(Theme.Colors.textMuted)
                    Text("v0.1.0 \u{00B7} LAN only")
                        .font(Theme.Fonts.captionSmall)
                        .foregroundColor(Color(hex: "334155"))
                }
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualConnectView()
        }
    }
}
```

- [ ] **Step 3: Build and screenshot to verify**

```bash
xcodebuild ... build && xcrun simctl install ... && xcrun simctl launch ... && sleep 2 && xcrun simctl io ... screenshot /tmp/bash-mirror-screen.png
```
Read `/tmp/bash-mirror-screen.png`. Expected: dark OLED background, cyan "REMOTE TERMINAL" subtitle, large "bash-mirror" title, scanner area with chevron icon, status dot, two styled buttons, footer text.

- [ ] **Step 4: Commit**

```bash
git add ios/BashMirror/BashMirror/BashMirrorApp.swift
git commit -m "feat(ios): redesign connection screen with dark OLED theme"
```

---

## Task 3: Redesign ManualConnectView

**Files:**
- Modify: `ios/BashMirror/BashMirror/Views/ManualConnectView.swift`

Replace the default iOS Form with custom dark-themed inputs matching the Paper design: section headers in cyan, dark input fields with subtle borders, helper text under token field, and themed connect button.

- [ ] **Step 1: Replace entire ManualConnectView**

Replace all content of `ManualConnectView.swift` with:

```swift
import SwiftUI

struct ManualConnectView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var host = ""
    @State private var port = "8765"
    @State private var token = ""

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Text("Manual Connect")
                        .font(Theme.Fonts.body.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    // Balance spacer
                    Color.clear.frame(width: 24, height: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)

                // Server section
                VStack(alignment: .leading, spacing: 20) {
                    Text("SERVER")
                        .font(Theme.Fonts.caption.weight(.medium))
                        .foregroundColor(Theme.Colors.accent)
                        .tracking(2)

                    ThemedTextField(label: "IP Address", text: $host, placeholder: "192.168.1.100", keyboard: .decimalPad)
                    ThemedTextField(label: "Port", text: $port, placeholder: "8765", keyboard: .numberPad)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)

                // Auth section
                VStack(alignment: .leading, spacing: 20) {
                    Text("AUTHENTICATION")
                        .font(Theme.Fonts.caption.weight(.medium))
                        .foregroundColor(Theme.Colors.accent)
                        .tracking(2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Token")
                            .font(Theme.Fonts.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                        TextField("Paste token here...", text: $token)
                            .font(Theme.Fonts.body)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .background(Theme.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radii.input)
                                    .stroke(Theme.Colors.surfaceLight, lineWidth: 1.5)
                            )
                            .cornerRadius(Theme.Radii.input)
                        Text("One-time use \u{00B7} Expires after connection")
                            .font(Theme.Fonts.captionSmall)
                            .foregroundColor(Theme.Colors.textMuted)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)

                // Connect button
                VStack(spacing: 16) {
                    Button(action: {
                        guard let portNum = Int(port) else { return }
                        connectionManager.connect(host: host, port: portNum, token: token)
                        dismiss()
                    }) {
                        Text("Connect")
                            .font(Theme.Fonts.body.weight(.semibold))
                            .foregroundColor(Theme.Colors.background)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(host.isEmpty || token.isEmpty ? Theme.Colors.accent.opacity(0.4) : Theme.Colors.accent)
                            .cornerRadius(Theme.Radii.button)
                    }
                    .disabled(host.isEmpty || token.isEmpty)

                    // Security note
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textMuted)
                        Text("TLS encrypted \u{00B7} LAN connection")
                            .font(Theme.Fonts.captionSmall)
                            .foregroundColor(Theme.Colors.textMuted)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)

                Spacer()
            }
        }
        .presentationBackground(Theme.Colors.background)
    }
}

// MARK: - Themed Text Field

private struct ThemedTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textTertiary)
            TextField(placeholder, text: $text)
                .font(Theme.Fonts.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radii.input)
                        .stroke(Theme.Colors.surfaceLight, lineWidth: 1.5)
                )
                .cornerRadius(Theme.Radii.input)
        }
    }
}
```

- [ ] **Step 2: Build and screenshot**

Build, install, launch app. Navigate to Manual Connect screen (may need to tap "Connect Manually" on connection screen). Screenshot and verify: dark background, cyan section headers, dark input fields, styled button.

- [ ] **Step 3: Commit**

```bash
git add ios/BashMirror/BashMirror/Views/ManualConnectView.swift
git commit -m "feat(ios): redesign manual connect screen with dark theme"
```

---

## Task 4: Redesign TerminalContainerView + SessionTabBar

**Files:**
- Modify: `ios/BashMirror/BashMirror/Views/TerminalContainerView.swift`

Redesign the session tab bar with styled session pills (cyan active, gray inactive), close buttons, and the right-side action buttons (sessions icon, new session, keyboard toggle). Update the container background.

- [ ] **Step 1: Replace entire TerminalContainerView.swift**

```swift
import SwiftUI

struct TerminalContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showKeyboard = true

    var body: some View {
        VStack(spacing: 0) {
            if connectionManager.sessions.count > 0 {
                SessionTabBar(showKeyboard: $showKeyboard)
                    .padding(.top, safeAreaTop)
            }

            if let activeSession = connectionManager.activeSessionId {
                TerminalView(sessionId: activeSession)
                    .id(activeSession)
            } else {
                Theme.Colors.background
                    .overlay(
                        Text("No active session")
                            .foregroundColor(Theme.Colors.textTertiary)
                            .font(Theme.Fonts.body)
                    )
            }

            if showKeyboard {
                FullKeyboardView { key in
                    if let session = connectionManager.activeSessionId {
                        connectionManager.sendInput(session: session, data: key)
                    }
                }
                .padding(.bottom, safeAreaBottom)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
    }
}

struct SessionTabBar: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Binding var showKeyboard: Bool

    var body: some View {
        HStack(spacing: 4) {
            // Session tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(connectionManager.sessions, id: \.self) { sessionId in
                        let isActive = connectionManager.activeSessionId == sessionId

                        Button(action: {
                            connectionManager.activeSessionId = sessionId
                        }) {
                            HStack(spacing: 4) {
                                Text(sessionId.prefix(6))
                                    .font(Theme.Fonts.captionSmall.weight(.semibold))
                                    .foregroundColor(isActive ? Theme.Colors.accent : Theme.Colors.textSecondary)

                                Button(action: {
                                    connectionManager.closeSession(sessionId)
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(isActive ? Theme.Colors.accent : Theme.Colors.textTertiary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isActive
                                    ? Theme.Colors.accent.opacity(0.12)
                                    : Theme.Colors.surfaceLight.opacity(0.5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isActive ? Theme.Colors.accentBorder : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                            .cornerRadius(8)
                        }
                    }
                }
            }

            Spacer()

            // Keyboard toggle
            Button(action: { showKeyboard.toggle() }) {
                Image(systemName: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 14))
                    .foregroundColor(showKeyboard ? Theme.Colors.textSecondary : Theme.Colors.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        showKeyboard
                            ? Theme.Colors.surfaceLight.opacity(0.5)
                            : Theme.Colors.accentDim
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(showKeyboard ? Color.clear : Theme.Colors.accentBorder, lineWidth: 1)
                    )
                    .cornerRadius(8)
            }

            // New session
            Button(action: { connectionManager.createSession() }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.Colors.success)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.success.opacity(0.15))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.Colors.background)
    }
}
```

- [ ] **Step 2: Build and screenshot**

This screen requires a connected session to display, so visual verification may be limited to checking the build succeeds. If the Rust server is running, you could connect and verify the tab bar styling.

- [ ] **Step 3: Commit**

```bash
git add ios/BashMirror/BashMirror/Views/TerminalContainerView.swift
git commit -m "feat(ios): redesign session tab bar with themed pills and keyboard toggle"
```

---

## Task 5: Redesign FullKeyboardView with Combined Key Shortcuts

**Files:**
- Modify: `ios/BashMirror/BashMirror/Views/Keyboard/FullKeyboardView.swift`

Restyle the keyboard with the new dark theme AND add a scrollable combined-key shortcuts bar at the top. The shortcuts bar provides one-tap access to common Ctrl combinations (Ctrl+C, Ctrl+Z, Ctrl+D, Ctrl+L, Ctrl+A, Ctrl+R, Ctrl+U, Ctrl+E). This replaces the two-tap Ctrl→letter workflow for the most common operations.

- [ ] **Step 1: Replace entire FullKeyboardView.swift**

```swift
import SwiftUI

// MARK: - Combined Key Shortcut Model

struct KeyCombo: Identifiable {
    let id = UUID()
    let label: String      // Display label: "^C"
    let sublabel: String   // Description: "Kill"
    let value: String      // ASCII value to send
}

// MARK: - Shortcuts Bar

struct ShortcutsBar: View {
    let onKey: (String) -> Void

    private let combos: [KeyCombo] = [
        KeyCombo(label: "^C", sublabel: "Kill", value: "\u{03}"),
        KeyCombo(label: "^Z", sublabel: "Stop", value: "\u{1a}"),
        KeyCombo(label: "^D", sublabel: "EOF", value: "\u{04}"),
        KeyCombo(label: "^L", sublabel: "Clear", value: "\u{0c}"),
        KeyCombo(label: "^A", sublabel: "Home", value: "\u{01}"),
        KeyCombo(label: "^E", sublabel: "End", value: "\u{05}"),
        KeyCombo(label: "^R", sublabel: "Search", value: "\u{12}"),
        KeyCombo(label: "^U", sublabel: "Kill ln", value: "\u{15}"),
        KeyCombo(label: "^W", sublabel: "Del wd", value: "\u{17}"),
        KeyCombo(label: "^K", sublabel: "Cut", value: "\u{0b}"),
        KeyCombo(label: "^Y", sublabel: "Paste", value: "\u{19}"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(combos) { combo in
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onKey(combo.value)
                    }) {
                        VStack(spacing: 1) {
                            Text(combo.label)
                                .font(Theme.Fonts.captionSmall.weight(.bold))
                                .foregroundColor(Theme.Colors.warning)
                            Text(combo.sublabel)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .frame(width: 52, height: 36)
                        .background(Theme.Colors.warning.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radii.key)
                                .stroke(Theme.Colors.warning.opacity(0.2), lineWidth: 1)
                        )
                        .cornerRadius(Theme.Radii.key)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - Full Keyboard

struct FullKeyboardView: View {
    let onKey: (String) -> Void

    @State private var isShiftActive = false
    @State private var isCtrlActive = false
    @State private var showNumbers = false

    private let topRow = ["Tab", "Ctrl", "~", "`", "|", "/", "-", "=", "[", "]"]
    private let row1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    private let row2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"]
    private let row3 = ["z", "x", "c", "v", "b", "n", "m", ","]
    private let numberRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    var body: some View {
        VStack(spacing: 3) {
            // Combined key shortcuts bar (always visible, scrollable)
            ShortcutsBar(onKey: onKey)
                .padding(.bottom, 2)

            // Top row: specials or numbers
            if showNumbers {
                keyRow(numberRow)
            } else {
                HStack(spacing: 3) {
                    ForEach(topRow, id: \.self) { key in
                        KeyButton(
                            label: key,
                            style: key == "Ctrl" && isCtrlActive ? .ctrl : (key == "Tab" || key == "Ctrl" ? .special : .normal)
                        ) {
                            handleSpecialKey(key)
                        }
                    }
                }
            }

            // Letter rows
            keyRow(row1)

            HStack(spacing: 3) {
                ForEach(row2, id: \.self) { key in
                    KeyButton(label: displayKey(key)) { sendKey(key) }
                }
            }
            .padding(.horizontal, 12)

            // Row 3 with shift and backspace
            HStack(spacing: 3) {
                KeyButton(label: "\u{21E7}", width: 42, style: isShiftActive ? .accent : .special) {
                    isShiftActive.toggle()
                }
                ForEach(row3, id: \.self) { key in
                    KeyButton(label: displayKey(key)) { sendKey(key) }
                }
                KeyButton(label: "\u{232B}", width: 42, style: .normal) { onKey("\u{7f}") }
            }

            // Bottom row
            HStack(spacing: 3) {
                KeyButton(label: "123", width: 42, style: .special) { showNumbers.toggle() }
                KeyButton(label: "Esc", width: 38, style: .special) { onKey("\u{1b}") }

                KeyButton(label: "\u{2190}", width: 30, style: .arrow) { onKey("\u{1b}[D") }
                KeyButton(label: "\u{2193}", width: 30, style: .arrow) { onKey("\u{1b}[B") }
                KeyButton(label: "\u{2191}", width: 30, style: .arrow) { onKey("\u{1b}[A") }
                KeyButton(label: "\u{2192}", width: 30, style: .arrow) { onKey("\u{1b}[C") }

                // Spacebar
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onKey(" ")
                }) {
                    Text("space")
                        .font(Theme.Fonts.captionSmall)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Theme.Colors.keyBackground)
                        .cornerRadius(Theme.Radii.key)
                }

                KeyButton(label: "\u{21B5}", width: 50, style: .enter) { onKey("\r") }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Theme.Colors.keyboardBackground)
        .overlay(
            Rectangle()
                .fill(Theme.Colors.keyboardBorder)
                .frame(height: 1),
            alignment: .top
        )
    }

    @ViewBuilder
    private func keyRow(_ keys: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                KeyButton(label: displayKey(key)) { sendKey(key) }
            }
        }
    }

    private func displayKey(_ key: String) -> String {
        if isShiftActive && key.count == 1 && key.first!.isLetter {
            return key.uppercased()
        }
        return key
    }

    private func sendKey(_ key: String) {
        var output = key
        if isShiftActive && key.count == 1 && key.first!.isLetter {
            output = key.uppercased()
            isShiftActive = false
        }
        if isCtrlActive && key.count == 1 {
            let char = key.lowercased().first!
            if let asciiValue = char.asciiValue, asciiValue >= 97, asciiValue <= 122 {
                output = String(Character(UnicodeScalar(asciiValue - 96)))
            }
            isCtrlActive = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onKey(output)
    }

    private func handleSpecialKey(_ key: String) {
        switch key {
        case "Tab": onKey("\t")
        case "Ctrl": isCtrlActive.toggle()
        default: sendKey(key)
        }
    }
}

// MARK: - Key Button

enum KeyStyle {
    case normal, special, accent, ctrl, arrow, enter
}

struct KeyButton: View {
    let label: String
    var width: CGFloat? = nil
    var style: KeyStyle = .normal
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(label)
                .font(Theme.Fonts.bodySmall)
                .foregroundColor(foregroundColor)
                .frame(minWidth: width, minHeight: 36)
                .frame(maxWidth: width != nil ? width : .infinity)
                .background(backgroundColor)
                .overlay(borderOverlay)
                .cornerRadius(Theme.Radii.key)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .normal: return Theme.Colors.textPrimary
        case .special: return Theme.Colors.textSecondary
        case .accent: return Theme.Colors.accent
        case .ctrl: return Theme.Colors.warning
        case .arrow: return Theme.Colors.textTertiary
        case .enter: return Theme.Colors.accent
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .ctrl: return Theme.Colors.warning.opacity(0.15)
        case .accent: return Theme.Colors.accent.opacity(0.1)
        case .enter: return Theme.Colors.accent.opacity(0.08)
        default: return Theme.Colors.keyBackground
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch style {
        case .accent:
            RoundedRectangle(cornerRadius: Theme.Radii.key)
                .stroke(Theme.Colors.accentBorder, lineWidth: 1)
        case .enter:
            RoundedRectangle(cornerRadius: Theme.Radii.key)
                .stroke(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
        default:
            EmptyView()
        }
    }
}
```

The key changes:
- **`ShortcutsBar`**: A horizontally scrollable bar of combined key shortcuts (^C Kill, ^Z Stop, ^D EOF, ^L Clear, ^A Home, ^E End, ^R Search, ^U Kill ln, ^W Del wd, ^K Cut, ^Y Paste)
- Each shortcut shows the key combo and a description label
- Orange-tinted styling distinguishes them from regular keys
- Medium haptic feedback (stronger than regular keys) for shortcuts
- The Ctrl key still works for manual Ctrl+letter combos — shortcuts are a fast lane
- `CommandPadView.swift` is no longer needed as a separate view (shortcuts are integrated)

- [ ] **Step 2: Build and screenshot**

Build and verify. The keyboard won't be visible on the connection screen, but compilation should succeed.

- [ ] **Step 3: Commit**

```bash
git add ios/BashMirror/BashMirror/Views/Keyboard/FullKeyboardView.swift
git commit -m "feat(ios): redesign keyboard with dark theme, styled keys, and combined shortcuts bar"
```

---

## Task 6: Final Integration Build + Visual Verification

**Files:** None (verification only)

- [ ] **Step 1: Clean build**

```bash
xcodebuild -project ios/BashMirror/BashMirror.xcodeproj -scheme BashMirror \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" \
  -derivedDataPath /tmp/bash-mirror-build clean build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Install and screenshot connection screen**

```bash
SIM_ID=4229443C-791F-4C25-9E07-AC8248BC68FF
xcrun simctl install $SIM_ID /tmp/bash-mirror-build/Build/Products/Debug-iphonesimulator/BashMirror.app
xcrun simctl terminate $SIM_ID com.nguyenvanhuu.bashmirror 2>/dev/null
xcrun simctl launch $SIM_ID com.nguyenvanhuu.bashmirror
sleep 3
xcrun simctl io $SIM_ID screenshot /tmp/bash-mirror-screen-final.png
```
Read screenshot. Compare with Paper design "1. Connection Screen". Check:
- [ ] Dark OLED background (#0A0A0F)
- [ ] Cyan "REMOTE TERMINAL" subtitle with letter spacing
- [ ] Large "bash-mirror" title
- [ ] Scanner area with rounded corners and border
- [ ] Status indicator dot
- [ ] Two styled CTA buttons
- [ ] Footer text

- [ ] **Step 3: Verify Manual Connect screen**

Use `xcrun simctl` UI automation or manually navigate. Screenshot and compare with Paper design "2. Manual Connect".

- [ ] **Step 4: Fix any visual discrepancies**

If the screenshot doesn't match the Paper designs, adjust colors, spacing, or font sizes in the relevant files and re-build/screenshot until it matches.

- [ ] **Step 5: Final commit if any fixes were made**

```bash
git add -A ios/BashMirror/BashMirror/
git commit -m "fix(ios): polish UI to match Paper designs"
```

---

## Summary

| Task | What | Files Changed |
|------|------|---------------|
| 1 | Create Theme.swift — design tokens + reusable view modifiers | +Theme.swift |
| 2 | Redesign connection screen | BashMirrorApp.swift |
| 3 | Redesign manual connect form (uses ThemedInputModifier) | ManualConnectView.swift |
| 4 | Redesign session tab bar + keyboard toggle | TerminalContainerView.swift |
| 5 | Restyle keyboard + add combined key shortcuts bar (^C, ^Z, ^D, etc.) | FullKeyboardView.swift |
| 6 | Final build + visual verification | (none — verification) |

### Combined Key Shortcuts Available

| Shortcut | ASCII | Description |
|----------|-------|-------------|
| ^C | `\x03` | Kill process (SIGINT) |
| ^Z | `\x1a` | Suspend process (SIGTSTP) |
| ^D | `\x04` | EOF / logout |
| ^L | `\x0c` | Clear screen |
| ^A | `\x01` | Move cursor to line start |
| ^E | `\x05` | Move cursor to line end |
| ^R | `\x12` | Reverse search history |
| ^U | `\x15` | Kill line (before cursor) |
| ^W | `\x17` | Delete word (before cursor) |
| ^K | `\x0b` | Cut line (after cursor) |
| ^Y | `\x19` | Paste last killed text |
