import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void

    /// Little "knock knock" greeting: the wordmark raps twice on appear.
    @State private var knockAngle: Double = 0

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: Theme.Space.md) {
                Wordmark(size: 44)
                    .rotationEffect(.degrees(knockAngle), anchor: .bottomLeading)
                Text("Simple, beautiful calls\nwith the people you know.")
                    .font(Theme.Font.title3)
                    .fontWeight(.light)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineSpacing(4)
            }

            Spacer()
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
            for _ in 0..<2 {
                KnockHaptics.shared.knock()
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
