import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: Tab = Self.initialTab
    /// NavigationStack path for the Matches tab; a single matchId pushes
    /// straight into ChatView (used by push routing and MatchMadeView's
    /// "Say hi").
    @State private var matchesPath: [String] = []

    enum Tab: Hashable { case tonight, matches, profile }

    /// Screenshot/debug hook: `-scene matches`/`-scene chat` land on Matches,
    /// `-scene profile` lands on Profile, everything else on Tonight.
    private static var initialTab: Tab {
        switch ProcessInfo.processInfo.arguments.sceneArgument {
        case "matches", "chat": return .matches
        case "profile": return .profile
        default: return .tonight
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            TonightView()
                .tabItem { Label("Tonight", systemImage: "moon.stars") }
                .tag(Tab.tonight)

            MatchesView(path: $matchesPath)
                .tabItem { Label("Matches", systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.matches)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(Theme.Color.accent)
        .onChange(of: selection) { _, _ in Haptics.select() }
        .onAppear { applyPendingRouteIfNeeded() }
        .onChange(of: appState.pendingRoute) { _, _ in applyPendingRouteIfNeeded() }
    }

    private func applyPendingRouteIfNeeded() {
        guard let route = appState.pendingRoute else { return }
        switch route {
        case .chat(let matchId):
            selection = .matches
            matchesPath = [matchId]
        case .matches:
            selection = .matches
        case .tonight:
            selection = .tonight
        }
        appState.clearPendingRoute()
    }
}
