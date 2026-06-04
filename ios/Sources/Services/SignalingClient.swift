import Foundation

// MARK: - Signaling events (server -> client)

enum SignalingEvent {
    case incomingCall(callId: String, fromUserId: String?, fromName: String?, type: CallType)
    case callAccepted(callId: String, byUserId: String?)
    case callDeclined(callId: String, byUserId: String?)
    case callEnded(callId: String)
    case participantJoined(callId: String, userId: String)
    case participantLeft(callId: String, userId: String)
    case presenceUpdate(userId: String, online: Bool)
    case unknown(type: String)
}

protocol SignalingClientDelegate: AnyObject {
    func signaling(_ client: SignalingClient, didReceive event: SignalingEvent)
    func signalingDidConnect(_ client: SignalingClient)
    func signalingDidDisconnect(_ client: SignalingClient)
}

/// App-plane WebSocket: `GET /v1/ws?token=<accessToken>`.
/// Handles incoming_call/call_accepted/etc with reconnect + exponential backoff.
final class SignalingClient: NSObject, @unchecked Sendable {
    weak var delegate: SignalingClientDelegate?

    private let baseURL: URL
    private let tokens: TokenStore
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?

    private var isStarted = false
    private var reconnectAttempt = 0
    private var heartbeatTimer: Timer?
    private let queue = DispatchQueue(label: "app.slide.signaling")

    init(baseURL: URL = Config.apiBaseURL, tokens: TokenStore = .shared) {
        self.baseURL = baseURL
        self.tokens = tokens
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: Lifecycle

    func connect() {
        queue.async { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true
            self.openSocket()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStarted = false
            self.stopHeartbeat()
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
        }
    }

    // MARK: Internal

    private func wsURL() -> URL? {
        guard let token = tokens.accessToken else { return nil }
        // Derive ws(s) scheme from the http(s) base.
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = (baseURL.scheme == "https") ? "wss" : "ws"
        // baseURL path already ends with /v1 — append /ws.
        let basePath = components.path
        components.path = basePath + "/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private func openSocket() {
        guard isStarted, let url = wsURL() else { return }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop()
        startHeartbeat()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handle(message)
                self.receiveLoop()
            case .failure:
                self.handleDisconnect()
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

        let event = Self.parse(type: type, obj: obj)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.signaling(self, didReceive: event)
        }
    }

    static func parse(type: String, obj: [String: Any]) -> SignalingEvent {
        switch type {
        case "incoming_call":
            let typeStr = obj["callType"] as? String ?? obj["type2"] as? String
            let call = obj["call"] as? [String: Any]
            let from = obj["from"] as? [String: Any]
            let callType = CallType(rawValue: typeStr ?? "one_to_one") ?? .oneToOne
            return .incomingCall(
                callId: (obj["callId"] as? String) ?? (obj["id"] as? String) ?? (call?["id"] as? String) ?? "",
                fromUserId: obj["fromUserId"] as? String ?? (obj["from"] as? String) ?? (from?["id"] as? String),
                fromName: obj["fromName"] as? String ?? obj["fromDisplayName"] as? String
                    ?? (from?["displayName"] as? String) ?? (from?["phone"] as? String),
                type: callType)
        case "call_accepted":
            return .callAccepted(callId: callIdOf(obj), byUserId: obj["byUserId"] as? String)
        case "call_declined":
            return .callDeclined(callId: callIdOf(obj), byUserId: obj["byUserId"] as? String)
        case "call_ended":
            return .callEnded(callId: callIdOf(obj))
        case "participant_joined":
            return .participantJoined(callId: callIdOf(obj), userId: obj["userId"] as? String ?? "")
        case "participant_left":
            return .participantLeft(callId: callIdOf(obj), userId: obj["userId"] as? String ?? "")
        case "presence_update":
            return .presenceUpdate(userId: obj["userId"] as? String ?? "",
                                   online: obj["online"] as? Bool ?? false)
        default:
            return .unknown(type: type)
        }
    }

    private static func callIdOf(_ obj: [String: Any]) -> String {
        (obj["callId"] as? String) ?? (obj["id"] as? String) ?? ""
    }

    // MARK: Outbound

    func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(string)) { _ in }
    }

    func presencePing() { send(["type": "presence_ping"]) }
    private func heartbeat() { send(["type": "heartbeat"]) }

    private func startHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { _ in
                self?.queue.async { self?.heartbeat() }
            }
        }
    }

    private func stopHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = nil
        }
    }

    // MARK: Reconnect with exponential backoff

    private func handleDisconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopHeartbeat()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.signalingDidDisconnect(self)
            }
            guard self.isStarted else { return }
            self.reconnectAttempt += 1
            let delay = min(pow(2.0, Double(self.reconnectAttempt)), 30.0)
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.openSocket()
            }
        }
    }
}

extension SignalingClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        reconnectAttempt = 0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.signalingDidConnect(self)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        handleDisconnect()
    }
}
