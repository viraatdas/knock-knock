import SwiftUI

/// Full-screen "finding someone" lobby (SPEC §2.3). Init: `LobbyView()`.
/// Presented by RootView while `AppState.dateFlow` is `.waiting` or
/// `.closed`. A `matched` heartbeat response or a `date_matched` event (both
/// handled in AppState) swaps this out for `DateView`. Cancel calls
/// `AppState.cancelLooking()`.
///
/// When the window closes while waiting, `AppState` moves `dateFlow` to the
/// transient `.closed` case (not straight to `.none`) so this view has time
/// to actually show "Doors are closed for tonight." before the
/// fullScreenCover dismisses ~1.5s later on its own.
struct LobbyView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pulse = false

    private var doorsClosed: Bool {
        appState.sessionWindow?.isOpen == false
    }

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()

            // Larger than a typical status icon on purpose: this and its
            // companion enlargements on Decision/Match are what keep the
            // middle third of the screen from reading as a bare, unfinished
            // gap between the greeting and the pinned-bottom action (SPEC
            // §4 names this screen as App Store screenshot material).
            ZStack {
                Circle()
                    .fill(Theme.Color.bgGrouped)
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth))
                    .frame(width: 176, height: 176)
                    .scaleEffect(pulse && !doorsClosed ? 1.04 : 1.0)
                    .animation(Theme.Motion.pulse, value: pulse)
                Image(systemName: doorsClosed ? "moon.zzz" : "moon.stars")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.Color.text)
            }
            .onAppear { pulse = true }

            VStack(spacing: Theme.Space.sm) {
                if doorsClosed {
                    Text("Doors are closed for tonight.")
                        .font(Theme.Font.title3)
                        .foregroundStyle(Theme.Color.text)
                } else {
                    Text("Finding someone nearby\u{2026}")
                        .font(Theme.Font.title3)
                        .foregroundStyle(Theme.Color.text)
                    Text("Within 75 miles \u{00b7} people who match what you're looking for")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Space.xl)
                }
            }

            Spacer()

            TextLinkButton(title: doorsClosed ? "Back" : "Cancel", color: Theme.Color.textSecondary) {
                Task { await appState.cancelLooking() }
            }
            .padding(.bottom, Theme.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }
}
