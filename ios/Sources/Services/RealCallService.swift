import Foundation
import SwiftUI
import AVFoundation

#if canImport(LiveKit)
import LiveKit

/// Real media via the self-hosted **LiveKit** SFU. The control plane (`/calls`)
/// returns `session.sfuUrl` (LiveKit ws URL) + `session.joinToken` (a LiveKit
/// access token scoped to room = call id); both participants join the same room.
///
/// Replaces the old custom-SFU `RTCPeerConnection` client (webrtc-rs SFU couldn't
/// complete DTLS over real networks). LiveKit handles ICE/DTLS/TURN + a TCP
/// fallback, so calls connect even on UDP-restricted networks.
final class RealCallService: NSObject, CallService, @unchecked Sendable {
    weak var delegate: CallServiceDelegate?

    /// The LiveKit room. Held for the lifetime of the call; the SwiftUI video
    /// views observe it (and its participants) for track updates.
    ///
    /// Audio tuning: full voice processing (echo cancellation + noise
    /// suppression + auto gain) and DTX off — DTX stops sending packets during
    /// silence, which can make quiet speech sound gated/choppy on flaky links.
    /// Continuous Opus at a steady bitrate sounds noticeably smoother.
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
        didSet { DispatchQueue.main.async { self.delegate?.callService(self, didChange: self.connectionState) } }
    }
    private(set) var hasRemoteVideo = false
    private(set) var isMuted = false
    private(set) var isVideoEnabled = true
    private(set) var isUsingFrontCamera = true
    private(set) var remoteParticipants: [RemoteParticipant] = []

    override init() {
        super.init()
        room.add(delegate: self)
    }

    // MARK: - Join

    func join(session: CallSession, videoEnabled: Bool) {
        isVideoEnabled = videoEnabled
        connectionState = .connecting
        let url = session.sfuUrl
        let token = session.joinToken
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.room.connect(url: url, token: token)
                try await self.room.localParticipant.setMicrophone(enabled: true)
                if videoEnabled {
                    try await self.room.localParticipant.setCamera(enabled: true)
                    Self.preferSpeakerIfOnEarpiece()
                }
            } catch {
                self.connectionState = .failed("Couldn't connect")
            }
        }
    }

    // MARK: - Controls

    func setMuted(_ muted: Bool) {
        isMuted = muted
        Task { try? await room.localParticipant.setMicrophone(enabled: !muted) }
    }

    func setVideoEnabled(_ enabled: Bool) {
        isVideoEnabled = enabled
        Task {
            try? await room.localParticipant.setCamera(enabled: enabled)
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
        isUsingFrontCamera.toggle()
        Task {
            guard let track = room.localParticipant.firstCameraVideoTrack as? LocalVideoTrack,
                  let capturer = track.capturer as? CameraCapturer else { return }
            _ = try? await capturer.switchCameraPosition()
        }
    }

    // MARK: - Video views

    func makeLocalVideoView() -> AnyView {
        AnyView(LiveKitLocalVideoView(participant: room.localParticipant))
    }
    func makeRemoteVideoView() -> AnyView {
        AnyView(LiveKitRemoteVideoView(room: room, participantId: nil))
    }
    func makeRemoteVideoView(for participantId: String) -> AnyView {
        AnyView(LiveKitRemoteVideoView(room: room, participantId: participantId))
    }

    func leave() {
        Task { await room.disconnect() }
        remoteParticipants = []
        hasRemoteVideo = false
        connectionState = .ended
    }

    // MARK: - Roster

    private func rebuildParticipants() {
        let ps = Array(room.remoteParticipants.values)
        let mapped = ps.map { p in
            RemoteParticipant(
                id: p.identity?.stringValue ?? p.sid?.stringValue ?? UUID().uuidString,
                displayName: p.name ?? "",
                hasVideo: p.firstCameraVideoTrack != nil)
        }
        remoteParticipants = mapped
        DispatchQueue.main.async {
            self.delegate?.callService(self, didUpdateParticipants: mapped)
        }
        refreshRemoteVideoState()
    }

    private func refreshRemoteVideoState() {
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
            self.connectionState = .connecting
        case .reconnecting:
            self.connectionState = .reconnecting
        case .connected:
            self.connectionState = .connected
        case .disconnected:
            // A clean disconnect after a real session = call ended; otherwise it
            // never connected → surface a failure.
            let wasUp = oldConnectionState == .connected || oldConnectionState == .reconnecting
            self.connectionState = wasUp ? .ended : .failed("Disconnected")
        case .disconnecting:
            break
        @unknown default:
            break
        }
    }

    func room(_ room: Room, participantDidConnect participant: LiveKit.RemoteParticipant) {
        rebuildParticipants()
    }

    func room(_ room: Room, participantDidDisconnect participant: LiveKit.RemoteParticipant) {
        rebuildParticipants()
    }

    func room(_ room: Room, participant: LiveKit.RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication) {
        rebuildParticipants()
    }

    func room(_ room: Room, participant: LiveKit.RemoteParticipant,
              didUnsubscribeTrack publication: RemoteTrackPublication) {
        rebuildParticipants()
    }

    func room(_ room: Room, participant: LiveKit.RemoteParticipant,
              didUnpublishTrack publication: RemoteTrackPublication) {
        rebuildParticipants()
    }

    func room(_ room: Room, participant: Participant,
              trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        rebuildParticipants()
    }
}

// MARK: - SwiftUI video bridges
// Observe the LiveKit participant so the feed appears the moment its camera
// track is published/subscribed (publishing is async after connect).

private struct LiveKitLocalVideoView: View {
    @ObservedObject var participant: LocalParticipant
    var body: some View {
        if let track = participant.firstCameraVideoTrack {
            SwiftUIVideoView(track, layoutMode: .fill, mirrorMode: .mirror)
        } else {
            Color.black
        }
    }
}

private struct LiveKitRemoteVideoView: View {
    @ObservedObject var room: Room
    let participantId: String?

    private var participant: LiveKit.RemoteParticipant? {
        let values = room.remoteParticipants.values
        if let id = participantId {
            return values.first { $0.identity?.stringValue == id }
        }
        return values.first
    }

    var body: some View {
        if let participant {
            RemoteParticipantVideo(participant: participant)
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
