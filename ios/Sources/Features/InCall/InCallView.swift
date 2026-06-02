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
                // Background: group grid, 1:1 video surface, or audio-only white.
                if vm.isGroup {
                    groupGrid(in: geo)
                        .ignoresSafeArea()
                } else if isVideoCall && vm.hasRemoteVideo {
                    vm.service.makeRemoteVideoView()
                        .ignoresSafeArea()
                } else if isVideoCall {
                    Theme.Color.text.ignoresSafeArea() // connecting video
                } else {
                    audioOnlyBackground
                }

                // Local self-view thumbnail (draggable, rounded) — 1:1 only; the
                // group grid shows everyone including a self tile.
                if isVideoCall && !vm.isGroup {
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
