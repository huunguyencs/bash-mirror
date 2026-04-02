import Foundation
import Combine

enum ConnectionState {
    case disconnected
    case connecting
    case connected
}

class ConnectionManager: ObservableObject {
    @Published var state: ConnectionState = .disconnected
    @Published var sessions: [String] = []
    @Published var activeSessionId: String?
    @Published var errorMessage: String?

    let webSocket = WebSocketService()
    private var terminalOutputHandlers: [String: (String) -> Void] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        webSocket.onMessage = { [weak self] msg in
            self?.handleMessage(msg)
        }
        webSocket.onDisconnect = { [weak self] in
            self?.state = .disconnected
            self?.sessions = []
            self?.activeSessionId = nil
        }
    }

    func connectFromQR(_ qrString: String) {
        // Parse: bashmirror://192.168.1.100:8765?token=abc123&fp=aa:bb:cc:...
        guard let components = URLComponents(string: qrString),
              let host = components.host,
              let port = components.port,
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value
        else {
            errorMessage = "Invalid QR code"
            return
        }

        let fingerprint = components.queryItems?.first(where: { $0.name == "fp" })?.value

        connect(host: host, port: port, token: token, fingerprint: fingerprint)
    }

    func connect(host: String, port: Int, token: String, fingerprint: String? = nil) {
        state = .connecting

        // Use wss:// when fingerprint is present (TLS enabled), ws:// otherwise
        let scheme = (fingerprint != nil && !fingerprint!.isEmpty) ? "wss" : "ws"
        guard let url = URL(string: "\(scheme)://\(host):\(port)") else {
            errorMessage = "Invalid URL"
            state = .disconnected
            return
        }

        webSocket.connect(url: url, token: token, fingerprint: fingerprint)
    }

    func createSession() {
        webSocket.send(.sessionCreate)
    }

    func closeSession(_ sessionId: String) {
        webSocket.send(.sessionClose(session: sessionId))
    }

    func sendInput(session: String, data: String) {
        webSocket.send(.input(session: session, data: data))
    }

    func sendResize(session: String, cols: Int, rows: Int) {
        webSocket.send(.resize(session: session, cols: cols, rows: rows))
    }

    func registerTerminalOutput(session: String, handler: @escaping (String) -> Void) {
        terminalOutputHandlers[session] = handler
    }

    func unregisterTerminalOutput(session: String) {
        terminalOutputHandlers.removeValue(forKey: session)
    }

    func onTerminalReady(session: String) {
        // Terminal WebView is ready — can start sending output
    }

    private func handleMessage(_ msg: ServerMessage) {
        switch msg {
        case .authOk:
            state = .connected
            // Auto-create first session
            createSession()

        case .authFail(let reason):
            state = .disconnected
            errorMessage = "Auth failed: \(reason)"

        case .output(let session, let data):
            // Pass base64 directly to terminal — JS will decode it
            terminalOutputHandlers[session]?(data)

        case .sessionCreated(let session, _):
            sessions.append(session)
            if activeSessionId == nil {
                activeSessionId = session
            }

        case .sessionClosed(let session):
            sessions.removeAll { $0 == session }
            if activeSessionId == session {
                activeSessionId = sessions.first
            }

        case .sessionExited(let session, _):
            sessions.removeAll { $0 == session }
            if activeSessionId == session {
                activeSessionId = sessions.first
            }

        case .sessionList(let infos):
            sessions = infos.map(\.id)

        case .pong:
            break

        case .error(_, let message):
            print("[Connection] Error: \(message)")
        }
    }
}
