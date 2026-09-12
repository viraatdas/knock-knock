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
            case .profileSetup:
                ProfileSetupFlow()
                    .transition(.opacity)
            case .home:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.standard, value: appState.phase)
        // The date flow (waiting/in-date/deciding/result) takes over full
        // screen above the tabs, for any DateFlow case but `.none`.
        .fullScreenCover(isPresented: dateFlowPresented) {
            DateFlowContainerView()
                .environmentObject(appState)
        }
    }

    private var dateFlowPresented: Binding<Bool> {
        Binding(
            get: { appState.dateFlow != .none },
            set: { presented in
                if !presented { appState.dismissDateFlow() }
            }
        )
    }
}

private struct LoadingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()
            Wordmark(size: 30)
            if appState.bootstrapUnreachable {
                VStack(spacing: Theme.Space.md) {
                    Text("Can't reach Knock Knock. Check your connection.")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                    PrimaryButton(title: "Try again") { appState.retryBootstrap() }
                        .frame(maxWidth: 200)
                }
                .padding(.horizontal, Theme.Space.xl)
            }
            Spacer()
        }
    }
}

/// Picks the right full-screen view for the current `DateFlow` case.
private struct DateFlowContainerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.dateFlow {
            case .none:
                EmptyView()
            case .waiting, .closed:
                LobbyView()
            case .inDate(let date):
                DateView(date: date)
            case .deciding(let date, let endReason):
                DecisionView(date: date, endReason: endReason, result: nil)
            case .result(let result, let date):
                switch result {
                case .matched(let match):
                    MatchMadeView(match: match, date: date)
                case .waiting, .passed:
                    DecisionView(date: date, endReason: nil, result: result)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
