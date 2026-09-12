import SwiftUI

/// Matches tab (SPEC §2.3 "Matches tab"). Init: `MatchesView(path:
/// Binding<[String]>)` — the binding is a stack of matchIds so push routing
/// (a tapped notification, or "Say hi" from MatchMadeView via
/// `AppState.pendingRoute`, both handled in `MainTabView`) can jump straight
/// into a chat. Reads `AppState.matches`; a row tap pushes `ChatView(matchId:)`.
struct MatchesView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var path: [String]

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // A plain, large light title — same family as Tonight's
                // wordmark and Profile's name header — rather than the
                // system nav bar's bold default, per the design tokens.
                Text("Matches")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.top, Theme.Space.xl)
                    .padding(.bottom, Theme.Space.sm)

                Group {
                    if !appState.matchesLoaded {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if appState.matches.isEmpty {
                        EmptyStateView(message: "Matches from your dates land here.",
                                      systemImage: "bubble.left.and.bubble.right")
                    } else {
                        List(appState.matches) { match in
                            Button {
                                path.append(match.id)
                            } label: {
                                MatchRow(match: match)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.Color.bg)
                            .listRowSeparatorTint(Theme.Color.hairline)
                        }
                        .listStyle(.plain)
                        .refreshable { await appState.refreshMatches() }
                    }
                }
            }
            .background(Theme.Color.bg)
            .navigationBarHidden(true)
            .navigationDestination(for: String.self) { matchId in
                ChatView(matchId: matchId)
            }
        }
        .task { await appState.refreshMatches() }
    }
}

private struct MatchRow: View {
    let match: MatchSummary

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            PhotoAvatar(profile: match.partner, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.partner.displayName)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.text)
                Text(match.lastMessage?.body ?? "Say hi")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(relativeTime)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                if match.unreadCount > 0 {
                    Circle().fill(Theme.Color.warm).frame(width: 8, height: 8)
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private var relativeTime: String {
        let date = match.lastMessage?.createdAt ?? match.createdAt
        return date.formatted(.relative(presentation: .named))
    }
}
