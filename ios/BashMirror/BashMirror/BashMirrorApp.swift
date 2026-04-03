import SwiftUI

@main
struct BashMirrorApp: App {
    @StateObject private var connectionManager = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .preferredColorScheme(.dark)
        }
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
    @State private var showScanner = false
    @State private var showError = false

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
                .padding(.top, 20)

                // Scanner area
                VStack(spacing: 10) {
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
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(Theme.Colors.accent)

                            Text("Tap Scan QR Code\nto open camera")
                                .font(Theme.Fonts.bodySmall)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: 200, height: 200)

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

                    // Auth error
                    if showError, let error = connectionManager.authError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.Colors.danger)
                            Text(error)
                                .font(Theme.Fonts.captionSmall)
                                .foregroundColor(Theme.Colors.danger)
                                .lineLimit(2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.danger.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radii.input)
                                .stroke(Theme.Colors.danger.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(Theme.Radii.input)
                        .padding(.horizontal, 32)
                        .onTapGesture {
                            connectionManager.authError = nil
                            showError = false
                        }
                    }
                }
                .padding(.top, 16)

                // CTAs
                VStack(spacing: 12) {
                    Button(action: { showScanner = true }) {
                        Text("Scan QR Code")
                            .font(Theme.Fonts.body.weight(.semibold))
                            .foregroundColor(Theme.Colors.background)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.Colors.accent)
                            .cornerRadius(Theme.Radii.button)
                    }

                    Button(action: { showManualEntry = true }) {
                        Text("Connect Manually")
                            .font(Theme.Fonts.body.weight(.medium))
                            .foregroundColor(Theme.Colors.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radii.button)
                                    .stroke(Theme.Colors.accentBorder, lineWidth: 1.5)
                            )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)

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
                .padding(.bottom, 16)
            }
        }
        .onChange(of: connectionManager.authError) {
            if connectionManager.authError != nil {
                showError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    showError = false
                    connectionManager.authError = nil
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerSheet(onScanned: { code in
                showScanner = false
                connectionManager.connectFromQR(code)
            }, onDismiss: {
                showScanner = false
            })
        }
        .sheet(isPresented: $showManualEntry) {
            ManualConnectView()
        }
    }
}

// MARK: - QR Scanner Sheet

struct QRScannerSheet: View {
    let onScanned: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Full-screen camera
            ScannerView(onScan: onScanned)
                .ignoresSafeArea()

            // Close button overlay
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(24)
                }
                Spacer()

                // Bottom hint
                Text("Point at QR code from terminal")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(Theme.Radii.button)
                    .padding(.bottom, 48)
            }
        }
        .background(Color.black)
    }
}
