import SwiftUI

/// "About" row on the Profile tab (SPEC §2.3). A small, non-scrolling sheet:
/// wordmark, one line describing the product, the app version (short version
/// + build number, unlike the Profile row's short version alone), and a link
/// to the source on GitHub.
struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Capsule()
                .fill(Theme.Color.hairline)
                .frame(width: 36, height: 4)
                .padding(.top, Theme.Space.sm)

            Wordmark(size: 28)
                .padding(.top, Theme.Space.md)

            Text("Five-minute video dates. Every night, 7 to 8 PM Pacific.")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.xl)

            Text(Config.fullVersion)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Color.textSecondary)

            Button {
                guard let url = URL(string: "https://github.com/viraatdas/knock-knock") else { return }
                UIApplication.shared.open(url)
            } label: {
                Text("Open source on GitHub")
                    .font(Theme.Font.buttonSmall)
                    .foregroundStyle(Theme.Color.text)
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.sm)
                    .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, Theme.Space.xs)

            Spacer(minLength: Theme.Space.lg)
        }
        .padding(.bottom, Theme.Space.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.Color.bg)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
    }
}
