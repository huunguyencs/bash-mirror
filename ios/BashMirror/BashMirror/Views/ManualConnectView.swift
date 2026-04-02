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
