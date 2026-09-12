import Foundation

// MARK: - Signaling events (server -> client), SPEC §1.9

enum SignalingEvent {
    case dateMatched(DateSession)
    case dateEnded(dateId: String, reason: String)
    case matchMade(MatchSummary)
    case matchRemoved(matchId: String)
    case message(matchId: String, message: Message)
    case connected
    case unknown(type: String)
}

protocol SignalingClientDelegate: AnyObject {
    func signaling(_ client: SignalingClient, didReceive event: SignalingEvent)
    func signalingDidConnect(_ client: SignalingClient)
    func signalingDidDisconnect(_ client: SignalingClient)
}

/// App-plane WebSocket: `GET /v1/ws?token=<accessToken>`.
/// Handles date_matched/date_ended/match_made/match_removed/message/connected
/// with reconnect + exponential backoff and a 25s client heartbeat.
final class SignalingClient: NSObject, @unchecked Sendable {
    weak var delegate: SignalingClientDelegate?

    private let baseURL: URL
    private let tokens: TokenStore
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?

    private var isStarted = false
    private var reconnectAttempt = 0
    private var heartbeatTimer: DispatchSourceTimer?
    private var socketGeneration = 0
    private var retryGeneration = 0
    private let queue = DispatchQueue(label: "app.slide.signaling")

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601WithFractional
        return d
    }()

    init(baseURL: URL = Config.apiBaseURL, tokens: TokenStore = .shared) {
        self.baseURL = baseURL
        self.tokens = tokens
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: Lifecycle

    func connect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStarted = true
            guard self.task == nil else { return }
            self.openSocket()
        }
    }

    /// Cancel a stale/suspended socket and connect immediately. Foregrounding
    /// calls this so `connect()` cannot be a no-op merely because an old task
    /// still exists locally.
    func reconnectNow() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStarted = true
            self.retryGeneration += 1
            self.reconnectAttempt = 0
            self.stopHeartbeat()
            let oldTask = self.task
            self.task = nil
            oldTask?.cancel(with: .goingAway, reason: nil)
            self.openSocket()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStarted = false
            self.retryGeneration += 1
            self.stopHeartbeat()
            let oldTask = self.task
            self.task = nil
            oldTask?.cancel(with: .goingAway, reason: nil)
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
        socketGeneration += 1
        let generation = socketGeneration
        self.task = task
        task.resume()
        receiveLoop(task: task, generation: generation)
    }

    private func receiveLoop(task: URLSessionWebSocketTask, generation: Int) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.task === task, self.socketGeneration == generation else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveLoop(task: task, generation: generation)
                case .failure:
                    self.handleDisconnect(task: task, generation: generation)
                }
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
              let raw = try? JSONSerialization.jsonObject(with: data),
              let obj = raw as? [String: Any],
              let type = obj["type"] as? String
        else { return }

        let event = parse(type: type, data: data)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.signaling(self, didReceive: event)
        }
    }

    private func parse(type: String, data: Data) -> SignalingEvent {
        switch type {
        case "date_matched":
            struct Payload: Decodable { let date: DateSession }
            guard let payload = try? decoder.decode(Payload.self, from: data) else {
                return .unknown(type: type)
            }
            return .dateMatched(payload.date)
        case "date_ended":
            struct Payload: Decodable { let dateId: String; let reason: String }
            guard let payload = try? decoder.decode(Payload.self, from: data) else {
                return .unknown(type: type)
            }
            return .dateEnded(dateId: payload.dateId, reason: payload.reason)
        case "match_made":
            struct Payload: Decodable { let match: MatchSummary }
            guard let payload = try? decoder.decode(Payload.self, from: data) else {
                return .unknown(type: type)
            }
            return .matchMade(payload.match)
        case "match_removed":
            struct Payload: Decodable { let matchId: String }
            guard let payload = try? decoder.decode(Payload.self, from: data) else {
                return .unknown(type: type)
            }
            return .matchRemoved(matchId: payload.matchId)
        case "message":
            struct Payload: Decodable { let matchId: String; let message: Message }
            guard let payload = try? decoder.decode(Payload.self, from: data) else {
                return .unknown(type: type)
            }
            return .message(matchId: payload.matchId, message: payload.message)
        case "connected":
            return .connected
        default:
            return .unknown(type: type)
        }
    }

    // MARK: Outbound

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard let task = self.task else {
                if self.isStarted {
                    self.retryGeneration += 1
                    self.openSocket()
                }
                return
            }
            let generation = self.socketGeneration
            task.send(.string(string)) { [weak self, weak task] error in
                guard error != nil, let self, let task else { return }
                self.queue.async {
                    self.handleDisconnect(task: task, generation: generation)
                }
            }
        }
    }

    private func heartbeat() { send(["type": "heartbeat"]) }

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 25, repeating: 25)
        timer.setEventHandler { [weak self] in self?.heartbeat() }
        heartbeatTimer = timer
        timer.resume()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    // MARK: Reconnect with exponential backoff

    private func handleDisconnect(task closedTask: URLSessionWebSocketTask,
                                  generation: Int) {
        guard task === closedTask, socketGeneration == generation else { return }
        task = nil
        stopHeartbeat()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.signalingDidDisconnect(self)
        }
        guard isStarted else { return }
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        retryGeneration += 1
        let retry = retryGeneration
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isStarted, self.task == nil,
                  self.retryGeneration == retry else { return }
            self.openSocket()
        }
    }
}

extension SignalingClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        queue.async { [weak self] in
            guard let self, self.task === webSocketTask else { return }
            self.reconnectAttempt = 0
            self.startHeartbeat()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.signalingDidConnect(self)
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.handleDisconnect(task: webSocketTask, generation: self.socketGeneration)
        }
    }
}
