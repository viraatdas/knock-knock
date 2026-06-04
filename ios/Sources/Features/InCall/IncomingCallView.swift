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
                Text(call.isVideo ? "Incoming video call" : "Incoming call")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Spacer()
            Spacer()

            // Decline (red) / Accept (black) circular buttons.
            HStack(spacing: Theme.Space.xxxl) {
                VStack(spacing: Theme.Space.sm) {
                    CircleActionButton(systemImage: "phone.down",
                                       diameter: 76,
                                       filled: true,
                                       tint: Theme.Color.danger) {
                        decline()
                    }
                    Text("Decline").uppercaseLabel()
                }
                VStack(spacing: Theme.Space.sm) {
                    CircleActionButton(systemImage: call.isVideo ? "video" : "phone",
                                       diameter: 76,
                                       filled: true,
                                       tint: Theme.Color.accent) {
                        accept()
                    }
                    Text("Accept").uppercaseLabel()
                }
            }
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
}
