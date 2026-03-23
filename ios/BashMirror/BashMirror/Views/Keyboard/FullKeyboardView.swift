import SwiftUI

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
        VStack(spacing: 2) {
            if showNumbers {
                keyRow(numberRow)
            } else {
                HStack(spacing: 2) {
                    ForEach(topRow, id: \.self) { key in
                        KeyButton(
                            label: key,
                            isHighlighted: key == "Ctrl" && isCtrlActive
                        ) {
                            handleSpecialKey(key)
                        }
                    }
                }
            }

            keyRow(row1)
            keyRow(row2)

            HStack(spacing: 2) {
                KeyButton(label: "⇧", width: 38, isHighlighted: isShiftActive) {
                    isShiftActive.toggle()
                }
                ForEach(row3, id: \.self) { key in
                    KeyButton(label: displayKey(key)) { sendKey(key) }
                }
                KeyButton(label: "⌫", width: 38) { onKey("\u{7f}") }
            }

            HStack(spacing: 2) {
                KeyButton(label: "123", width: 38) { showNumbers.toggle() }
                KeyButton(label: "Esc", width: 38) { onKey("\u{1b}") }

                // Arrow keys inline
                KeyButton(label: "←", width: 28) { onKey("\u{1b}[D") }
                KeyButton(label: "↓", width: 28) { onKey("\u{1b}[B") }
                KeyButton(label: "↑", width: 28) { onKey("\u{1b}[A") }
                KeyButton(label: "→", width: 28) { onKey("\u{1b}[C") }

                // Spacebar
                Button(action: { onKey(" ") }) {
                    Text(" ")
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Color(UIColor.systemGray4))
                        .cornerRadius(4)
                }

                KeyButton(label: "↵", width: 46) { onKey("\r") }
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 3)
        .padding(.bottom, 2)
        .background(Color(UIColor.systemGray6))
    }

    @ViewBuilder
    private func keyRow(_ keys: [String]) -> some View {
        HStack(spacing: 2) {
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

struct KeyButton: View {
    let label: String
    var width: CGFloat? = nil
    var isHighlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .frame(minWidth: width, minHeight: 30)
                .frame(maxWidth: width != nil ? width : .infinity)
                .background(isHighlighted ? Color.orange.opacity(0.6) : Color(UIColor.systemGray4))
                .cornerRadius(4)
        }
    }
}
