import SwiftUI

/// The live date (SPEC §2.3 "Date"). Init: `DateView(date: DateSession)`.
/// Presented full screen by RootView while `AppState.dateFlow == .inDate`.
/// Owns a `DateViewModel` for the LiveKit/mock call; leaving (button or the
/// 5-minute mark) moves `AppState.dateFlow` to `.deciding`, which swaps this
/// view out for `DecisionView` from underneath (see `onDisappear`).
struct DateView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: DateViewModel
    @State private var showChrome = true
    @State private var showLeaveConfirm = false
    @State private var thumbOffset: CGSize = .zero
    @State private var thumbCornerIndex = 2   // see thumbAnchors: 2 = bottom-trailing
    @State private var hideTask: Task<Void, Never>?

    init(date: DateSession) {
        _vm = StateObject(wrappedValue: DateViewModel(date: date))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    vm.callService.makeRemoteVideoView().ignoresSafeArea()

                    // Mutually exclusive with the "Time!" overlay below: once
                    // that's showing, the date already ended, and both used
                    // to be able to render stacked (e.g. a connect that never
                    // succeeded reaching the 5-minute mark), one on top of
                    // the other.
                    if !vm.hasRemoteVideo && !vm.showTimeUpOverlay { connectingOverlay }

                    VStack {
                        topBar
                        if let cameraMessage = cameraPermissionMessage {
                            cameraPermissionBanner(cameraMessage)
                        }
                        Spacer()
                        if showChrome { bottomChrome }
                    }
                    .padding(Theme.Space.lg)
                    .padding(.top, Theme.Space.md)

                    // Local self-view thumbnail, draggable, snaps to a corner.
                    // `.simultaneously(with:)` so a stationary tap — which
                    // never crosses the drag's minimumDistance and would
                    // otherwise just claim the touch and go nowhere — still
                    // reveals the chrome like a tap anywhere else on screen.
                    localThumbnail
                        .position(thumbPosition(in: geo))
                        .gesture(dragGesture(in: geo).simultaneously(with: TapGesture().onEnded { revealChrome() }))

                    if vm.showTimeUpOverlay { timeUpOverlay }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { revealChrome() }
        .onAppear {
            let date = vm.date
            vm.onTimeUp = { [weak appState] in appState?.handleLocalDateTimeout(date) }
            vm.attach(clock: appState.sessionClock)
            vm.join()
            scheduleHide()
        }
        .onDisappear {
            vm.leave()
            hideTask?.cancel()
        }
        .confirmationDialog("Leave this date?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await appState.leaveDateFromSelf() } }
            Button("Stay", role: .cancel) {}
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var connectingOverlay: some View {
        VStack(spacing: Theme.Space.md) {
            if case .failed(let reason) = vm.connectionState {
                // A real connection error (bad token, unreachable media
                // server, a mic/camera failure inside join) — distinct from
                // "still connecting" and from "partner hasn't shown up",
                // since it's this device's own connection that broke and
                // "They didn't make it" would misdescribe whose fault it is.
                Text(vm.hasEverConnected ? "Connection lost" : "Couldn't connect")
                    .font(Theme.Font.callout)
                    .foregroundStyle(.white)
                Text(reason)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: Theme.Space.md) {
                    PrimaryButton(title: "Try again") { vm.retryJoin() }
                    TextLinkButton(title: "Leave", color: .white) { showLeaveConfirm = true }
                }
                .padding(.horizontal, Theme.Space.xl)
            } else if vm.hasEverConnected {
                // The partner's video dropped mid-date (camera toggled off,
                // a brief network hiccup) — not the same situation as never
                // having connected, so this must not reuse the "They didn't
                // make it" + Continue copy, which would end a still-ongoing
                // date as a no-show.
                ProgressView().tint(.white)
                Text("Reconnecting\u{2026}")
                    .font(Theme.Font.callout)
                    .foregroundStyle(.white)
            } else if vm.connectingTimedOut {
                Text("They didn't make it")
                    .font(Theme.Font.callout)
                    .foregroundStyle(.white)
                PrimaryButton(title: "Continue") { appState.handleConnectTimeout(vm.date) }
                    .padding(.horizontal, Theme.Space.xl)
            } else {
                ProgressView().tint(.white)
                Text("Connecting\u{2026}")
                    .font(Theme.Font.callout)
                    .foregroundStyle(.white)
            }
        }
    }

    /// SPEC: "Turn on camera access in Settings to be seen" — shown instead
    /// of silently degrading to no video when camera permission was denied.
    private var cameraPermissionMessage: String? {
        vm.cameraPermissionDenied ? "Camera access is off. Turn it on in Settings to be seen." : nil
    }

    private func cameraPermissionBanner(_ message: String) -> some View {
        Text(message)
            .font(Theme.Font.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The 1.2s beat between the knock-knock cue and moving to Decision.
    private var timeUpOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            Text("Time!")
                .font(Theme.Font.largeTitle)
                .foregroundStyle(.white)
        }
        .transition(.opacity)
        .animation(Theme.Motion.standard, value: vm.showTimeUpOverlay)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xxs) {
                    Text(vm.date.partner.displayName)
                        .font(Theme.Font.callout)
                        .foregroundStyle(.white)
                    if let age = vm.date.partner.age {
                        Text("\u{00b7} \(age)")
                            .font(Theme.Font.callout)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                if let miles = vm.date.partner.distanceMiles {
                    Text("\(miles) mi away")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            ZStack {
                CountdownRing(
                    progress: appState.sessionClock.progress(from: vm.date.startedAt, to: vm.date.endsAt),
                    lineWidth: 3,
                    color: appState.sessionClock.secondsRemaining(to: vm.date.endsAt) <= 60
                        ? Theme.Color.warm : .white
                )
                .frame(width: 48, height: 48)
                Text(appState.sessionClock.mmss(to: vm.date.endsAt))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }

    private var bottomChrome: some View {
        HStack(spacing: Theme.Space.sm) {
            CircleActionButton(systemImage: vm.isMuted ? "mic.slash.fill" : "mic.fill",
                              diameter: 44, tint: .white,
                              strokeColor: .white.opacity(0.3), background: .white.opacity(0.15)) {
                vm.toggleMute()
            }
            CircleActionButton(systemImage: vm.isVideoEnabled ? "video.fill" : "video.slash.fill",
                              diameter: 44, tint: .white,
                              strokeColor: .white.opacity(0.3), background: .white.opacity(0.15)) {
                vm.toggleVideo()
            }
            CircleActionButton(systemImage: "arrow.triangle.2.circlepath.camera",
                              diameter: 44, tint: .white,
                              strokeColor: .white.opacity(0.3), background: .white.opacity(0.15)) {
                vm.flipCamera()
            }
            CircleActionButton(systemImage: vm.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                              diameter: 44, tint: .white,
                              strokeColor: .white.opacity(0.3), background: .white.opacity(0.15)) {
                vm.toggleSpeaker()
            }
            Spacer(minLength: Theme.Space.xs)
            Button { showLeaveConfirm = true } label: {
                Text("Leave")
                    .font(Theme.Font.buttonSmall)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.sm + 4)
                    .background(Theme.Color.warm, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.bottom, Theme.Space.lg)
        .frame(maxWidth: .infinity)
    }

    private var localThumbnail: some View {
        vm.callService.makeLocalVideoView()
            .frame(width: 96, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            )
    }

    // MARK: - Draggable thumbnail (snaps to a corner)

    /// The four snap anchors for the self-view, inset from the edges and
    /// clear of the top name/timer and bottom chrome.
    private func thumbAnchors(in geo: GeometryProxy) -> [CGPoint] {
        let xL: CGFloat = Theme.Space.lg + 48, xR = geo.size.width - Theme.Space.lg - 48
        let yT: CGFloat = Theme.Space.xxxl + 64, yB = geo.size.height - 204
        return [CGPoint(x: xR, y: yT), CGPoint(x: xL, y: yT),
                CGPoint(x: xR, y: yB), CGPoint(x: xL, y: yB)]
    }

    private func thumbPosition(in geo: GeometryProxy) -> CGPoint {
        let base = thumbAnchors(in: geo)[thumbCornerIndex]
        return CGPoint(x: base.x + thumbOffset.width, y: base.y + thumbOffset.height)
    }

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in thumbOffset = value.translation }
            .onEnded { value in
                // Snap to whichever corner is nearest the release point.
                let base = thumbAnchors(in: geo)[thumbCornerIndex]
                let end = CGPoint(x: base.x + value.predictedEndTranslation.width,
                                  y: base.y + value.predictedEndTranslation.height)
                let anchors = thumbAnchors(in: geo)
                let nearest = anchors.indices.min(by: {
                    hypot(anchors[$0].x - end.x, anchors[$0].y - end.y) <
                    hypot(anchors[$1].x - end.x, anchors[$1].y - end.y)
                }) ?? 0
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    thumbCornerIndex = nearest
                    thumbOffset = .zero
                }
                Haptics.gentle()
            }
    }

    // MARK: - Chrome timing (auto-hides after a few seconds; tap to reveal)

    private func revealChrome() {
        withAnimation(Theme.Motion.standard) { showChrome = true }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { withAnimation(Theme.Motion.standard) { showChrome = false } }
        }
    }
}
