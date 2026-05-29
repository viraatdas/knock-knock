import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: Tab = Self.initialTab

    enum Tab: Hashable { case calls, contacts, profile }

    /// Screenshot/debug hook to land on a specific tab.
    private static var initialTab: Tab {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-tabContacts") || args.contains("-uiPreviewContacts") { return .contacts }
        if args.contains("-tabProfile") { return .profile }
        return .calls
    }

    var body: some View {
        TabView(selection: $selection) {
            RecentsView()
                .tabItem {
                    Label("Calls", systemImage: "phone")
                }
                .tag(Tab.calls)

            ContactsView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2")
                }
                .tag(Tab.contacts)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(Tab.profile)
        }
        .tint(Theme.Color.accent)
    }
}
