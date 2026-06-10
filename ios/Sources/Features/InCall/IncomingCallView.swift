import SwiftUI

struct IncomingCallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var call: ActiveCall
    @State private var pulse = false
    @State private var knockPunch: CGFloat = 1.0
    @State private var knockRing = false

    var body: some View {
        if call.isKnock {
            KnockDoorAnswerView(call: call,
                                onAnswer: { accept() },
                                onDecline: { decline() })
        } else {
            classicBody
        }
    }

    private var classicBody: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()

            // Large avatar with a gentle pulse (scale 1.0 -> 1.04). Each
            // received knock tap punches the avatar and fires a ripple, so the
            // callee literally sees the caller's knocking rhythm.
            ZStack {
                Circle()
                    .stroke(Theme.Color.accent.opacity(knockRing ? 0 : 0.45),
                            lineWidth: 2)
                    .frame(width: 148, height: 148)
                    .scaleEffect(knockRing ? 1.45 : 1.0)

                Circle()
                    .stroke(Theme.Color.hairline, lineWidth: 1)
                    .frame(width: 168, height: 168)
                    .scaleEffect(pulse ? 1.12 : 1.0)
                    .opacity(pulse ? 0 : 0.8)
                    .animation(Theme.Motion.pulse, value: pulse)
                AvatarCircle(name: call.remoteName, size: 132)
                    .scaleEffect((pulse ? 1.04 : 1.0) * knockPunch)
                    .animation(Theme.Motion.pulse, value: pulse)
            }
            .onChange(of: call.knockPulse) { _, _ in
                // Haptic + sound already played in AppState.receiveKnock.
                knockRing = false
                withAnimation(.easeOut(duration: 0.5)) { knockRing = true }
                withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { knockPunch = 1.09 }
                withAnimation(.easeOut(duration: 0.28).delay(0.12)) { knockPunch = 1.0 }
            }

            VStack(spacing: Theme.Space.xs) {
                Text(call.remoteName)
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text(subtitle)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.fast, value: call.knockPulse)
            }

            Spacer()
            Spacer()

            VStack(spacing: Theme.Space.lg) {
                SlideToAnswerControl(isVideo: call.isVideo) {
                    accept()
                }

                VStack(spacing: Theme.Space.sm) {
                    CircleActionButton(systemImage: "phone.down",
                                       diameter: 68,
                                       filled: true,
                                       tint: Theme.Color.danger) {
                        decline()
                    }
                    Text("Decline").uppercaseLabel()
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.bottom, Theme.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .onAppear { pulse = true }
    }

    private func accept() {
        appState.acceptIncoming()
        // The container view switches to InCallView once status != ringing.
    }

    private func decline() {
        appState.declineIncoming()
    }

    private var subtitle: String {
        call.isVideo ? "Incoming video call" : "Incoming call"
    }
}

// MARK: - Knock door ("knock knock, who's there?")

/// The anonymous knock screen: a door, no name. The knocker's taps physically
/// rattle the door; you answer by knocking back twice — the door opens and you
/// find out who it is. Decline quietly leaves them on the porch.
private struct KnockDoorAnswerView: View {
    @ObservedObject var call: ActiveCall
    let onAnswer: () -> Void
    let onDecline: () -> Void

    /// Taps the callee has landed toward the two needed to answer.
    @State private var answerTaps = 0
    @State private var resetTask: Task<Void, Never>?
    /// Door physics.
    @State private var doorShake: Double = 0       // degrees, their knocks
    @State private var doorPunch: CGFloat = 1.0    // scale, your knocks
    @State private var glow = false                // warm light under the door

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()

            VStack(spacing: Theme.Space.xs) {
                Text("Knock knock.")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text(subtitle)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.fast, value: call.knockPulse)
            }

            Spacer()

            door
                .rotationEffect(.degrees(doorShake), anchor: .bottom)
                .scaleEffect(doorPunch)
                .onTapGesture { tapDoor() }
                .onChange(of: call.knockPulse) { _, _ in theirKnock() }

            Text(answerTaps == 0 ? "Knock twice to answer" : "Once more…")
                .font(Theme.Font.footnote)
                .foregroundStyle(answerTaps == 0 ? Theme.Color.textSecondary : Theme.Color.accent)
                .animation(Theme.Motion.fast, value: answerTaps)

            Spacer()

            VStack(spacing: Theme.Space.sm) {
                CircleActionButton(systemImage: "phone.down",
                                   diameter: 68,
                                   filled: true,
                                   tint: Theme.Color.danger) { onDecline() }
                Text("Not now").uppercaseLabel()
            }
            .padding(.bottom, Theme.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .onAppear {
            KnockHaptics.shared.prepare()
            replayMissedRhythm()
        }
        .onDisappear { resetTask?.cancel() }
    }

    private var subtitle: String {
        call.knockPulse <= 1 ? "Someone's at your door"
                             : "Knocked \(call.knockPulse) times"
    }

    /// A warm, simple door: espresso slab, two inset panels, a brass-ish
    /// knocker, and light spilling out underneath as the knocking goes on.
    private var door: some View {
        ZStack(alignment: .bottom) {
            // Light under the door — brightens while they keep knocking.
            Ellipse()
                .fill(Theme.Color.danger.opacity(glow ? 0.35 : 0.12))
                .frame(width: 190, height: 26)
                .blur(radius: 12)
                .offset(y: 14)
                .animation(.easeOut(duration: 0.6), value: glow)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Color.accent)
                .frame(width: 176, height: 264)
                .overlay(
                    VStack(spacing: Theme.Space.sm) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Theme.Color.onAccent.opacity(0.22), lineWidth: 1.5)
                            .frame(width: 116, height: 86)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Theme.Color.onAccent.opacity(0.22), lineWidth: 1.5)
                            .frame(width: 116, height: 86)
                    }
                )
                .overlay(alignment: .trailing) {
                    // Handle.
                    Circle()
                        .fill(Theme.Color.onAccent.opacity(0.85))
                        .frame(width: 10, height: 10)
                        .padding(.trailing, 14)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.Color.text.opacity(0.25), lineWidth: 1)
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Door")
        .accessibilityHint("Knock twice to answer the call")
    }

    /// Replay the taps that landed while the phone was locked — their exact
    /// cadence, as haptics + door rattles — so opening the app feels like
    /// arriving at your own front door mid-knock.
    private func replayMissedRhythm() {
        let rhythm = call.knockRhythm
        guard !rhythm.isEmpty else { return }
        call.knockRhythm = []
        Task { @MainActor in
            var budget = 4.0
            for dt in rhythm {
                let gap = min(max(dt, 0.12), 1.2)
                budget -= gap
                if budget <= 0 { break }
                try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
                KnockHaptics.shared.knock()
                theirKnock()
            }
        }
    }

    /// Their knock arrived: rattle the door and brighten the light.
    /// (Haptic + sound already played in AppState.receiveKnock.)
    private func theirKnock() {
        glow = true
        withAnimation(.spring(response: 0.10, dampingFraction: 0.35)) { doorShake = 1.6 }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.55).delay(0.10)) { doorShake = 0 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            glow = false
        }
    }

    /// Your knock: thump the door; two within 1.5s opens it.
    private func tapDoor() {
        KnockHaptics.shared.knock()
        withAnimation(.spring(response: 0.14, dampingFraction: 0.5)) { doorPunch = 0.96 }
        withAnimation(.easeOut(duration: 0.22).delay(0.10)) { doorPunch = 1.0 }

        answerTaps += 1
        if answerTaps >= 2 {
            resetTask?.cancel()
            onAnswer()
            return
        }
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            answerTaps = 0
        }
    }
}

private struct SlideToAnswerControl: View {
    let isVideo: Bool
    let onComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var completed = false
    @State private var pastThreshold = false

    private let height: CGFloat = 68
    private let knobSize: CGFloat = 60
    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let maxOffset = max(0, geo.size.width - knobSize - inset * 2)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Theme.Color.bgGrouped)
                    .overlay(
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                            .stroke(Theme.Color.hairline, lineWidth: 1)
                    )

                Text(isVideo ? "Swipe for video" : "Swipe to pick up")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, knobSize + Theme.Space.sm)

                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Image(systemName: isVideo ? "video.fill" : "phone.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.Color.bg)
                    }
                    .offset(x: inset + dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !completed else { return }
                                dragOffset = min(max(0, value.translation.width), maxOffset)
                                // Click when crossing (or backing out of) the
                                // commit threshold so the answer point is felt.
                                let past = dragOffset >= maxOffset * 0.72
                                if past != pastThreshold {
                                    pastThreshold = past
                                    Haptics.select()
                                }
                            }
                            .onEnded { _ in
                                guard !completed else { return }
                                pastThreshold = false
                                if dragOffset >= maxOffset * 0.72 {
                                    completed = true
                                    withAnimation(Theme.Motion.standard) {
                                        dragOffset = maxOffset
                                    }
                                    onComplete()
                                } else {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
            .frame(height: height)
        }
        .frame(height: height)
    }
}
