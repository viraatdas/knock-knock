import SwiftUI

/// A big circular ✊ tap target. Each tap relays a knock to `user` and plays a
/// local sound + haptic so the caller feels the rhythm they're tapping.
///
/// Brand: pure white background, thin near-black type, generous whitespace, one
/// restrained accent (the black tap target).
struct KnockPad: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Who we're knocking. Needs a stable user-id to relay over the WS.
    let user: User

    /// Drives the press-down scale + pulse-ring animation per tap.
    @State private var pressScale: CGFloat = 1.0
    @State private var ringPulse: Bool = false
    @State private var tapCount: Int = 0

    private var title: String {
        let name = user.displayName ?? user.phone
        return name.isEmpty ? "Tap" : name
    }

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer().frame(height: Theme.Space.lg)

            VStack(spacing: Theme.Space.xs) {
                Text("Tapping")
                    .uppercaseLabel()
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.text)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            tapTarget

            Text("Tap a rhythm. They feel every tap.")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.xl)

            Spacer()

            TextLinkButton(title: "Done") {
                appState.resetKnockSession()
                dismiss()
            }
            .padding(.bottom, Theme.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg.ignoresSafeArea())
        .onAppear { KnockHaptics.shared.prepare() }
        .onDisappear { appState.resetKnockSession() }
    }

    private var tapTarget: some View {
        ZStack {
            // Expanding ring that fires on each tap, then fades.
            Circle()
                .stroke(Theme.Color.accent.opacity(ringPulse ? 0 : 0.4),
                        lineWidth: Theme.hairlineWidth)
                .frame(width: 200, height: 200)
                .scaleEffect(ringPulse ? 1.25 : 1.0)
                .animation(.easeOut(duration: 0.45), value: ringPulse)

            Circle()
                .fill(Theme.Color.accent)
                .frame(width: 200, height: 200)
                .overlay(
                    Text("✊")
                        .font(.system(size: 86))
                )
                .scaleEffect(pressScale)
        }
        .contentShape(Circle())
        .accessibilityLabel("Tap")
        .accessibilityHint("Double tap to send a Tap")
        .onTapGesture { tap() }
    }

    private func tap() {
        guard !user.id.isEmpty else { return }
        tapCount += 1
        appState.sendKnockTap(to: user.id)

        // Quick squish-and-release; toggle the ring to retrigger its animation.
        withAnimation(.easeOut(duration: 0.08)) { pressScale = 0.92 }
        withAnimation(.easeOut(duration: 0.22).delay(0.08)) { pressScale = 1.0 }
        ringPulse = false
        withAnimation { ringPulse = true }
    }
}
