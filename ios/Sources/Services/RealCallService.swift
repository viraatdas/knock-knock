import Foundation
import SwiftUI

#if canImport(WebRTC)
import WebRTC

/// Real WebRTC implementation. Connects an `RTCPeerConnection` to the SFU at
/// `session.sfuUrl` (plane B), authenticated by the room-scoped `joinToken`,
/// using the `iceServers` from the /calls response.
///
/// Media is verified on a physical device; the simulator defaults to the mock
/// (Config.useMockCallService == true). This file compiles only when the
/// stasel/WebRTC package is resolved.
final class RealCallService: NSObject, CallService, @unchecked Sendable {
    weak var delegate: CallServiceDelegate?

    private(set) var connectionState: CallConnectionState = .idle {
        didSet { DispatchQueue.main.async { self.delegate?.callService(self, didChange: self.connectionState) } }
    }
    private(set) var hasRemoteVideo: Bool = false
    private(set) var isMuted: Bool = false
    private(set) var isVideoEnabled: Bool = true
    private(set) var isUsingFrontCamera: Bool = true

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()

    private var peerConnection: RTCPeerConnection?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var videoCapturer: RTCCameraVideoCapturer?

    private var signaling: SFUSignaling?
    private var session: CallSession?

    // RTCMTLVideoView is UIKit/main-actor; create lazily on first use (always
    // from the main thread via the SwiftUI representable below).
    private lazy var localRenderer = RTCMTLVideoView(frame: .zero)
    private lazy var remoteRenderer = RTCMTLVideoView(frame: .zero)

    // MARK: - Join

    func join(session: CallSession, videoEnabled: Bool) {
        self.session = session
        self.isVideoEnabled = videoEnabled
        connectionState = .connecting

        let rtcIce = session.iceServers.map { server -> RTCIceServer in
            RTCIceServer(urlStrings: server.urls,
                         username: server.username,
                         credential: server.credential)
        }
        let config = RTCConfiguration()
        config.iceServers = rtcIce
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])

        peerConnection = Self.factory.peerConnection(with: config,
                                                     constraints: constraints,
                                                     delegate: self)
        configureAudioSession()
        addLocalMedia(videoEnabled: videoEnabled)
        connectSignaling(url: session.sfuUrl, joinToken: session.joinToken)
    }

    private func configureAudioSession() {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [])
            try session.setActive(true)
        } catch {
            connectionState = .failed("Audio session error")
        }
        session.unlockForConfiguration()
    }

    private func addLocalMedia(videoEnabled: Bool) {
        guard let pc = peerConnection else { return }
        let streamId = "local"

        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = Self.factory.audioSource(with: audioConstraints)
        let audioTrack = Self.factory.audioTrack(with: audioSource, trackId: "audio0")
        self.localAudioTrack = audioTrack
        pc.add(audioTrack, streamIds: [streamId])

        if videoEnabled {
            let videoSource = Self.factory.videoSource()
            let capturer = RTCCameraVideoCapturer(delegate: videoSource)
            self.videoCapturer = capturer
            let videoTrack = Self.factory.videoTrack(with: videoSource, trackId: "video0")
            self.localVideoTrack = videoTrack
            pc.add(videoTrack, streamIds: [streamId])
            videoTrack.add(localRenderer)
            startCapture()
        }
    }

    private func startCapture() {
        guard let capturer = videoCapturer else { return }
        let position: AVCaptureDevice.Position = isUsingFrontCamera ? .front : .back
        guard let device = RTCCameraVideoCapturer.captureDevices()
            .first(where: { $0.position == position }) else { return }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = formats.max(by: { f1, f2 in
            let d1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription)
            let d2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription)
            return d1.width * d1.height < d2.width * d2.height
        }) else { return }
        let fps = format.videoSupportedFrameRateRanges
            .map { $0.maxFrameRate }.max() ?? 30
        capturer.startCapture(with: device, format: format, fps: Int(min(fps, 30)))
    }

    private func connectSignaling(url: String, joinToken: String) {
        guard let sfu = URL(string: url) else {
            connectionState = .failed("Bad SFU URL")
            return
        }
        let signaling = SFUSignaling(url: sfu, joinToken: joinToken)
        signaling.onRemoteDescription = { [weak self] sdp in self?.applyRemote(sdp: sdp) }
        signaling.onRemoteCandidate = { [weak self] cand in self?.peerConnection?.add(cand) { _ in } }
        signaling.onOpen = { [weak self] in self?.makeOffer() }
        self.signaling = signaling
        signaling.connect()
    }

    private func makeOffer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": isVideoEnabled ? "true" : "false"
        ], optionalConstraints: nil)
        peerConnection?.offer(for: constraints) { [weak self] sdp, _ in
            guard let self, let sdp else { return }
            self.peerConnection?.setLocalDescription(sdp) { _ in
                self.signaling?.sendOffer(sdp)
            }
        }
    }

    private func applyRemote(sdp: RTCSessionDescription) {
        peerConnection?.setRemoteDescription(sdp) { [weak self] _ in
            guard let self else { return }
            if sdp.type == .offer {
                let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                self.peerConnection?.answer(for: constraints) { answer, _ in
                    guard let answer else { return }
                    self.peerConnection?.setLocalDescription(answer) { _ in
                        self.signaling?.sendAnswer(answer)
                    }
                }
            }
        }
    }

    // MARK: - Controls

    func setMuted(_ muted: Bool) {
        isMuted = muted
        localAudioTrack?.isEnabled = !muted
    }

    func setVideoEnabled(_ enabled: Bool) {
        isVideoEnabled = enabled
        localVideoTrack?.isEnabled = enabled
    }

    func flipCamera() {
        isUsingFrontCamera.toggle()
        videoCapturer?.stopCapture { [weak self] in self?.startCapture() }
    }

    func makeLocalVideoView() -> AnyView { AnyView(RTCVideoViewRepresentable(view: localRenderer)) }
    func makeRemoteVideoView() -> AnyView { AnyView(RTCVideoViewRepresentable(view: remoteRenderer)) }

    func leave() {
        videoCapturer?.stopCapture()
        peerConnection?.close()
        peerConnection = nil
        signaling?.disconnect()
        signaling = nil
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        try? audio.setActive(false)
        audio.unlockForConfiguration()
        connectionState = .ended
    }
}

// MARK: - RTCPeerConnectionDelegate

extension RealCallService: RTCPeerConnectionDelegate {
    func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        signaling?.sendCandidate(candidate)
    }

    func peerConnection(_ pc: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver,
                        streams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCVideoTrack {
            self.remoteVideoTrack = track
            track.add(remoteRenderer)
            self.hasRemoteVideo = true
            DispatchQueue.main.async { self.delegate?.callServiceRemoteVideoBecameAvailable(self) }
        }
    }

    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed: connectionState = .connected
        case .disconnected: connectionState = .reconnecting
        case .failed: connectionState = .failed("ICE failed")
        case .closed: connectionState = .ended
        default: break
        }
    }

    func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - RTC video view bridge

struct RTCVideoViewRepresentable: UIViewRepresentable {
    let view: RTCMTLVideoView
    func makeUIView(context: Context) -> RTCMTLVideoView {
        view.videoContentMode = .scaleAspectFill
        return view
    }
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {}
}

// MARK: - SFU signaling (plane B)
// Minimal SDP/ICE trickle over WebSocket, authenticated by joinToken.
// The exact framing lives in docs/SFU.md; this is the standard offer/answer +
// trickle shape and is the integration point to adjust to that spec.

final class SFUSignaling: NSObject {
    private let url: URL
    private let joinToken: String
    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    var onOpen: (() -> Void)?
    var onRemoteDescription: ((RTCSessionDescription) -> Void)?
    var onRemoteCandidate: ((RTCIceCandidate) -> Void)?

    init(url: URL, joinToken: String) {
        self.url = url
        self.joinToken = joinToken
    }

    func connect() {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "joinToken", value: joinToken))
        comps?.queryItems = items
        guard let full = comps?.url else { return }
        let task = session.webSocketTask(with: full)
        self.task = task
        task.resume()
        receive()
    }

    func disconnect() { task?.cancel(with: .goingAway, reason: nil); task = nil }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            if case .success(let message) = result {
                self.handle(message)
                self.receive()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let s): data = s.data(using: .utf8)
        case .data(let d): data = d
        @unknown default: data = nil
        }
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "offer", "answer":
            if let sdp = obj["sdp"] as? String {
                let rtcType: RTCSdpType = (type == "offer") ? .offer : .answer
                onRemoteDescription?(RTCSessionDescription(type: rtcType, sdp: sdp))
            }
        case "candidate":
            if let cand = obj["candidate"] as? String {
                let mid = obj["sdpMid"] as? String
                let idx = (obj["sdpMLineIndex"] as? Int) ?? 0
                onRemoteCandidate?(RTCIceCandidate(sdp: cand, sdpMLineIndex: Int32(idx), sdpMid: mid))
            }
        default: break
        }
    }

    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { _ in }
    }

    func sendOffer(_ sdp: RTCSessionDescription) {
        sendJSON(["type": "offer", "sdp": sdp.sdp])
    }
    func sendAnswer(_ sdp: RTCSessionDescription) {
        sendJSON(["type": "answer", "sdp": sdp.sdp])
    }
    func sendCandidate(_ c: RTCIceCandidate) {
        sendJSON(["type": "candidate",
                  "candidate": c.sdp,
                  "sdpMLineIndex": Int(c.sdpMLineIndex),
                  "sdpMid": c.sdpMid as Any])
    }
}

extension SFUSignaling: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.onOpen?() }
    }
}

#endif
