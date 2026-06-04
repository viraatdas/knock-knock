import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Theme.Color.bg.ignoresSafeArea()

            switch appState.phase {
            case .loading:
                LoadingView()
            case .onboarding:
                OnboardingFlow()
                    .transition(.opacity)
            case .needsName:
                NameStepView()
                    .transition(.opacity)
            case .home:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.standard, value: appState.phase)
        // Incoming-knock banner floats above the tabs (lightweight, not CallKit).
        .overlay(alignment: .top) {
            IncomingKnockOverlay()
                .environmentObject(appState)
        }
        // Active call takes over full screen, modal above the tabs.
        .fullScreenCover(item: $appState.activeCall) { call in
            CallContainerView(call: call)
                .environmentObject(appState)
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            Wordmark(size: 30)
            Spacer()
        }
    }
}

/// Decides between the incoming-call screen and the in-call screen.
struct CallContainerView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var call: ActiveCall

    var body: some View {
        Group {
            if call.direction == .incoming && call.status == .ringing {
                IncomingCallView(call: call)
            } else {
                InCallView(call: call)
            }
        }
        .preferredColorScheme(.light)
    }
}
