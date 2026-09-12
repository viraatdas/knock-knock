import SwiftUI

/// Decision screen (SPEC §2.3 "Decision"). Init: `DecisionView(date:
/// DateSession, endReason: String?, result: DecisionResult?)`.
/// - `result == nil`: the "Keep talking with X? / Pass" choice, shown while
///   `AppState.dateFlow == .deciding`. The buttons call
///   `AppState.decide(explore:)`.
/// - `result != nil`, only `.waiting` or `.passed` (`.matched` routes to
///   `MatchMadeView` instead — see RootView): the outcome copy, shown while
///   `AppState.dateFlow == .result`.
struct DecisionView: View {
    @EnvironmentObject private var appState: AppState
    let date: DateSession
    var endReason: String?
    var result: DecisionResult?
    @State private var isDeciding = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()
            // Bigger than the usual list-row avatar so the middle of the
            // screen carries real visual weight instead of reading as bare
            // space between the greeting and the pinned-bottom actions.
            PhotoAvatar(profile: date.partner, size: 128)
            if let result {
                outcome(result)
            } else {
                choice
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.danger)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            actions
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }

    private var choice: some View {
        VStack(spacing: Theme.Space.sm) {
            // "left" is a partner-initiated date_ended; "self_left" is your
            // own Leave button (see AppState+date.swift) and gets no extra
            // line here, since you already know you left. "no_show" is the
            // 20s connect timeout.
            if endReason == "left" {
                Text("They left early")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else if endReason == "timeout" {
                Text("Time's up")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else if endReason == "no_show" {
                Text("They didn't make it")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Text("Keep talking with \(date.partner.displayName)?")
                .font(Theme.Font.title2)
                .foregroundStyle(Theme.Color.text)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func outcome(_ result: DecisionResult) -> some View {
        switch result {
        case .waiting:
            Text("If \(date.partner.displayName) feels the same, you'll see them in Matches.")
                .font(Theme.Font.title3)
                .foregroundStyle(Theme.Color.text)
                .multilineTextAlignment(.center)
        case .passed:
            Text("No worries.")
                .font(Theme.Font.title2)
                .foregroundStyle(Theme.Color.text)
        case .matched:
            // Unreachable: RootView routes a `.matched` result to MatchMadeView.
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        if result == nil {
            VStack(spacing: Theme.Space.md) {
                PrimaryButton(title: "Yes, keep talking", isLoading: isDeciding) { decide(true) }
                Button { decide(false) } label: {
                    Text("Pass")
                        .font(Theme.Font.button)
                        .foregroundStyle(Theme.Color.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.large)
                                .stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth)
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isDeciding)
            }
        } else {
            VStack(spacing: Theme.Space.md) {
                PrimaryButton(title: "Next date") {
                    appState.dismissDateFlow()
                    Task { await appState.startLookingForDate() }
                }
                TextLinkButton(title: "Done for tonight", color: Theme.Color.textSecondary) {
                    appState.dismissDateFlow()
                }
            }
        }
    }

    private func decide(_ explore: Bool) {
        isDeciding = true
        errorMessage = nil
        Task {
            let failure = await appState.decide(explore: explore)
            await MainActor.run {
                isDeciding = false
                errorMessage = failure
            }
        }
    }
}
