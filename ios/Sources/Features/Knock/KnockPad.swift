import SwiftUI

/// A big circular ✊ target. Pressing it starts a call-style knock invitation so
/// the other phone rings through CallKit/Telecom even when the app is closed.
///
/// Brand: pure white background, thin near-black type, generous whitespace, one
/// restrained accent (the black knock target).
struct KnockPad: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Who we're knocking. Needs a stable user-id to relay over the WS.
    let user: User

    /// Drives the press-down scale + pulse-ring animation per tap.
    @State private var pressScale: CGFloat = 1.0
    @State private var ringPulse: Bool = false
    @State private var tapCount: Int = 0
    @State private var didStart = false

    private var title: String {
        let name = user.displayName ?? user.phone
        return name.isEmpty ? "Slide" : name
    }

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer().frame(height: Theme.Space.lg)

            VStack(spacing: Theme.Space.xs) {
                Text("Knock knock knock")
                    .uppercaseLabel()
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.text)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            tapTarget

            Text("Knock to ring them with a slide-to-pick-up.")
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
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 76))
                        .foregroundStyle(Theme.Color.onAccent)
                )
                .scaleEffect(pressScale)
        }
        .contentShape(Circle())
        .accessibilityLabel("Knock")
        .accessibilityHint("Starts a knock call")
        .onTapGesture { tap() }
    }

    private func tap() {
        guard !user.id.isEmpty, !didStart else { return }
        didStart = true
        tapCount += 1
        appState.startKnockCall(to: user)

        // Quick squish-and-release; toggle the ring to retrigger its animation.
        withAnimation(.easeOut(duration: 0.08)) { pressScale = 0.92 }
        withAnimation(.easeOut(duration: 0.22).delay(0.08)) { pressScale = 1.0 }
        ringPulse = false
        withAnimation { ringPulse = true }
    }
}
