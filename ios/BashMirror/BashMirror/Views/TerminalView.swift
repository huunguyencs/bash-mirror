import SwiftUI
import WebKit

// WKWebView subclass that suppresses the system keyboard and accessory bar
class NoKeyboardWebView: WKWebView {
    override var inputView: UIView? {
        return UIView()
    }
    override var inputAccessoryView: UIView? {
        return nil
    }
}

// Also suppress keyboard on all subviews (xterm.js creates hidden textareas)
extension UIView {
    @objc func _swizzledInputView() -> UIView? { return UIView() }
    @objc func _swizzledInputAccessoryView() -> UIView? { return nil }
}

private let swizzleOnce: Void = {
    // Find the WKContentView class and swizzle its input views
    if let wkContentViewClass = NSClassFromString("WKContentView") {
        let originalInputView = class_getInstanceMethod(wkContentViewClass, #selector(getter: UIResponder.inputView))
        let swizzledInputView = class_getInstanceMethod(UIView.self, #selector(UIView._swizzledInputView))
        if let orig = originalInputView, let swiz = swizzledInputView {
            method_exchangeImplementations(orig, swiz)
        }
        let originalAccessory = class_getInstanceMethod(wkContentViewClass, #selector(getter: UIResponder.inputAccessoryView))
        let swizzledAccessory = class_getInstanceMethod(UIView.self, #selector(UIView._swizzledInputAccessoryView))
        if let orig = originalAccessory, let swiz = swizzledAccessory {
            method_exchangeImplementations(orig, swiz)
        }
    }
}()

struct TerminalView: UIViewRepresentable {
    let sessionId: String
    @EnvironmentObject var connectionManager: ConnectionManager

    func makeUIView(context: Context) -> NoKeyboardWebView {
        // Suppress system keyboard on WKContentView
        _ = swizzleOnce

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        controller.add(context.coordinator, name: "terminalInput")
        controller.add(context.coordinator, name: "terminalResize")
        controller.add(context.coordinator, name: "terminalReady")

        config.userContentController = controller

        let webView = NoKeyboardWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.102, green: 0.102, blue: 0.180, alpha: 1) // #1a1a2e
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        if let htmlURL = Bundle.main.url(forResource: "terminal", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            print("[Terminal] ERROR: terminal.html not found in bundle!")
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: NoKeyboardWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionId: sessionId, connectionManager: connectionManager)
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        let sessionId: String
        let connectionManager: ConnectionManager
        weak var webView: WKWebView?
        private var isReady = false
        private var outputBuffer: [String] = []

        init(sessionId: String, connectionManager: ConnectionManager) {
            self.sessionId = sessionId
            self.connectionManager = connectionManager
            super.init()

            connectionManager.registerTerminalOutput(session: sessionId) { [weak self] b64Data in
                self?.writeOutput(b64Data)
            }
        }

        deinit {
            connectionManager.unregisterTerminalOutput(session: sessionId)
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "terminalInput":
                if let data = message.body as? String {
                    connectionManager.sendInput(session: sessionId, data: data)
                }
            case "terminalResize":
                if let json = message.body as? String,
                   let jsonData = json.data(using: .utf8),
                   let dims = try? JSONDecoder().decode(TermDims.self, from: jsonData) {
                    connectionManager.sendResize(session: sessionId, cols: dims.cols, rows: dims.rows)
                }
            case "terminalReady":
                print("[Terminal] xterm.js ready for session \(sessionId)")
                isReady = true
                for buffered in outputBuffer {
                    evalTermWrite(buffered)
                }
                outputBuffer.removeAll()
                connectionManager.onTerminalReady(session: sessionId)
            default:
                break
            }
        }

        func writeOutput(_ b64Data: String) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.isReady {
                    self.evalTermWrite(b64Data)
                } else {
                    self.outputBuffer.append(b64Data)
                }
            }
        }

        private func evalTermWrite(_ b64Data: String) {
            webView?.evaluateJavaScript("termWrite('\(b64Data)')") { _, error in
                if let error = error {
                    print("[Terminal] JS error: \(error)")
                }
            }
        }
    }
}
