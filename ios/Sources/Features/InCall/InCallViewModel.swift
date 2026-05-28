import SwiftUI
import Combine

@MainActor
final class InCallViewModel: ObservableObject {
    @Published var connectionState: CallConnectionState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var isMuted = false
    @Published var isVideoEnabled: Bool
    @Published var hasRemoteVideo = false

    let service: CallService
    private weak var call: ActiveCall?
    private var timer: Timer?
    private var startedAt: Date?
    private var delegateBox: Delegate?

    init(call: ActiveCall) {
        self.call = call
        self.isVideoEnabled = call.isVideo
        self.service = CallServiceFactory.make()
        let box = Delegate(owner: self)
        self.delegateBox = box
        self.service.delegate = box
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
        case .connected: return timerText
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
        if state == .connected, startedAt == nil {
            startedAt = Date()
            startTimer()
        }
    }

    fileprivate func remoteVideoAvailable() {
        hasRemoteVideo = service.hasRemoteVideo
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
    }
}
