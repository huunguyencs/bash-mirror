import SwiftUI

struct CommandPadView: View {
    let onKey: (String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Shortcut grid
            HStack(spacing: 6) {
                // Left column
                VStack(spacing: 4) {
                    ShortcutButton(label: "Esc") { onKey("\u{1b}") }
                    ShortcutButton(label: "^C", sublabel: "Kill") { onKey("\u{03}") }
                    ShortcutButton(label: "^Z", sublabel: "Stop") { onKey("\u{1a}") }
                    ShortcutButton(label: "^R", sublabel: "Search") { onKey("\u{12}") }
                }

                // Center: arrow keys
                VStack(spacing: 3) {
                    ArrowButton(symbol: "chevron.up") { onKey("\u{1b}[A") }
                    HStack(spacing: 3) {
                        ArrowButton(symbol: "chevron.left") { onKey("\u{1b}[D") }
                        ArrowButton(symbol: "chevron.down") { onKey("\u{1b}[B") }
                        ArrowButton(symbol: "chevron.right") { onKey("\u{1b}[C") }
                    }
                }
                .frame(maxWidth: .infinity)

                // Right column
                VStack(spacing: 4) {
                    ShortcutButton(label: "Tab") { onKey("\t") }
                    ShortcutButton(label: "^L", sublabel: "Clear") { onKey("\u{0c}") }
                    ShortcutButton(label: "^D", sublabel: "EOF") { onKey("\u{04}") }
                    ShortcutButton(label: "^A", sublabel: "Home") { onKey("\u{01}") }
                }
            }
            .padding(.horizontal, 6)

            // Bottom row: common commands
            HStack(spacing: 4) {
                QuickCmdButton(label: "↵") { onKey("\r") }
                QuickCmdButton(label: "⌫") { onKey("\u{7f}") }
                QuickCmdButton(label: "Space") { onKey(" ") }
                QuickCmdButton(label: "^E End") { onKey("\u{05}") }
                QuickCmdButton(label: "^U Kill ln") { onKey("\u{15}") }
            }
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 6)
        .padding(.bottom, 16) // home indicator space
        .background(Color(UIColor.systemGray6))
    }
}

struct ShortcutButton: View {
    let label: String
    var sublabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                if let sublabel = sublabel {
                    Text(sublabel)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 56, height: 38)
            .background(Color(UIColor.systemGray4))
            .cornerRadius(6)
        }
    }
}

struct ArrowButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Color(UIColor.systemGray4))
                .cornerRadius(6)
        }
    }
}

struct QuickCmdButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Color(UIColor.systemGray4))
                .cornerRadius(5)
        }
    }
}
