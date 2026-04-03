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
                        .frame(width: 52, height: 40)
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
    private let row3 = ["z", "x", "c", "v", "b", "n", "m", ",", "."]
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
                        .frame(maxWidth: .infinity, minHeight: 40)
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
                .frame(minWidth: width, minHeight: 40)
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
