import SwiftUI

struct TerminalContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showKeyboard = true

    var body: some View {
        VStack(spacing: 0) {
            // Session tab bar
            if connectionManager.sessions.count > 0 {
                SessionTabBar(showKeyboard: $showKeyboard)
            }

            // Terminal fills remaining space
            if let activeSession = connectionManager.activeSessionId {
                TerminalView(sessionId: activeSession)
                    .id(activeSession)
            } else {
                Color(hex: "1a1a2e")
                    .overlay(
                        Text("No active session")
                            .foregroundColor(.gray)
                            .font(.system(.body, design: .monospaced))
                    )
            }

            // Keyboard
            if showKeyboard {
                FullKeyboardView { key in
                    if let session = connectionManager.activeSessionId {
                        connectionManager.sendInput(session: session, data: key)
                    }
                }
            }
        }
        .background(Color(hex: "1a1a2e"))
    }
}

struct SessionTabBar: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Binding var showKeyboard: Bool

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(connectionManager.sessions, id: \.self) { sessionId in
                        Button(action: {
                            connectionManager.activeSessionId = sessionId
                        }) {
                            HStack(spacing: 4) {
                                Text(sessionId.prefix(6))
                                    .font(.system(size: 11, design: .monospaced))

                                Button(action: {
                                    connectionManager.closeSession(sessionId)
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8))
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                connectionManager.activeSessionId == sessionId
                                    ? Color.cyan.opacity(0.3)
                                    : Color.gray.opacity(0.2)
                            )
                            .cornerRadius(5)
                        }
                        .foregroundColor(.white)
                    }
                }
            }

            Spacer()

            Button(action: { showKeyboard.toggle() }) {
                Image(systemName: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }

            Button(action: { connectionManager.createSession() }) {
                Image(systemName: "plus.rectangle")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(UIColor.systemGray5))
    }
}
