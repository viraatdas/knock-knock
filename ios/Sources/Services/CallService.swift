import Foundation
import SwiftUI

// MARK: - CallService protocol

enum CallConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    case failed(String)
    case ended
}

/// One remote person in a (possibly group) call. `id` is the SFU-assigned track
/// stream identity; `hasVideo` drives whether we show their feed or an avatar.
struct RemoteParticipant: Identifiable, Equatable {
    let id: String
    var displayName: String
    var hasVideo: Bool
    /// True when their microphone is muted — shown so nobody does the
    /// "can you hear me?" dance.
    var isAudioMuted: Bool = false
}

protocol CallServiceDelegate: AnyObject {
    func callService(_ service: CallService, didChange state: CallConnectionState)
    func callServiceRemoteVideoBecameAvailable(_ service: CallService)
    /// Fired whenever the set of remote participants changes (join/leave/video).
    func callService(_ service: CallService, didUpdateParticipants participants: [RemoteParticipant])
}

extension CallServiceDelegate {
    // Optional: 1:1-only services need not implement roster updates.
    func callService(_ service: CallService, didUpdateParticipants participants: [RemoteParticipant]) {}
}

/// Abstracts the WebRTC media layer. A real implementation (RealCallService)
/// wires `RTCPeerConnection` to the SFU; a mock (MockCallService) renders the
/// in-call UI in the simulator without media.
protocol CallService: AnyObject {
    var delegate: CallServiceDelegate? { get set }
    var connectionState: CallConnectionState { get }

    /// Whether the remote/local feeds are available (drives UI placeholders).
    var hasRemoteVideo: Bool { get }
    var isMuted: Bool { get }
    var isVideoEnabled: Bool { get }
    var isUsingFrontCamera: Bool { get }

    /// All remote participants currently in the call (empty for a 1:1 that hasn't
    /// connected). For 1:1 calls this holds a single entry once connected.
    var remoteParticipants: [RemoteParticipant] { get }

    /// Join a room described by the control-plane response.
    func join(session: CallSession, videoEnabled: Bool)

    func setMuted(_ muted: Bool)
    func setVideoEnabled(_ enabled: Bool)
    func flipCamera()

    /// Provide SwiftUI views for local/remote video (real impl returns RTC views;
    /// mock returns placeholders).
    func makeLocalVideoView() -> AnyView
    func makeRemoteVideoView() -> AnyView
    /// Video view for a specific remote participant (group grid). Falls back to
    /// the single remote view when a service doesn't track per-participant feeds.
    func makeRemoteVideoView(for participantId: String) -> AnyView

    func leave()
}

extension CallService {
    func makeRemoteVideoView(for participantId: String) -> AnyView { makeRemoteVideoView() }
    var remoteParticipants: [RemoteParticipant] { [] }
    /// 1pt view the call screen must host so system Picture-in-Picture can
    /// take over the remote feed on backgrounding. Nil when unsupported.
    func makePiPAnchorView() -> AnyView? { nil }
}

// MARK: - Mock implementation (default in simulator)

final class MockCallService: CallService {
    weak var delegate: CallServiceDelegate?
    private(set) var connectionState: CallConnectionState = .idle {
        didSet { delegate?.callService(self, didChange: connectionState) }
    }
    private(set) var hasRemoteVideo: Bool = false
    private(set) var isMuted: Bool = false
    private(set) var isVideoEnabled: Bool = true
    private(set) var isUsingFrontCamera: Bool = true
    private(set) var remoteParticipants: [RemoteParticipant] = []

    /// Names to populate the mock roster with (set by the view model from the
    /// ActiveCall's member list so the simulator renders a real group grid).
    var mockMemberNames: [String] = []

    func join(session: CallSession, videoEnabled: Bool) {
        isVideoEnabled = videoEnabled
        connectionState = .connecting
        // Simulate a fast connect.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.connectionState = .connected
            let names = self.mockMemberNames.isEmpty ? ["Remote"] : self.mockMemberNames
            self.remoteParticipants = names.enumerated().map { idx, name in
                RemoteParticipant(id: "mock-\(idx)", displayName: name, hasVideo: videoEnabled)
            }
            if videoEnabled {
                self.hasRemoteVideo = true
                self.delegate?.callServiceRemoteVideoBecameAvailable(self)
            }
            self.delegate?.callService(self, didUpdateParticipants: self.remoteParticipants)
        }
    }

    func setMuted(_ muted: Bool) { isMuted = muted }
    func setVideoEnabled(_ enabled: Bool) {
        isVideoEnabled = enabled
        hasRemoteVideo = enabled
    }
    func flipCamera() { isUsingFrontCamera.toggle() }

    func makeLocalVideoView() -> AnyView {
        AnyView(MockVideoPlaceholder(kind: .local))
    }
    func makeRemoteVideoView(for participantId: String) -> AnyView {
        // Deterministic per-participant tint so grid tiles look distinct.
        AnyView(MockVideoPlaceholder(kind: .remote, seed: participantId))
    }
    func makeRemoteVideoView() -> AnyView {
        AnyView(MockVideoPlaceholder(kind: .remote))
    }

    func leave() {
        connectionState = .ended
        hasRemoteVideo = false
    }
}

/// A quiet placeholder feed used by the mock so the in-call screen renders
/// beautifully in the simulator. Subtle moving hairline, on-brand.
struct MockVideoPlaceholder: View {
    enum Kind { case local, remote }
    let kind: Kind
    var seed: String = ""
    @State private var phase: CGFloat = 0

    private var tint: Color {
        guard kind == .remote, !seed.isEmpty else {
            return kind == .remote ? Theme.Color.text : Theme.Color.bgGrouped
        }
        // Deterministic dark tint per participant so grid tiles read as distinct.
        let h = Double(abs(seed.hashValue) % 360) / 360.0
        return Color(hue: h, saturation: 0.18, brightness: 0.16)
    }

    var body: some View {
        ZStack {
            // Remote = near-black "video" surface; local = soft gray.
            tint
            GeometryReader { geo in
                Path { p in
                    let y = geo.size.height * 0.5
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(
                    (kind == .remote ? Color.white.opacity(0.06) : Theme.Color.hairline),
                    lineWidth: 1
                )
                .offset(y: phase)
            }
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: kind == .remote ? "video" : "person.crop.circle")
                    .font(.system(size: kind == .remote ? 30 : 20, weight: .light))
                    .foregroundStyle(kind == .remote ? Color.white.opacity(0.35)
                                                      : Theme.Color.textSecondary)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                phase = 40
            }
        }
    }
}

// MARK: - Factory

enum CallServiceFactory {
    static func make() -> CallService {
        if Config.useMockCallService {
            return MockCallService()
        }
        #if canImport(LiveKit)
        return RealCallService()
        #else
        return MockCallService()
        #endif
    }
}
