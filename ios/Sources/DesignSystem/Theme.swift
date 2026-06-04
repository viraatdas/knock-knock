import SwiftUI

/// Slide design system — "quiet & precise".
/// White space + thin black type. No gradients, no heavy color, no decorative
/// shadows. All tokens come straight from AGENTS.md.
enum Theme {

    // MARK: Color tokens

    enum Color {
        /// #FFFFFF — every background.
        static let bg = SwiftUI.Color(hex: 0xFFFFFF)
        /// #FAFAFA — grouped sections.
        static let bgGrouped = SwiftUI.Color(hex: 0xFAFAFA)
        /// #0A0A0A — primary near-black text.
        static let text = SwiftUI.Color(hex: 0x0A0A0A)
        /// #6B7280 — secondary gray.
        static let textSecondary = SwiftUI.Color(hex: 0x6B7280)
        /// #ECECEC — 1px borders & dividers.
        static let hairline = SwiftUI.Color(hex: 0xECECEC)
        /// #0A0A0A — primary action / active toggles — pure black.
        static let accent = SwiftUI.Color(hex: 0x0A0A0A)
        /// #E5484D — end call / decline / log out — the ONLY red.
        static let danger = SwiftUI.Color(hex: 0xE5484D)

        /// On-black text/icon color (for filled accent buttons).
        static let onAccent = SwiftUI.Color.white
    }

    // MARK: Spacing — 8px grid

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: Radii — 12-16px subtle

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 14
        static let large: CGFloat = 16
        static let pill: CGFloat = 999
    }

    // MARK: Hairline

    static let hairlineWidth: CGFloat = 1
    static let iconStroke: CGFloat = 1.5

    // MARK: Motion — 150-200ms ease-out

    enum Motion {
        static let fast: Animation = .easeOut(duration: 0.15)
        static let standard: Animation = .easeOut(duration: 0.2)
        /// Gentle pulse for incoming calls (scale 1.0 -> 1.04).
        static let pulse: Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    }

    // MARK: Typography
    // Weights: Light (300) large headings, Regular (400) body,
    // Medium (500) only buttons / active states.

    enum Font {
        /// The "Slide" wordmark — always thin, tracking +0.04em.
        static func wordmark(_ size: CGFloat = 28) -> SwiftUI.Font {
            .system(size: size, weight: .light, design: .default)
        }

        static func displayLight(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .light, design: .default)
        }

        static let largeTitle = SwiftUI.Font.system(size: 34, weight: .light)
        static let title = SwiftUI.Font.system(size: 28, weight: .light)
        static let title2 = SwiftUI.Font.system(size: 22, weight: .light)
        static let title3 = SwiftUI.Font.system(size: 20, weight: .regular)
        static let body = SwiftUI.Font.system(size: 17, weight: .regular)
        static let callout = SwiftUI.Font.system(size: 16, weight: .regular)
        static let subheadline = SwiftUI.Font.system(size: 15, weight: .regular)
        static let footnote = SwiftUI.Font.system(size: 13, weight: .regular)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular)
        /// Medium 500 — only on buttons / active states.
        static let button = SwiftUI.Font.system(size: 17, weight: .medium)
        static let buttonSmall = SwiftUI.Font.system(size: 15, weight: .medium)
        /// Big digits for phone / OTP entry.
        static let bigDigits = SwiftUI.Font.system(size: 28, weight: .light).monospacedDigit()
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Letter spacing helper for uppercase labels

extension View {
    /// Generous letter-spacing (~0.02em) on small uppercase labels.
    func uppercaseLabel() -> some View {
        self
            .font(Theme.Font.caption)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Color.textSecondary)
    }

    /// Wordmark styling: thin, tracking +0.04em.
    func wordmarkStyle(_ size: CGFloat = 28) -> some View {
        self
            .font(Theme.Font.wordmark(size))
            .tracking(size * 0.04)
            .foregroundStyle(Theme.Color.text)
    }
}
