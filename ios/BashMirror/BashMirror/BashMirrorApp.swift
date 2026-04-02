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
            Theme.Colors.background.ignoresSafeArea()

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
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header branding
                VStack(spacing: 8) {
                    Text("REMOTE TERMINAL")
                        .font(Theme.Fonts.subtitle)
                        .foregroundColor(Theme.Colors.accent)
                        .tracking(4)

                    Text("bash-mirror")
                        .font(Theme.Fonts.title)
                        .foregroundColor(.white)

                    Text("Control your shell from anywhere")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .padding(.top, 4)
                }
                .padding(.top, 60)

                // Scanner area
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radii.scanner)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "0F1019"), Color(hex: "111827")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radii.scanner)
                                    .stroke(Theme.Colors.accentBorder, lineWidth: 2)
                            )

                        VStack(spacing: 16) {
                            Image(systemName: "chevron.right.square")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(Theme.Colors.accent)

                            Text("Point camera at\nQR code on terminal")
                                .font(Theme.Fonts.bodySmall)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .multilineTextAlignment(.center)
                        }

                        // Actual scanner overlay (invisible but functional)
                        ScannerView { code in
                            connectionManager.connectFromQR(code)
                        }
                        .opacity(0.01) // Hidden but active for camera capture
                    }
                    .frame(width: 280, height: 280)

                    // Status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.Colors.accent)
                            .frame(width: 8, height: 8)
                            .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 4)
                        Text("Camera ready")
                            .font(Theme.Fonts.captionSmall)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .padding(.top, 40)

                // CTAs
                VStack(spacing: 12) {
                    Button(action: {
                        // Scanner is always active above; this is a visual affordance
                    }) {
                        Text("Scan QR Code")
                            .font(Theme.Fonts.body.weight(.semibold))
                            .foregroundColor(Theme.Colors.background)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.Colors.accent)
                            .cornerRadius(Theme.Radii.button)
                    }

                    Button(action: { showManualEntry = true }) {
                        Text("Connect Manually")
                            .font(Theme.Fonts.body.weight(.medium))
                            .foregroundColor(Theme.Colors.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radii.button)
                                    .stroke(Theme.Colors.accentBorder, lineWidth: 1.5)
                            )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)

                Spacer()

                // Footer
                VStack(spacing: 4) {
                    Text("Secured with one-time tokens")
                        .font(Theme.Fonts.captionSmall)
                        .foregroundColor(Theme.Colors.textMuted)
                    Text("v0.1.0 \u{00B7} LAN only")
                        .font(Theme.Fonts.captionSmall)
                        .foregroundColor(Color(hex: "334155"))
                }
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualConnectView()
        }
    }
}
