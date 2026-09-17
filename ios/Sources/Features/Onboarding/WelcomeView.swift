import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void

    /// Little "knock knock" greeting: the wordmark raps twice on appear.
    @State private var knockAngle: Double = 0

    /// Required before "Get started" is enabled (Guideline 1.2: users must
    /// agree to terms that state zero tolerance for objectionable content
    /// and abusive users before registering). Persisted so returning to
    /// Welcome mid-onboarding (e.g. backing out of phone entry) doesn't
    /// re-ask; reset only if the person signs out.
    @AppStorage("agreedToTermsV1") private var agreedToTerms = false

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: Theme.Space.lg) {
                Wordmark(size: 52)
                    .rotationEffect(.degrees(knockAngle), anchor: .bottomLeading)
                Text("Five-minute video dates.\nEvery night, 7 to 8.")
                    .font(Theme.Font.title3)
                    .fontWeight(.light)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineSpacing(4)
            }

            // A single Spacer here, the same weight as the one above,
            // instead of two stacked ones: two left the button pinned to
            // the very bottom with a bare 400-500pt gap of solid eggshell
            // above it (SPEC's App Store screenshot material reading as an
            // unfinished layout). One keeps the greeting and the CTA an
            // equal, calmer distance from the vertical center.
            Spacer()

            VStack(spacing: Theme.Space.md) {
                termsAgreement
                PrimaryButton(title: "Get started", isEnabled: agreedToTerms, action: onGetStarted)
                Text("No usernames. No passwords. Just your number.")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .navigationBarBackButtonHidden(true)
        .onAppear { playKnockKnock() }
    }

    /// Required consent row (Guideline 1.2). The checkbox is its own
    /// `Button`, separate from the sentence: a `Text` with Markdown links
    /// left un-nested inside any button keeps "Terms of Use" and "Privacy
    /// Policy" independently tappable (opens Safari) instead of the tap
    /// being swallowed by a wrapping button's gesture.
    private var termsAgreement: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Button {
                agreedToTerms.toggle()
                Haptics.tap()
            } label: {
                Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(agreedToTerms ? Theme.Color.accent : Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Agree to Terms of Use and Privacy Policy")
            .accessibilityAddTraits(agreedToTerms ? [.isSelected] : [])

            Text("I agree to the [Terms of Use](\(Config.termsURL)) and [Privacy Policy](\(Config.privacyURL)). Knock Knock has zero tolerance for objectionable content or abusive behavior.")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Color.textSecondary)
                .tint(Theme.Color.text)
                .multilineTextAlignment(.leading)
        }
    }

    private func playKnockKnock() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            SoundEffects.play(.knock)
            for _ in 0..<2 {
                Haptics.tap()
                withAnimation(.spring(response: 0.10, dampingFraction: 0.45)) { knockAngle = 2.5 }
                try? await Task.sleep(nanoseconds: 110_000_000)
                withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) { knockAngle = 0 }
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
        }
    }
}

#Preview {
    NavigationStack { WelcomeView {} }
}
