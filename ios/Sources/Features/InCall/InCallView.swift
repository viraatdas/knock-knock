import SwiftUI

struct InCallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var call: ActiveCall
    @StateObject private var vm: InCallViewModel

    @State private var chromeVisible = true
    @State private var waitingTapCount = 0
    @State private var remotePunch: CGFloat = 1.0
    @State private var thumbOffset: CGSize = .zero
    @State private var thumbCornerIndex = 0   // 0 = top-trailing
    @State private var hideTask: Task<Void, Never>?

    init(call: ActiveCall) {
        self.call = call
        _vm = StateObject(wrappedValue: InCallViewModel(call: call))
    }

    /// A video *call* — independent of whether our own camera is currently on,
    /// so muting your camera never blanks the other person's feed.
    private var isVideoCall: Bool { call.isVideo }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background: group grid, 1:1 video surface, or audio-only white.
                if vm.isGroup {
                    groupGrid(in: geo)
                        .ignoresSafeArea()
                } else if isVideoCall && vm.hasRemoteVideo {
                    vm.service.makeRemoteVideoView()
                        .ignoresSafeArea()
                } else if isVideoCall {
                    videoWaitingBackground
                } else {
                    audioOnlyBackground
                }

                // Local self-view thumbnail (draggable, snaps to corners) —
                // 1:1 only; the group grid shows everyone including a self tile.
                // Hidden while your camera is off.
                if isVideoCall && vm.isVideoEnabled && !vm.isGroup {
                    localThumbnail
                        .position(thumbPosition(in: geo))
                        .gesture(dragGesture(in: geo))
                        .transition(.scale.combined(with: .opacity))
                }

                // Chrome (fades after a few seconds; tap to reveal).
                chrome
                    .opacity(chromeVisible ? 1 : 0)
                    .animation(Theme.Motion.standard, value: chromeVisible)
            }
            .contentShape(Rectangle())
            .onTapGesture { revealChrome() }
        }
        // Crossfade ringing → live call instead of hard-swapping surfaces.
        .animation(Theme.Motion.standard, value: vm.remoteJoined)
        .animation(Theme.Motion.standard, value: vm.hasRemoteVideo)
        .background(isVideoCall ? Theme.Color.text : Theme.Color.bg)
        .onAppear {
            KnockHaptics.shared.prepare()
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
                .scaleEffect(remotePunch)
                .onChange(of: call.knockPulse) { _, _ in punchRemoteAvatar() }
            VStack(spacing: Theme.Space.xs) {
                Text(call.remoteName)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.text)
                Text(vm.statusText)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .monospacedDigit()
            }
            if showsWaitingTapTarget {
                WaitingTapButton(onDarkBackground: false) {
                    sendWaitingTap()
                }
                .padding(.top, Theme.Space.md)

                waitingCaption(color: Theme.Color.textSecondary)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .ignoresSafeArea()
    }

    private var videoWaitingBackground: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()
            AvatarCircle(name: call.remoteName,
                         size: 128,
                         background: Color.white.opacity(0.12),
                         foreground: .white)
                .scaleEffect(remotePunch)
                .onChange(of: call.knockPulse) { _, _ in punchRemoteAvatar() }
            VStack(spacing: Theme.Space.xs) {
                Text(call.remoteName)
                    .font(Theme.Font.title)
                    .foregroundStyle(.white)
                Text(videoWaitingText)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .monospacedDigit()
                if vm.remoteJoined {
                    Text("Their camera is off")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.top, 2)
                }
            }
            if showsWaitingTapTarget {
                WaitingTapButton(onDarkBackground: true) {
                    sendWaitingTap()
                }
                .padding(.top, Theme.Space.md)

                waitingCaption(color: Color.white.opacity(0.7))
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.text)
        .ignoresSafeArea()
    }

    /// "Tap until they pick up" until the first tap, then a live knock counter.
    private func waitingCaption(color: Color) -> some View {
        Text(waitingTapCount == 0
             ? "Tap until they pick up"
             : "\(waitingTapCount + 1) knocks — they can feel every one")
            .font(Theme.Font.footnote)
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .animation(Theme.Motion.fast, value: waitingTapCount)
    }

    private var videoWaitingText: String {
        // Once they've joined, statusText is the live timer; before that it's
        // Knocking…/Ringing…/Connecting….
        vm.statusText
    }

    /// Keep the tap pad up until the other person actually joins the room —
    /// being connected to the media server ourselves doesn't mean they picked up.
    private var showsWaitingTapTarget: Bool {
        guard call.isKnock, call.direction == .outgoing, !vm.remoteJoined else { return false }
        switch vm.connectionState {
        case .ended, .failed(_):
            return false
        case .idle, .connecting, .reconnecting, .connected:
            return true
        }
    }

    // MARK: Group grid

    /// Adaptive tile grid for group calls: remote participants plus a self tile.
    private func groupGrid(in geo: GeometryProxy) -> some View {
        let participants = vm.displayParticipants
        let tiles = participants.count + 1            // +1 for the self tile
        let cols = tiles <= 1 ? 1 : (tiles <= 4 ? 2 : 3)
        let rows = Int(ceil(Double(tiles) / Double(cols)))
        let spacing: CGFloat = 4
        let w = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let h = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)

        return ZStack {
            Theme.Color.text
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: spacing), count: cols),
                      spacing: spacing) {
                ForEach(participants) { p in
                    GroupTile(name: p.displayName,
                              showVideo: isVideoCall && p.hasVideo,
                              video: { vm.service.makeRemoteVideoView(for: p.id) })
                        .frame(width: w, height: h)
                        .clipped()
                }
                // Self tile last.
                GroupTile(name: "You",
                          showVideo: isVideoCall && vm.isVideoEnabled,
                          video: { vm.service.makeLocalVideoView() })
                    .frame(width: w, height: h)
                    .clipped()
            }
        }
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
            .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
            // Double-tap your own tile to flip the camera.
            .onTapGesture(count: 2) {
                Haptics.select()
                vm.flipCamera()
            }
    }

    /// The four snap anchors for the self-view, inset from the edges and clear
    /// of the top status text / bottom controls.
    private func thumbAnchors(in geo: GeometryProxy) -> [CGPoint] {
        let xL: CGFloat = 16 + 54, xR = geo.size.width - 16 - 54
        let yT: CGFloat = 140, yB = geo.size.height - 200
        return [CGPoint(x: xR, y: yT), CGPoint(x: xL, y: yT),
                CGPoint(x: xR, y: yB), CGPoint(x: xL, y: yB)]
    }

    private func thumbPosition(in geo: GeometryProxy) -> CGPoint {
        let base = thumbAnchors(in: geo)[thumbCornerIndex]
        return CGPoint(x: base.x + thumbOffset.width, y: base.y + thumbOffset.height)
    }

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                thumbOffset = value.translation
            }
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

    // MARK: Chrome (top name/timer + bottom controls)

    private var chrome: some View {
        VStack {
            // Top: callee name + timer in thin white (or black on white for audio).
            VStack(spacing: 4) {
                Text(vm.isGroup ? "Group call" : call.remoteName)
                    .font(Theme.Font.title3)
                    .fontWeight(.light)
                    .foregroundStyle(chromeText)
                Text(vm.isGroup ? "\(call.memberNames.count + 1) people · \(vm.statusText)"
                                : vm.statusText)
                    .font(Theme.Font.callout)
                    .foregroundStyle(chromeSubtext)
                    .monospacedDigit()
            }
            .padding(.top, Theme.Space.xxl)
            .frame(maxWidth: .infinity)
            .background(topScrim)

            Spacer()

            // Bottom row of thin circular buttons.
            HStack(spacing: Theme.Space.md) {
                CircleActionButton(
                    systemImage: vm.isMuted ? "mic.slash" : "mic",
                    diameter: 56,
                    filled: vm.isMuted,
                    tint: chromeText,
                    strokeColor: chromeStroke,
                    background: .clear,
                    filledIconColor: filledIconColor) { vm.toggleMute(); revealChrome() }

                // Audio output: shows current route (earpiece/speaker/AirPods),
                // taps open the system picker.
                AudioRouteButton(diameter: 56,
                                 tint: chromeText,
                                 strokeColor: chromeStroke,
                                 filledIconColor: filledIconColor)

                if call.isVideo {
                    CircleActionButton(
                        systemImage: vm.isVideoEnabled ? "video" : "video.slash",
                        diameter: 56,
                        filled: !vm.isVideoEnabled,
                        tint: chromeText,
                        strokeColor: chromeStroke,
                        background: .clear,
                        filledIconColor: filledIconColor) { vm.toggleVideo(); revealChrome() }

                    CircleActionButton(
                        systemImage: "arrow.triangle.2.circlepath.camera",
                        diameter: 56,
                        filled: false,
                        tint: chromeText,
                        strokeColor: chromeStroke,
                        background: .clear) { vm.flipCamera(); revealChrome() }
                }

                // Red end call.
                CircleActionButton(
                    systemImage: "phone.down",
                    diameter: 56,
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
    /// Dark icon on white-filled buttons over video; cream on brown elsewhere.
    private var filledIconColor: Color { onVideo ? Theme.Color.text : Theme.Color.onAccent }

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

    /// They tapped back while we wait — bounce their avatar in answer.
    private func punchRemoteAvatar() {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { remotePunch = 1.08 }
        withAnimation(.easeOut(duration: 0.28).delay(0.12)) { remotePunch = 1.0 }
    }

    private func sendWaitingTap() {
        waitingTapCount += 1
        guard let userId = call.remoteUserId, !userId.isEmpty else {
            KnockHaptics.shared.knock()
            revealChrome()
            return
        }
        appState.sendKnockTap(to: userId)
        revealChrome()
    }
}

private struct WaitingTapButton: View {
    let onDarkBackground: Bool
    let action: () -> Void

    @State private var pressScale: CGFloat = 1.0
    @State private var ringPulse = false
    @State private var breathing = false

    var body: some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.08)) { pressScale = 0.92 }
            withAnimation(.easeOut(duration: 0.22).delay(0.08)) { pressScale = 1.0 }
            ringPulse = false
            withAnimation(.easeOut(duration: 0.45)) { ringPulse = true }
        } label: {
            ZStack {
                // Idle breathing ring — a standing invitation to keep tapping.
                Circle()
                    .stroke(ringColor.opacity(breathing ? 0.06 : 0.25),
                            lineWidth: Theme.hairlineWidth)
                    .frame(width: 148, height: 148)
                    .scaleEffect(breathing ? 1.16 : 1.02)

                Circle()
                    .stroke(ringColor.opacity(ringPulse ? 0 : 0.36),
                            lineWidth: Theme.hairlineWidth)
                    .frame(width: 148, height: 148)
                    .scaleEffect(ringPulse ? 1.28 : 1.0)

                Circle()
                    .fill(fillColor)
                    .frame(width: 148, height: 148)
                    .overlay(
                        Circle()
                            .stroke(strokeColor, lineWidth: Theme.hairlineWidth)
                    )
                    .overlay(
                        Text("tap")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(textColor)
                    )
                    .scaleEffect(pressScale)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tap")
        .accessibilityHint("Sends another tap while waiting for pickup")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    private var fillColor: Color {
        onDarkBackground ? Theme.Color.bg : Theme.Color.accent
    }

    private var textColor: Color {
        onDarkBackground ? Theme.Color.accent : Theme.Color.onAccent
    }

    private var ringColor: Color {
        onDarkBackground ? Color.white : Theme.Color.accent
    }

    private var strokeColor: Color {
        onDarkBackground ? Color.white.opacity(0.18) : Theme.Color.hairline
    }
}

// MARK: - Group grid tile

/// A single participant cell in the group grid: live video when available,
/// otherwise an avatar on near-black, with a name chip in the corner.
private struct GroupTile<Video: View>: View {
    let name: String
    let showVideo: Bool
    @ViewBuilder var video: () -> Video

    var body: some View {
        ZStack {
            if showVideo {
                video()
            } else {
                Theme.Color.text
                AvatarCircle(name: name.isEmpty ? "?" : name, size: 72)
            }
            VStack {
                Spacer()
                HStack {
                    Text(name.isEmpty ? "" : name)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.45), in: Capsule())
                    Spacer()
                }
            }
            .padding(8)
        }
    }
}
