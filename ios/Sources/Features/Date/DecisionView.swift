import SwiftUI

/// Decision screen (SPEC §2.3 "Decision"). Init: `DecisionView(date:
/// DateSession, endReason: String?, result: DecisionResult?)`.
/// - `result == nil`: a swipeable card — swipe right (or tap the heart) to
///   keep talking, swipe left (or tap the X) to pass — shown while
///   `AppState.dateFlow == .deciding`. Either path calls
///   `AppState.decide(explore:)`; the decision is private (the other person
///   never sees which way you went unless it's a mutual yes).
/// - `result != nil`, only `.waiting` or `.passed` (`.matched` routes to
///   `MatchMadeView` instead — see RootView): the outcome copy, shown while
///   `AppState.dateFlow == .result`.
///
/// The partner is still anonymous here: `date.partner` arrives redacted from
/// the server (id only), so this screen shows no name and no photo. Their
/// identity is first shown by `MatchMadeView`, from the `MatchSummary` the
/// decide endpoint returns on a mutual yes.
struct DecisionView: View {
    @EnvironmentObject private var appState: AppState
    /// Not read here since the date went anonymous (the body used to show
    /// `date.partner`); kept because RootView passes it and the decision
    /// itself keys off `AppState.dateFlow`, which carries the same session.
    let date: DateSession
    var endReason: String?
    var result: DecisionResult?
    @State private var isDeciding = false
    @State private var errorMessage: String?
    /// Live finger position while dragging the card; `.zero` at rest. Also
    /// the vehicle for the fly-off-screen animation on release past
    /// `swipeThreshold`, so `decide(_:)` and the drag gesture share one path.
    @State private var dragOffset: CGSize = .zero
    @State private var cardRemoved = false

    private let swipeThreshold: CGFloat = 100

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()
            if let result {
                doorMark
                outcome(result)
            } else {
                card
                swipeHint
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

    /// Stands in for the partner's avatar, which the anonymous date can't
    /// show. Same 128pt footprint as the `PhotoAvatar` it replaced so the
    /// middle of the screen still carries real visual weight instead of
    /// reading as bare space between the question and the pinned-bottom
    /// actions. A closed door in the warm terracotta: the other side hasn't
    /// been opened yet.
    private var doorMark: some View {
        ZStack {
            Circle()
                .fill(Theme.Color.warm.opacity(0.12))
                .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth))
            Image(systemName: "door.left.hand.closed")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.Color.warm)
        }
        .frame(width: 128, height: 128)
        .accessibilityHidden(true)
    }

    /// The swipeable card: `doorMark` plus the prompt, draggable left/right,
    /// with LIKE/PASS stamps that fade in as the drag crosses the threshold.
    /// A drag is just a faster path to the same `decide(_:)` the heart/X
    /// buttons below call — VoiceOver and anyone who'd rather tap keep a
    /// fully equivalent way to answer.
    private var card: some View {
        VStack(spacing: Theme.Space.lg) {
            ZStack {
                doorMark
                stamp("LIKE", color: Theme.Color.warm)
                    .opacity(likeOpacity)
                    .rotationEffect(.degrees(-12))
                    .offset(x: -70, y: -60)
                stamp("PASS", color: Theme.Color.textSecondary)
                    .opacity(passOpacity)
                    .rotationEffect(.degrees(12))
                    .offset(x: 70, y: -60)
            }
            promptText
        }
        .padding(Theme.Space.xl)
        .background(Theme.Color.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large)
                .stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth)
        )
        .offset(dragOffset)
        .rotationEffect(.degrees(Double(dragOffset.width / 16)))
        .opacity(cardRemoved ? 0 : 1)
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard !isDeciding else { return }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    guard !isDeciding else { return }
                    if value.translation.width > swipeThreshold {
                        swipe(liked: true)
                    } else if value.translation.width < -swipeThreshold {
                        swipe(liked: false)
                    } else {
                        withAnimation(Theme.Motion.standard) { dragOffset = .zero }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(promptAccessibilityLabel)
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.Font.title3.bold())
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xxs)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).stroke(color, lineWidth: 2))
    }

    /// 0→1 as the card crosses from center to `swipeThreshold` to the right.
    private var likeOpacity: Double {
        min(1, max(0, Double(dragOffset.width) / Double(swipeThreshold)))
    }

    /// 0→1 as the card crosses from center to `swipeThreshold` to the left.
    private var passOpacity: Double {
        min(1, max(0, Double(-dragOffset.width) / Double(swipeThreshold)))
    }

    private var promptText: some View {
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
            Text("Keep talking?")
                .font(Theme.Font.title2)
                .foregroundStyle(Theme.Color.text)
                .multilineTextAlignment(.center)
        }
    }

    private var promptAccessibilityLabel: String {
        "Keep talking? Double tap the heart below to say yes, or the X to pass."
    }

    private var swipeHint: some View {
        Text("Swipe right to keep talking, left to pass")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.textSecondary)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func outcome(_ result: DecisionResult) -> some View {
        switch result {
        case .waiting:
            Text("If they feel the same, you'll see them in Matches.")
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
            HStack(spacing: Theme.Space.xxl) {
                CircleActionButton(systemImage: "xmark", diameter: 64,
                                   tint: Theme.Color.textSecondary, strokeColor: Theme.Color.hairline,
                                   background: Theme.Color.bg) {
                    swipe(liked: false)
                }
                .accessibilityLabel("Pass")
                .disabled(isDeciding)

                CircleActionButton(systemImage: "heart.fill", diameter: 72, filled: true,
                                   tint: Theme.Color.warm, filledIconColor: Theme.Color.onAccent) {
                    swipe(liked: true)
                }
                .accessibilityLabel("Keep talking")
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

    /// Shared by the drag gesture and the heart/X buttons: animate the card
    /// off in `liked`'s direction, then fire the actual decision. If the
    /// request fails, bring the card back instead of leaving it stranded
    /// off-screen with no way to answer again.
    private func swipe(liked: Bool) {
        guard !isDeciding else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset = CGSize(width: liked ? 700 : -700, height: dragOffset.height)
            cardRemoved = true
        }
        Haptics.gentle()
        decide(liked)
    }

    private func decide(_ explore: Bool) {
        isDeciding = true
        errorMessage = nil
        Task {
            let failure = await appState.decide(explore: explore)
            await MainActor.run {
                isDeciding = false
                errorMessage = failure
                if failure != nil {
                    // The card already flew off-screen optimistically; a
                    // failed request means no decision was recorded, so
                    // bring it back and let them try again.
                    withAnimation(Theme.Motion.standard) {
                        dragOffset = .zero
                        cardRemoved = false
                    }
                }
            }
        }
    }
}
