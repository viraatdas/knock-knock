import Foundation
import SwiftUI
import AVFoundation

#if canImport(LiveKit)
import LiveKit

/// Real media via the self-hosted **LiveKit** SFU, 1:1 only. The control
/// plane (`POST /lobby/join` etc.) returns `session.sfuUrl` + `session.
/// joinToken`; both daters join the same room (= the date id).
///
/// There is no system call UI anymore, so nothing else configures the audio session.
/// `join(session:videoEnabled:)` sets `.playAndRecord`/`.videoChat` with
/// Bluetooth + speaker routing and activates it itself, before `room.connect`.
final class RealCallService: NSObject, CallService, @unchecked Sendable {
    weak var delegate: CallServiceDelegate?

    /// Audio tuning: full voice processing (echo cancellation + noise
    /// suppression + auto gain) and DTX off — DTX stops sending packets during
    /// silence, which can make quiet speech sound gated/choppy on flaky links.
    /// Video tuning: capture 720p@30 from the front camera and publish with
    /// simulcast so the SFU can serve each receiver the best layer for their
    /// link instead of one compromise stream.
    let room = Room(roomOptions: RoomOptions(
        defaultCameraCaptureOptions: CameraCaptureOptions(
            position: .front,
            dimensions: .h720_169,
            fps: 30),
        defaultAudioCaptureOptions: AudioCaptureOptions(
            echoCancellation: true,
            autoGainControl: true,
            noiseSuppression: true,
            highpassFilter: true),
        defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
        defaultAudioPublishOptions: AudioPublishOptions(dtx: false),
        adaptiveStream: true,
        dynacast: true))

    private(set) var connectionState: CallConnectionState = .idle {
        didSet {
            let state = connectionState
            DispatchQueue.main.async {
                if self.isLeavingSnapshot, state != .ended { return }
                self.delegate?.callService(self, didChange: state)
            }
        }
    }
    private(set) var hasRemoteVideo = false
    private(set) var isMuted = false
    private(set) var isVideoEnabled = true
    private(set) var isUsingFrontCamera = true
    private let lifecycleLock = NSLock()
    private var lifecycleGeneration = 0
    private var isLeaving = false
    private var joinTask: Task<Void, Never>?

    override init() {
        super.init()
        room.add(delegate: self)
    }

    // MARK: - Join

    func join(session: DateSession, videoEnabled: Bool) {
        let generation = beginJoin()
        isVideoEnabled = videoEnabled
        connectionState = .connecting
        Self.configureAudioSession()
        let url = session.sfuUrl
        let token = session.joinToken
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.room.connect(url: url, token: token)
                guard !Task.isCancelled, self.isCurrentJoin(generation) else {
                    await self.room.disconnect()
                    return
                }
                try await self.room.localParticipant.setMicrophone(enabled: !self.isMuted)
                guard !Task.isCancelled, self.isCurrentJoin(generation) else {
                    await self.room.disconnect()
                    return
                }
                if videoEnabled {
                    if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                        do {
                            try await self.room.localParticipant.setCamera(enabled: true)
                            guard !Task.isCancelled, self.isCurrentJoin(generation) else {
                                await self.room.disconnect()
                                return
                            }
                            Self.preferSpeakerIfOnEarpiece()
                        } catch {
                            if self.isCurrentJoin(generation) {
                                self.isVideoEnabled = false
                            }
                        }
                    } else if self.isCurrentJoin(generation) {
                        self.isVideoEnabled = false
                    }
                }
                guard !Task.isCancelled, self.isCurrentJoin(generation) else {
                    await self.room.disconnect()
                    return
                }
            } catch {
                await self.room.disconnect()
                if self.isCurrentJoin(generation) {
                    self.connectionState = .failed("Couldn't connect")
                }
            }
        }
        joinTask = task
    }

    /// No system call UI here to own the audio session, so the app configures
    /// it itself: `.playAndRecord`/`.videoChat` with Bluetooth + speaker routing.
    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoChat,
                                    options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            // Best-effort: LiveKit's own AudioManager default configuration is
            // a reasonable fallback if this fails.
        }
    }

    private func beginJoin() -> Int {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        lifecycleGeneration += 1
        isLeaving = false
        return lifecycleGeneration
    }

    private func invalidateJoin() {
        lifecycleLock.lock()
        lifecycleGeneration += 1
        isLeaving = true
        lifecycleLock.unlock()
    }

    private func isCurrentJoin(_ generation: Int) -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return !isLeaving && lifecycleGeneration == generation
    }

    private func currentGenerationIfActive() -> Int? {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return isLeaving ? nil : lifecycleGeneration
    }

    private var isLeavingSnapshot: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return isLeaving
    }

    // MARK: - Controls

    func setMuted(_ muted: Bool) {
        guard let generation = currentGenerationIfActive() else { return }
        isMuted = muted
        Task { [weak self] in
            guard let self, self.isCurrentJoin(generation) else { return }
            _ = try? await self.room.localParticipant.setMicrophone(enabled: !muted)
        }
    }

    func setVideoEnabled(_ enabled: Bool) {
        guard let generation = currentGenerationIfActive() else { return }
        isVideoEnabled = enabled
        Task { [weak self] in
            guard let self, self.isCurrentJoin(generation) else { return }
            _ = try? await self.room.localParticipant.setCamera(enabled: enabled)
            guard self.isCurrentJoin(generation) else { return }
            if enabled { Self.preferSpeakerIfOnEarpiece() }
        }
    }

    /// Video belongs on speakerphone — but never yank audio off headphones/BT.
    static func preferSpeakerIfOnEarpiece() {
        let session = AVAudioSession.sharedInstance()
        if session.currentRoute.outputs.first?.portType == .builtInReceiver {
            try? session.overrideOutputAudioPort(.speaker)
        }
    }

    func flipCamera() {
        guard let generation = currentGenerationIfActive() else { return }
        // Set an explicit target instead of LiveKit's toggle — the toggle
        // derives "current" from device state and throws .unspecified during
        // capture (re)starts, which made flip a silent no-op.
        let target: AVCaptureDevice.Position = isUsingFrontCamera ? .back : .front
        isUsingFrontCamera.toggle()
        Task { [weak self] in
            guard let self,
                  self.isCurrentJoin(generation),
                  let track = self.room.localParticipant.firstCameraVideoTrack as? LocalVideoTrack,
                  let capturer = track.capturer as? CameraCapturer else { return }
            do {
                try await capturer.set(cameraPosition: target)
                guard self.isCurrentJoin(generation) else { return }
            } catch {
                // Capture restart failed — revert so the next tap retries.
                if self.isCurrentJoin(generation) {
                    self.isUsingFrontCamera = (target != .front)
                }
            }
        }
    }

    // MARK: - Video views

    func makeLocalVideoView() -> AnyView {
        AnyView(LiveKitLocalVideoView(participant: room.localParticipant))
    }
    func makeRemoteVideoView() -> AnyView {
        AnyView(LiveKitRemoteVideoView(room: room))
    }

    func leave() {
        guard !isLeavingSnapshot else { return }
        invalidateJoin()
        joinTask?.cancel()
        joinTask = nil
        Task { await room.disconnect() }
        hasRemoteVideo = false
        connectionState = .ended
    }

    // MARK: - Remote video state (1:1 — a single partner)

    private func refreshRemoteVideoState() {
        guard !isLeavingSnapshot else { return }
        let anyVideo = room.remoteParticipants.values.contains { $0.firstCameraVideoTrack != nil }
        hasRemoteVideo = anyVideo
        DispatchQueue.main.async {
            self.delegate?.callServiceRemoteVideoBecameAvailable(self)
        }
    }
}

// MARK: - RoomDelegate

extension RealCallService: RoomDelegate {
    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState,
              from oldConnectionState: ConnectionState) {
        switch connectionState {
        case .connecting:
            guard !isLeavingSnapshot else { return }
            self.connectionState = .connecting
        case .reconnecting:
            guard !isLeavingSnapshot else { return }
            self.connectionState = .reconnecting
        case .connected:
            guard !isLeavingSnapshot else { return }
            self.connectionState = .connected
        case .disconnected:
            // Only an explicit local leave is a clean end. Losing the room after
            // it was connected is recoverable/failable UI, not a terminal event
            // that leaves the date screen stuck with no retry affordance.
            self.connectionState = isLeavingSnapshot ? .ended : .failed("Disconnected")
        case .disconnecting:
            break
        @unknown default:
            break
        }
    }

    func room(_ room: Room, participantDidConnect participant: LiveKit.RemoteParticipant) {
        refreshRemoteVideoState()
    }

    func room(_ room: Room, participantDidDisconnect participant: LiveKit.RemoteParticipant) {
        refreshRemoteVideoState()
    }

    func room(_ room: Room, participant: LiveKit.RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication) {
        refreshRemoteVideoState()
    }

    func room(_ room: Room, participant: LiveKit.RemoteParticipant,
              didUnsubscribeTrack publication: RemoteTrackPublication) {
        refreshRemoteVideoState()
    }

    func room(_ room: Room, participant: LiveKit.RemoteParticipant,
              didUnpublishTrack publication: RemoteTrackPublication) {
        refreshRemoteVideoState()
    }
}

// MARK: - SwiftUI video bridges
// Observe the LiveKit participant so the feed appears the moment its camera
// track is published/subscribed (publishing is async after connect).

private struct LiveKitLocalVideoView: View {
    @ObservedObject var participant: LocalParticipant
    var body: some View {
        if let track = participant.firstCameraVideoTrack {
            // .auto mirrors the front camera only — a mirrored back camera
            // reads backwards.
            SwiftUIVideoView(track, layoutMode: .fill, mirrorMode: .auto)
        } else {
            Color.black
        }
    }
}

private struct LiveKitRemoteVideoView: View {
    @ObservedObject var room: Room

    private var partner: LiveKit.RemoteParticipant? { room.remoteParticipants.values.first }

    var body: some View {
        if let partner {
            RemoteParticipantVideo(participant: partner)
        } else {
            Color.black
        }
    }
}

private struct RemoteParticipantVideo: View {
    @ObservedObject var participant: LiveKit.RemoteParticipant
    var body: some View {
        if let track = participant.firstCameraVideoTrack {
            SwiftUIVideoView(track, layoutMode: .fill)
        } else {
            Color.black
        }
    }
}

#endif
