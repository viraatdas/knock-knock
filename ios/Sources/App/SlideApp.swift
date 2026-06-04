import SwiftUI

@main
struct SlideApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Quiet, precise system chrome: white, near-black tint.
        configureAppearance()
        // Warm up the Taptic engine so the first haptic fires without latency.
        Haptics.prepareAll()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(Theme.Color.accent)
                .preferredColorScheme(.light) // design is white-first, no dark mode
                .task { await appState.bootstrap() }
        }
    }

    private func configureAppearance() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor.white
        tab.shadowColor = UIColor(white: 0xEC / 255.0, alpha: 1) // hairline
        let item = tab.stackedLayoutAppearance
        item.normal.titleTextAttributes = [
            .foregroundColor: UIColor(white: 0x6B / 255.0, alpha: 1),
            .font: UIFont.systemFont(ofSize: 10, weight: .regular)
        ]
        item.selected.titleTextAttributes = [
            .foregroundColor: UIColor(white: 0x0A / 255.0, alpha: 1),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        item.normal.iconColor = UIColor(white: 0x6B / 255.0, alpha: 1)
        item.selected.iconColor = UIColor(white: 0x0A / 255.0, alpha: 1)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = .white
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor(white: 0x0A / 255.0, alpha: 1)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}
