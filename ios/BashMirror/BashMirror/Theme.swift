import SwiftUI

enum Theme {
    // MARK: - Colors
    enum Colors {
        static let background = Color(hex: "0A0A0F")
        static let surface = Color(hex: "111827")
        static let surfaceLight = Color(hex: "1E293B")
        static let terminal = Color(hex: "0D1117")

        static let textPrimary = Color(hex: "E2E8F0")
        static let textSecondary = Color(hex: "94A3B8")
        static let textTertiary = Color(hex: "64748B")
        static let textMuted = Color(hex: "475569")

        static let accent = Color(hex: "22D3EE")       // cyan
        static let accentDim = Color(hex: "22D3EE").opacity(0.12)
        static let accentBorder = Color(hex: "22D3EE").opacity(0.25)

        static let success = Color(hex: "10B981")       // green
        static let danger = Color(hex: "EF4444")         // red
        static let warning = Color(hex: "F97316")        // orange

        static let keyBackground = Color(hex: "1E293B")
        static let keyboardBackground = Color(hex: "111827")
        static let keyboardBorder = Color(hex: "1E293B")
    }

    // MARK: - Fonts
    enum Fonts {
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        static let title = mono(32, weight: .bold)
        static let subtitle = mono(13, weight: .medium)
        static let body = mono(15)
        static let bodySmall = mono(13)
        static let caption = mono(12)
        static let captionSmall = mono(11)
        static let micro = mono(10, weight: .medium)
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }

    // MARK: - Radii
    enum Radii {
        static let key: CGFloat = 6
        static let input: CGFloat = 10
        static let button: CGFloat = 12
        static let card: CGFloat = 14
        static let scanner: CGFloat = 24
    }
}

// MARK: - Reusable View Modifiers

struct ThemedInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.body)
            .foregroundColor(Theme.Colors.textPrimary)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radii.input)
                    .stroke(Theme.Colors.surfaceLight, lineWidth: 1.5)
            )
            .cornerRadius(Theme.Radii.input)
    }
}

struct ThemedPrimaryButtonModifier: ViewModifier {
    var isEnabled: Bool = true

    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.body.weight(.semibold))
            .foregroundColor(Theme.Colors.background)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.4))
            .cornerRadius(Theme.Radii.button)
    }
}

struct ThemedOutlineButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.body.weight(.medium))
            .foregroundColor(Theme.Colors.accent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radii.button)
                    .stroke(Theme.Colors.accentBorder, lineWidth: 1.5)
            )
    }
}

struct ThemedSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Fonts.caption.weight(.medium))
            .foregroundColor(Theme.Colors.accent)
            .tracking(2)
    }
}

extension View {
    func themedInput() -> some View { modifier(ThemedInputModifier()) }
    func themedPrimaryButton(isEnabled: Bool = true) -> some View { modifier(ThemedPrimaryButtonModifier(isEnabled: isEnabled)) }
    func themedOutlineButton() -> some View { modifier(ThemedOutlineButtonModifier()) }
}
