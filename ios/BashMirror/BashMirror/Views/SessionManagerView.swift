import SwiftUI

struct SessionManagerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss

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
                    Text("Sessions")
                        .font(Theme.Fonts.body.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 24, height: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Session list
                        sessionList
                            .padding(.top, 24)

                        // Connection info
                        connectionInfo
                            .padding(.top, 24)

                        // Action buttons
                        actionButtons
                            .padding(.top, 24)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .presentationBackground(Theme.Colors.background)
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 10) {
            ForEach(connectionManager.sessions, id: \.self) { sessionId in
                let isActive = connectionManager.activeSessionId == sessionId

                Button(action: {
                    connectionManager.activeSessionId = sessionId
                    dismiss()
                }) {
                    HStack(spacing: 14) {
                        // Terminal icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isActive ? Theme.Colors.accent.opacity(0.1) : Theme.Colors.surfaceLight.opacity(0.3))
                                .frame(width: 40, height: 40)
                            Image(systemName: "chevron.right.square")
                                .font(.system(size: 18))
                                .foregroundColor(isActive ? Theme.Colors.accent : Theme.Colors.textTertiary)
                        }

                        // Session info
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(sessionId.prefix(6))
                                    .font(Theme.Fonts.bodySmall.weight(.semibold))
                                    .foregroundColor(isActive ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)

                                Text(isActive ? "ACTIVE" : "IDLE")
                                    .font(Theme.Fonts.micro)
                                    .foregroundColor(isActive ? Theme.Colors.success : Theme.Colors.textTertiary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        isActive
                                            ? Theme.Colors.success.opacity(0.15)
                                            : Theme.Colors.surfaceLight.opacity(0.5)
                                    )
                                    .cornerRadius(4)
                            }

                            Text("/bin/zsh")
                                .font(Theme.Fonts.captionSmall)
                                .foregroundColor(Theme.Colors.textMuted)
                        }

                        Spacer()

                        // More menu / close
                        Button(action: {
                            connectionManager.closeSession(sessionId)
                        }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.Colors.textMuted)
                        }
                    }
                    .padding(16)
                    .background(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radii.card)
                            .stroke(
                                isActive ? Theme.Colors.accentBorder : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    .cornerRadius(Theme.Radii.card)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Connection Info

    private var connectionInfo: some View {
        VStack(alignment: .leading, spacing: 16) {
            ThemedSectionHeader(title: "CONNECTION")
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                infoRow(label: "Host", value: connectionManager.connectedHost)
                infoDivider
                infoRow(label: "Port", value: "\(connectionManager.connectedPort)")
                infoDivider
                HStack {
                    Text("Status")
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.Colors.success)
                            .frame(width: 6, height: 6)
                            .shadow(color: Theme.Colors.success.opacity(0.5), radius: 3)
                        Text("Connected")
                            .font(Theme.Fonts.bodySmall)
                            .foregroundColor(Theme.Colors.success)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                infoDivider
                infoRow(label: "Uptime", value: uptimeString)
                infoDivider
                infoRow(label: "TLS", value: connectionManager.useTLS ? "Self-signed" : "Disabled", valueColor: Theme.Colors.accent)
            }
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.Radii.card)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: { connectionManager.createSession() }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                    Text("New Session")
                        .font(Theme.Fonts.bodySmall.weight(.medium))
                }
                .foregroundColor(Theme.Colors.success)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.Colors.success.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radii.button)
                        .stroke(Theme.Colors.success.opacity(0.25), lineWidth: 1.5)
                )
                .cornerRadius(Theme.Radii.button)
            }

            Button(action: {
                connectionManager.disconnect()
                dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .medium))
                    Text("Disconnect")
                        .font(Theme.Fonts.bodySmall.weight(.medium))
                }
                .foregroundColor(Theme.Colors.danger)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.Colors.danger.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radii.button)
                        .stroke(Theme.Colors.danger.opacity(0.2), lineWidth: 1.5)
                )
                .cornerRadius(Theme.Radii.button)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String, valueColor: Color = Theme.Colors.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.Fonts.bodySmall)
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var infoDivider: some View {
        Rectangle()
            .fill(Theme.Colors.surfaceLight)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private var uptimeString: String {
        guard let connectedAt = connectionManager.connectedAt else { return "—" }
        let interval = Date().timeIntervalSince(connectedAt)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
