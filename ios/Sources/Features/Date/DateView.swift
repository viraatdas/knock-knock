import SwiftUI

/// The live date (SPEC §2.3 "Date"). Init: `DateView(date: DateSession)`.
/// Presented full screen by RootView while `AppState.dateFlow == .inDate`.
/// Owns a `DateViewModel` for the LiveKit/mock call; leaving (button or the
/// 5-minute mark) moves `AppState.dateFlow` to `.deciding`, which swaps this
/// view out for `DecisionView` from underneath (see `onDisappear`).
///
/// The date is anonymous: the server sends `date.partner` redacted (id only,
/// no name, age, distance, bio or photo), so nothing here shows who the other
/// person is. Only the countdown and the call controls are on screen; their
/// identity appears after a mutual match, from the `MatchSummary`.
struct DateView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: DateViewModel
    @State private var showChrome = true
    @State private var showLeaveConfirm = false
    @State private var thumbOffset: CGSize = .zero
    @State private var thumbCornerIndex = 2   // see thumbAnchors: 2 = bottom-trailing
    @State private var hideTask: Task<Void, Never>?
    /// Measured height of `cameraPermissionBanner` (0 while it isn't shown),
    /// so the top thumbnail anchors can clear it. See `thumbAnchors`.
    @State private var cameraBannerHeight: CGFloat = 0

    /// Gap between the top bar, the camera banner and the bottom chrome.
    /// Explicit (rather than the stack's default) because `thumbAnchors`
    /// adds it to the banner height.
    private let chromeSpacing: CGFloat = Theme.Space.xs

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

                    VStack(spacing: chromeSpacing) {
                        topBar
                        if let cameraMessage = cameraPermissionMessage {
                            cameraPermissionBanner(cameraMessage)
                        }
                        Spacer()
                        if showChrome { bottomChrome }
                    }
                    .padding(Theme.Space.lg)
                    .padding(.top, Theme.Space.md)
                    .onPreferenceChange(CameraBannerHeightKey.self) { cameraBannerHeight = $0 }

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
    /// of silently degrading to no video/audio when permission was denied.
    /// Combines camera and microphone into one line (rather than two
    /// stacked banners) since both point at the same fix: the Settings app.
    private var cameraPermissionMessage: String? {
        switch (vm.cameraPermissionDenied, vm.microphonePermissionDenied) {
        case (true, true):
            return "Camera and microphone are off. Turn them on in Settings to be seen and heard."
        case (true, false):
            return "Camera access is off. Turn it on in Settings to be seen."
        case (false, true):
            return "Microphone access is off. Turn it on in Settings to be heard."
        case (false, false):
            return nil
        }
    }

    /// Tappable — unlike a plain notice, this is the fastest way back into
    /// the flow: open Settings instead of leaving the person to hunt for it
    /// on their own mid-date.
    private func cameraPermissionBanner(_ message: String) -> some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(message)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PressableButtonStyle())
        // Report the rendered height (padding included, and however
        // many lines the message wrapped to) for `thumbAnchors`. Reverts
        // to the key's default of 0 once the banner leaves the tree.
        .background(GeometryReader { proxy in
            Color.clear.preference(key: CameraBannerHeightKey.self, value: proxy.size.height)
        })
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

    /// A quiet caption on the leading side and the countdown ring on the
    /// trailing side. Deliberately no name, age or distance: the partner is
    /// anonymous until a mutual match (see the type doc).
    private var topBar: some View {
        HStack(alignment: .center) {
            Text("Your date")
                .font(Theme.Font.caption)
                .foregroundStyle(.white.opacity(0.7))
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
    /// clear of the top bar, the camera banner and the bottom chrome. The
    /// top bar starts `Theme.Space.lg + Theme.Space.md` below the safe area
    /// and is 48pt tall (the countdown ring), so its bottom edge is at
    /// lg + md + 48. While the camera-permission banner is showing it sits
    /// `chromeSpacing` under the ring and is `cameraBannerHeight` tall (as
    /// measured, since the message wraps on narrow screens), so the top
    /// chrome's bottom edge moves down by that much. `yT` is that plus a
    /// `Theme.Space.md` gap plus half the thumbnail's 128pt height
    /// (`.position` centers it), which parks the thumbnail's top edge 16pt
    /// under whichever of the ring or the banner is lowest instead of over
    /// its lower half.
    private func thumbAnchors(in geo: GeometryProxy) -> [CGPoint] {
        let xL: CGFloat = Theme.Space.lg + 48, xR = geo.size.width - Theme.Space.lg - 48
        let banner: CGFloat = cameraPermissionMessage == nil ? 0 : chromeSpacing + cameraBannerHeight
        let yT: CGFloat = Theme.Space.lg + Theme.Space.md + 48 + banner + Theme.Space.md + 64
        let yB: CGFloat = geo.size.height - 204
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

/// Rendered height of DateView's camera-permission banner, for the
/// thumbnail's top anchors. 0 when the banner isn't in the tree.
private struct CameraBannerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
