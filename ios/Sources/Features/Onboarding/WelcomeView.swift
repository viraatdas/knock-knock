import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void

    /// Little "knock knock" greeting: the wordmark raps twice on appear.
    @State private var knockAngle: Double = 0

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
                PrimaryButton(title: "Get started", action: onGetStarted)
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
