import Foundation
import CryptoKit

class WebSocketService: NSObject, URLSessionWebSocketDelegate, ObservableObject {
    @Published var isConnected = false

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession!
    private var expectedFingerprint: String?
    var onMessage: ((ServerMessage) -> Void)?
    var onDisconnect: (() -> Void)?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect(url: URL, token: String, fingerprint: String? = nil) {
        disconnect()

        expectedFingerprint = fingerprint
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        // Send auth as first message
        send(.auth(token: token))
        receiveLoop()
    }

    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        expectedFingerprint = nil
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

    // Trust self-signed certificates with fingerprint pinning
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // If no fingerprint provided, trust any cert (e.g. --no-tls fallback or manual connect without fingerprint)
        guard let expected = expectedFingerprint, !expected.isEmpty else {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // Extract server certificate and compute SHA-256 fingerprint
        if let certChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
           let serverCert = certChain.first {
            let certData = SecCertificateCopyData(serverCert) as Data
            let hash = SHA256.hash(data: certData)
            let fingerprint = hash.map { String(format: "%02x", $0) }.joined(separator: ":")

            if fingerprint == expected {
                print("[WS] Certificate fingerprint verified")
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                print("[WS] Certificate fingerprint mismatch!")
                print("[WS]   Expected: \(expected)")
                print("[WS]   Got:      \(fingerprint)")
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            print("[WS] Could not extract server certificate")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
