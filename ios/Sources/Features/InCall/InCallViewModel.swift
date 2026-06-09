import SwiftUI
import Combine

@MainActor
final class InCallViewModel: ObservableObject {
    @Published var connectionState: CallConnectionState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var isMuted = false
    @Published var isVideoEnabled: Bool
    @Published var hasRemoteVideo = false
    @Published var remoteParticipants: [RemoteParticipant] = []
    /// True once the other person has actually joined the room. Until then the
    /// call is still "ringing" from the user's perspective, even though we're
    /// already connected to the media server ourselves.
    @Published var remoteJoined = false

    let service: CallService
    let isGroup: Bool
    let isKnock: Bool
    let isOutgoing: Bool
    private let memberNames: [String]
    private weak var call: ActiveCall?
    private var timer: Timer?
    private var startedAt: Date?
    private var delegateBox: Delegate?

    init(call: ActiveCall) {
        self.call = call
        self.isVideoEnabled = call.isVideo
        self.isGroup = call.isGroup
        self.isKnock = call.isKnock
        self.isOutgoing = call.direction == .outgoing
        self.memberNames = call.memberNames
        self.service = CallServiceFactory.make()
        // Seed the mock roster so the simulator renders a real group grid.
        if let mock = service as? MockCallService {
            mock.mockMemberNames = call.memberNames
        }
        let box = Delegate(owner: self)
        self.delegateBox = box
        self.service.delegate = box
    }

    /// Participants with display names filled in from the call's member list
    /// (the SFU doesn't carry names, so we map by position for the roster).
    var displayParticipants: [RemoteParticipant] {
        remoteParticipants.enumerated().map { idx, p in
            var copy = p
            if copy.displayName.isEmpty, idx < memberNames.count {
                copy.displayName = memberNames[idx]
            }
            return copy
        }
    }

    var timerText: String {
        let total = Int(elapsed)
        let m = total / 60, s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    var statusText: String {
        switch connectionState {
        case .idle, .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .failed: return "Call failed"
        case .connected:
            // We're in the room, but the call hasn't "started" until the other
            // person joins — show ringing, not a ticking timer.
            if remoteJoined { return timerText }
            if isOutgoing { return isKnock ? "Knocking…" : "Ringing…" }
            return "Connecting…"
        case .ended: return "Call ended"
        }
    }

    func start() {
        guard let call else { return }
        // Wait for the control-plane session, then join.
        if let session = call.session {
            join(session)
        } else {
            // Poll briefly for the session created asynchronously.
            Task { @MainActor in
                for _ in 0..<40 where call.session == nil {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if let session = call.session { join(session) }
            }
        }
    }

    private func join(_ session: CallSession) {
        service.join(session: session, videoEnabled: isVideoEnabled)
    }

    func toggleMute() {
        isMuted.toggle()
        service.setMuted(isMuted)
    }

    func toggleVideo() {
        isVideoEnabled.toggle()
        service.setVideoEnabled(isVideoEnabled)
    }

    func flipCamera() { service.flipCamera() }

    func end() {
        timer?.invalidate()
        service.leave()
    }

    fileprivate func handleStateChange(_ state: CallConnectionState) {
        connectionState = state
        switch state {
        case .failed:
            Haptics.error()
        case .ended:
            if remoteJoined { SoundEffects.ended() }
        default:
            break
        }
    }

    fileprivate func remoteVideoAvailable() {
        hasRemoteVideo = service.hasRemoteVideo
    }

    fileprivate func participantsChanged(_ participants: [RemoteParticipant]) {
        remoteParticipants = participants
        // First remote participant = the moment the call truly begins: start
        // the timer and celebrate with a haptic + a tiny chime.
        if !participants.isEmpty, !remoteJoined {
            remoteJoined = true
            Haptics.success()
            SoundEffects.connected()
            if startedAt == nil {
                startedAt = Date()
                startTimer()
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    /// Bridges the non-isolated delegate callbacks back to the main actor.
    private final class Delegate: CallServiceDelegate {
        weak var owner: InCallViewModel?
        init(owner: InCallViewModel) { self.owner = owner }
        func callService(_ service: CallService, didChange state: CallConnectionState) {
            Task { @MainActor in self.owner?.handleStateChange(state) }
        }
        func callServiceRemoteVideoBecameAvailable(_ service: CallService) {
            Task { @MainActor in self.owner?.remoteVideoAvailable() }
        }
        func callService(_ service: CallService, didUpdateParticipants participants: [RemoteParticipant]) {
            Task { @MainActor in self.owner?.participantsChanged(participants) }
        }
    }
}
