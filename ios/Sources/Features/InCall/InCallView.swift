import SwiftUI

struct InCallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var call: ActiveCall
    @StateObject private var vm: InCallViewModel

    @State private var chromeVisible = true
    @State private var thumbOffset: CGSize = .zero
    @State private var thumbAccumulated: CGSize = CGSize(width: 0, height: 0)
    @State private var hideTask: Task<Void, Never>?

    init(call: ActiveCall) {
        self.call = call
        _vm = StateObject(wrappedValue: InCallViewModel(call: call))
    }

    private var isVideoCall: Bool { vm.isVideoEnabled && call.isVideo }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background: video surface (black) or audio-only white.
                if isVideoCall && vm.hasRemoteVideo {
                    vm.service.makeRemoteVideoView()
                        .ignoresSafeArea()
                } else if isVideoCall {
                    Theme.Color.text.ignoresSafeArea() // connecting video
                } else {
                    audioOnlyBackground
                }

                // Local self-view thumbnail (draggable, rounded).
                if isVideoCall {
                    localThumbnail
                        .position(thumbPosition(in: geo))
                        .gesture(dragGesture(in: geo))
                }

                // Chrome (fades after a few seconds; tap to reveal).
                chrome
                    .opacity(chromeVisible ? 1 : 0)
                    .animation(Theme.Motion.standard, value: chromeVisible)
            }
            .contentShape(Rectangle())
            .onTapGesture { revealChrome() }
        }
        .background(isVideoCall ? Theme.Color.text : Theme.Color.bg)
        .onAppear {
            vm.start()
            scheduleHide()
        }
        .onDisappear { hideTask?.cancel() }
    }

    // MARK: Audio-only background — centered avatar on white.

    private var audioOnlyBackground: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()
            AvatarCircle(name: call.remoteName, size: 128)
            VStack(spacing: Theme.Space.xs) {
                Text(call.remoteName)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.text)
                Text(vm.statusText)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .ignoresSafeArea()
    }

    // MARK: Local thumbnail

    private var localThumbnail: some View {
        vm.service.makeLocalVideoView()
            .frame(width: 108, height: 152)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
    }

    private func thumbPosition(in geo: GeometryProxy) -> CGPoint {
        let base = CGPoint(x: geo.size.width - 80, y: 140)
        return CGPoint(x: base.x + thumbOffset.width, y: base.y + thumbOffset.height)
    }

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                thumbOffset = CGSize(width: thumbAccumulated.width + value.translation.width,
                                     height: thumbAccumulated.height + value.translation.height)
            }
            .onEnded { _ in
                thumbAccumulated = thumbOffset
            }
    }

    // MARK: Chrome (top name/timer + bottom controls)

    private var chrome: some View {
        VStack {
            // Top: callee name + timer in thin white (or black on white for audio).
            VStack(spacing: 4) {
                Text(call.remoteName)
                    .font(Theme.Font.title3)
                    .fontWeight(.light)
                    .foregroundStyle(chromeText)
                Text(vm.statusText)
                    .font(Theme.Font.callout)
                    .foregroundStyle(chromeSubtext)
                    .monospacedDigit()
            }
            .padding(.top, Theme.Space.xxl)
            .frame(maxWidth: .infinity)
            .background(topScrim)

            Spacer()

            // Bottom row of thin circular buttons.
            HStack(spacing: Theme.Space.lg) {
                CircleActionButton(
                    systemImage: vm.isMuted ? "mic.slash" : "mic",
                    diameter: 60,
                    filled: vm.isMuted,
                    tint: chromeText,
                    strokeColor: chromeStroke,
                    background: .clear) { vm.toggleMute(); revealChrome() }

                if call.isVideo {
                    CircleActionButton(
                        systemImage: vm.isVideoEnabled ? "video" : "video.slash",
                        diameter: 60,
                        filled: !vm.isVideoEnabled,
                        tint: chromeText,
                        strokeColor: chromeStroke,
                        background: .clear) { vm.toggleVideo(); revealChrome() }

                    CircleActionButton(
                        systemImage: "arrow.triangle.2.circlepath.camera",
                        diameter: 60,
                        filled: false,
                        tint: chromeText,
                        strokeColor: chromeStroke,
                        background: .clear) { vm.flipCamera(); revealChrome() }
                }

                // Red end call.
                CircleActionButton(
                    systemImage: "phone.down",
                    diameter: 60,
                    filled: true,
                    tint: Theme.Color.danger,
                    background: .clear) { endCall() }
            }
            .padding(.bottom, Theme.Space.xxl)
            .frame(maxWidth: .infinity)
            .background(bottomScrim)
        }
    }

    // MARK: Color helpers (white chrome over video, dark chrome over white)

    private var onVideo: Bool { isVideoCall }
    private var chromeText: Color { onVideo ? .white : Theme.Color.text }
    private var chromeSubtext: Color { onVideo ? Color.white.opacity(0.7) : Theme.Color.textSecondary }
    private var chromeStroke: Color { onVideo ? Color.white.opacity(0.4) : Theme.Color.hairline }

    private var topScrim: some View {
        Group {
            if onVideo {
                LinearGradient(colors: [Color.black.opacity(0.35), .clear],
                               startPoint: .top, endPoint: .bottom)
            } else { Color.clear }
        }
        .ignoresSafeArea(edges: .top)
    }
    private var bottomScrim: some View {
        Group {
            if onVideo {
                LinearGradient(colors: [.clear, Color.black.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
            } else { Color.clear }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Chrome timing

    private func revealChrome() {
        chromeVisible = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { chromeVisible = false }
        }
    }

    private func endCall() {
        vm.end()
        appState.endActiveCall()
    }
}
