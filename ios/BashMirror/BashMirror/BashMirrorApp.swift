import UIKit
import SwiftUI

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let connectionManager = ConnectionManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let rootView = ContentView()
            .environmentObject(connectionManager)
            .preferredColorScheme(.dark)

        let hosting = UIHostingController(rootView: rootView)
        // Remove container safe area so SwiftUI gets the full screen frame.
        // This is why .ignoresSafeArea() alone never worked.
        hosting.safeAreaRegions.remove(.container)

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = hosting
        window?.makeKeyAndVisible()
        return true
    }
}

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        ZStack {
            Color(hex: "1a1a2e").ignoresSafeArea()

            switch connectionManager.state {
            case .disconnected:
                ScannerContainerView()
            case .connecting:
                ProgressView("Connecting...")
                    .foregroundColor(.white)
            case .connected:
                TerminalContainerView()
            }
        }
    }
}

struct ScannerContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showManualEntry = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "1a1a2e").ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("bash-mirror")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text("Scan QR code from your Mac terminal")
                        .foregroundColor(.gray)

                    ScannerView { code in
                        connectionManager.connectFromQR(code)
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    Button("Enter manually") {
                        showManualEntry = true
                    }
                    .foregroundColor(.cyan)
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualConnectView()
            }
        }
    }
}
