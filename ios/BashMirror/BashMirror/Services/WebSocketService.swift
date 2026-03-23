import Foundation

class WebSocketService: NSObject, URLSessionWebSocketDelegate, ObservableObject {
    @Published var isConnected = false

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession!
    var onMessage: ((ServerMessage) -> Void)?
    var onDisconnect: (() -> Void)?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect(url: URL, token: String) {
        disconnect()

        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        // Send auth as first message
        send(.auth(token: token))
        receiveLoop()
    }

    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        DispatchQueue.main.async { self.isConnected = false }
    }

    func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else {
            print("[WS] Failed to encode message")
            return
        }

        print("[WS] Sending: \(text.prefix(200))")
        webSocket?.send(.string(text)) { error in
            if let error = error {
                print("[WS] Send error: \(error)")
            }
        }
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(.string(let text)):
                // Log non-output messages (output is too verbose)
                if !text.contains("\"Output\"") {
                    print("[WS] Received: \(text.prefix(200))")
                } else {
                    print("[WS] Received Output (\(text.count) bytes)")
                }
                if let data = text.data(using: .utf8),
                   let msg = try? JSONDecoder().decode(ServerMessage.self, from: data) {
                    DispatchQueue.main.async { self?.onMessage?(msg) }
                } else {
                    print("[WS] Failed to decode: \(text.prefix(200))")
                }
            case .failure(let error):
                print("[WS] Receive error: \(error)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.onDisconnect?()
                }
                return
            default:
                break
            }
            self?.receiveLoop()
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        print("[WS] Connected")
        DispatchQueue.main.async { self.isConnected = true }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        print("[WS] Closed: \(closeCode)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.onDisconnect?()
        }
    }

    // Trust self-signed certificates
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            // TODO: Pin cert fingerprint from QR payload
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
