import SwiftUI

struct IncomingCallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var call: ActiveCall
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()

            // Large avatar with a gentle pulse (scale 1.0 -> 1.04).
            ZStack {
                Circle()
                    .stroke(Theme.Color.hairline, lineWidth: 1)
                    .frame(width: 168, height: 168)
                    .scaleEffect(pulse ? 1.12 : 1.0)
                    .opacity(pulse ? 0 : 0.8)
                AvatarCircle(name: call.remoteName, size: 132)
                    .scaleEffect(pulse ? 1.04 : 1.0)
            }
            .animation(Theme.Motion.pulse, value: pulse)

            VStack(spacing: Theme.Space.xs) {
                Text(call.remoteName)
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text(subtitle)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
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
        if call.isKnock { return "is knocking" }
        return call.isVideo ? "Incoming video call" : "Incoming call"
    }
}

private struct SlideToAnswerControl: View {
    let isVideo: Bool
    let onComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var completed = false

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
                            }
                            .onEnded { _ in
                                guard !completed else { return }
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
