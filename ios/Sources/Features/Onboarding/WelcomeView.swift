import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: Theme.Space.md) {
                Wordmark(size: 44)
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
    }
}

#Preview {
    NavigationStack { WelcomeView {} }
}
