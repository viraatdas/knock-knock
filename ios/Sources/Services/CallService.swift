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

protocol CallServiceDelegate: AnyObject {
    func callService(_ service: CallService, didChange state: CallConnectionState)
    func callServiceRemoteVideoBecameAvailable(_ service: CallService)
}

/// Abstracts the WebRTC media layer for a single 1:1 date. A real
/// implementation (RealCallService) wires LiveKit to the SFU; a mock
/// (MockCallService) renders the in-date UI in the simulator without media.
protocol CallService: AnyObject {
    var delegate: CallServiceDelegate? { get set }
    var connectionState: CallConnectionState { get }

    /// Whether the remote feed is available (drives UI placeholders).
    var hasRemoteVideo: Bool { get }
    var isMuted: Bool { get }
    var isVideoEnabled: Bool { get }
    var isUsingFrontCamera: Bool { get }

    /// Join the date's room described by the control-plane response.
    func join(session: DateSession, videoEnabled: Bool)

    func setMuted(_ muted: Bool)
    func setVideoEnabled(_ enabled: Bool)
    func flipCamera()

    /// SwiftUI views for local/remote video (real impl returns RTC views;
    /// mock returns placeholders).
    func makeLocalVideoView() -> AnyView
    func makeRemoteVideoView() -> AnyView

    func leave()
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
    /// The date partner's id, so `makeRemoteVideoView` can show their mock
    /// photo under `-mockPhotosDir` (DEBUG screenshots only).
    private var partnerId: String?

    func join(session: DateSession, videoEnabled: Bool) {
        partnerId = session.partner.id
        isVideoEnabled = videoEnabled
        connectionState = .connecting
        // Simulate a fast connect.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.connectionState = .connected
            if videoEnabled {
                self.hasRemoteVideo = true
                self.delegate?.callServiceRemoteVideoBecameAvailable(self)
            }
        }
    }

    func setMuted(_ muted: Bool) { isMuted = muted }
    func setVideoEnabled(_ enabled: Bool) {
        isVideoEnabled = enabled
        hasRemoteVideo = enabled
    }
    func flipCamera() { isUsingFrontCamera.toggle() }

    func makeLocalVideoView() -> AnyView {
        AnyView(MockVideoPlaceholder(kind: .local, userId: "u_me"))
    }
    func makeRemoteVideoView() -> AnyView {
        AnyView(MockVideoPlaceholder(kind: .remote, userId: partnerId))
    }

    func leave() {
        connectionState = .ended
        hasRemoteVideo = false
    }
}

/// A quiet placeholder feed used by the mock so the date screen renders
/// beautifully in the simulator. Subtle moving hairline, on-brand.
struct MockVideoPlaceholder: View {
    enum Kind { case local, remote }
    let kind: Kind
    /// Whose feed this stands in for ("u_me" for local, the partner's id for
    /// remote) — only consulted under `-mockPhotosDir` (DEBUG screenshots).
    var userId: String? = nil
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            #if DEBUG
            if let userId, let photo = MockPhotoAvatars.image(for: userId) {
                GeometryReader { geo in
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                phase = 40
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            // Remote = near-black "video" surface; local = soft gray.
            kind == .remote ? Theme.Color.text : Theme.Color.bgGrouped
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
            Image(systemName: kind == .remote ? "video" : "person.crop.circle")
                .font(.system(size: kind == .remote ? 30 : 20, weight: .light))
                .foregroundStyle(kind == .remote ? Color.white.opacity(0.35)
                                                  : Theme.Color.textSecondary)
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
