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
