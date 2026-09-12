import SwiftUI

/// "It's a match" screen (SPEC §2.3). Init: `MatchMadeView(match:
/// MatchSummary, date: DateSession)`. Shown while `AppState.dateFlow ==
/// .result(.matched, _)`. "Say hi" hands off to Matches via
/// `AppState.openChat(matchId:)`; "Next date" re-enters the lobby; "Done for
/// tonight" clears the flow.
struct MatchMadeView: View {
    @EnvironmentObject private var appState: AppState
    let match: MatchSummary
    let date: DateSession

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()
            // Bigger than the usual list-row avatar so the middle of the
            // screen carries real visual weight instead of reading as bare
            // space between the greeting and the pinned-bottom actions.
            PhotoAvatar(profile: match.partner, size: 136)
            VStack(spacing: Theme.Space.sm) {
                Text("It's a match.")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text("You and \(match.partner.displayName) both want to keep talking.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: Theme.Space.md) {
                PrimaryButton(title: "Say hi") { appState.openChat(matchId: match.id) }
                HStack(spacing: Theme.Space.lg) {
                    TextLinkButton(title: "Next date", color: Theme.Color.textSecondary) {
                        appState.dismissDateFlow()
                        Task { await appState.startLookingForDate() }
                    }
                    TextLinkButton(title: "Done for tonight", color: Theme.Color.textSecondary) {
                        appState.dismissDateFlow()
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .onAppear {
            SoundEffects.play(.match)
            Haptics.success()
        }
    }
}
