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
    private(set) var remoteParticipants: [RemoteParticipant] = []

    /// Per-participant remote video renderers, keyed by SFU stream id. The SFU
    /// tags each forwarded track's stream with the publisher's identity.
    private var remoteRenderers: [String: RTCMTLVideoView] = [:]
    private var remoteTracks: [String: RTCVideoTrack] = [:]

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
            // .voiceChat engages Apple's Voice-Processing I/O (hardware echo
            // cancellation / noise suppression / AGC) — we keep it because WebRTC
            // relies on it for clean calls. The critical part is the OPTIONS:
            // without these, call audio can't route to Bluetooth/wireless earbuds
            // or wired/USB output (the "earbud plays media but goes silent on a
            // call" bug). allowBluetooth = HFP headsets; allowBluetoothA2DP =
            // AirPods/wireless earbuds; allowAirPlay covers wireless displays.
            let options: AVAudioSession.CategoryOptions =
                [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            try session.setActive(true)
            applyPreferredRoute()
        } catch {
            connectionState = .failed("Audio session error")
        }
        session.unlockForConfiguration()
        observeAudioRouteChanges()
    }

    /// Pick the best available route for a call. Prefer a connected external
    /// device (Bluetooth/AirPods, wired headset/headphones, USB) over the
    /// built-in speaker/earpiece; fall back to speaker for hands-free video,
    /// earpiece for audio-only.
    private func applyPreferredRoute() {
        let av = AVAudioSession.sharedInstance()

        // 1) If an external OUTPUT is already in the current route (e.g. plain
        //    wired headphones, USB-C/Lightning output with no mic, AirPods),
        //    leave it alone — don't force speaker over it.
        let externalOutputs: Set<AVAudioSession.Port> = [
            .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones,
            .usbAudio, .carAudio, .lineOut, .airPlay, .HDMI
        ]
        let outNow = av.currentRoute.outputs.map { $0.portType }
        if outNow.contains(where: { externalOutputs.contains($0) }) {
            return
        }

        // 2) If an external INPUT device is available (wired headset mic,
        //    Bluetooth HFP, USB), prefer it — output follows the device.
        if let inputs = av.availableInputs {
            let externalInputs: [AVAudioSession.Port] =
                [.bluetoothHFP, .headsetMic, .usbAudio, .carAudio, .lineIn]
            if let external = inputs.first(where: { externalInputs.contains($0.portType) }) {
                try? av.setPreferredInput(external)
                return
            }
        }

        // 3) No external device: speaker for video (hands-free), earpiece for audio.
        try? av.setPreferredInput(nil)
        try? av.overrideOutputAudioPort(isVideoEnabled ? .speaker : .none)
    }

    private var routeObserver: NSObjectProtocol?
    private var resetObserver: NSObjectProtocol?

    private func observeAudioRouteChanges() {
        let nc = NotificationCenter.default
        if routeObserver == nil {
            routeObserver = nc.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let self else { return }
                // When a device connects/disconnects, re-apply our preferred
                // route so call audio follows the newly connected earbud.
                let reasonRaw = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
                let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
                if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable
                    || reason == .routeConfigurationChange {
                    let s = RTCAudioSession.sharedInstance()
                    s.lockForConfiguration()
                    self.applyPreferredRoute()
                    s.unlockForConfiguration()
                }
            }
        }
        if resetObserver == nil {
            // The audio stack can reset out from under us; rebuild the session.
            resetObserver = nc.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.configureAudioSession()
            }
        }
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
    func makeRemoteVideoView(for participantId: String) -> AnyView {
        if let view = remoteRenderers[participantId] {
            return AnyView(RTCVideoViewRepresentable(view: view))
        }
        return AnyView(RTCVideoViewRepresentable(view: remoteRenderer))
    }

    func leave() {
        videoCapturer?.stopCapture()
        peerConnection?.close()
        peerConnection = nil
        signaling?.disconnect()
        signaling = nil
        remoteRenderers.removeAll()
        remoteTracks.removeAll()
        remoteParticipants.removeAll()
        if let r = routeObserver { NotificationCenter.default.removeObserver(r); routeObserver = nil }
        if let r = resetObserver { NotificationCenter.default.removeObserver(r); resetObserver = nil }
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
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        // The SFU tags each forwarded track's stream id with the publisher's
        // identity; use it to key per-participant renderers for the group grid.
        let pid = streams.first?.streamId ?? track.trackId
        DispatchQueue.main.async {
            let renderer = RTCMTLVideoView(frame: .zero)
            track.add(renderer)
            self.remoteRenderers[pid] = renderer
            self.remoteTracks[pid] = track
            // Keep the legacy single-remote view pointing at the first track so
            // 1:1 calls keep working unchanged.
            if self.remoteVideoTrack == nil {
                self.remoteVideoTrack = track
                track.add(self.remoteRenderer)
            }
            self.hasRemoteVideo = true
            self.rebuildParticipants()
            self.delegate?.callServiceRemoteVideoBecameAvailable(self)
            self.delegate?.callService(self, didUpdateParticipants: self.remoteParticipants)
        }
    }

    private func rebuildParticipants() {
        remoteParticipants = remoteRenderers.keys.sorted().enumerated().map { _, pid in
            RemoteParticipant(id: pid, displayName: "", hasVideo: true)
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
// The exact framing lives in AGENTS.md; this is the standard offer/answer +
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
        items.append(URLQueryItem(name: "token", value: joinToken))
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
        case "ice":
            if let cand = obj["candidate"] as? String {
                let mid = obj["sdp_mid"] as? String
                let idx = (obj["sdp_mline_index"] as? Int) ?? 0
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
        sendJSON(["type": "ice",
                  "candidate": c.sdp,
                  "sdp_mline_index": Int(c.sdpMLineIndex),
                  "sdp_mid": c.sdpMid as Any])
    }
}

extension SFUSignaling: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.onOpen?() }
    }
}

#endif
