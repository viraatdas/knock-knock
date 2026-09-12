import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Async/await URLSession client implementing every endpoint in SPEC §1.
/// Performs a silent refresh on 401 via POST /auth/refresh.
actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let tokens: TokenStore
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Coalesces concurrent refresh attempts.
    private var refreshTask: Task<Void, Error>?

    /// Called when refresh ultimately fails so the app can log out.
    var onAuthFailure: (@Sendable () -> Void)?

    init(baseURL: URL = Config.apiBaseURL, tokens: TokenStore = .shared) {
        self.baseURL = baseURL
        self.tokens = tokens

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601WithFractional
        self.decoder = dec

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    func setAuthFailureHandler(_ handler: @escaping @Sendable () -> Void) {
        self.onAuthFailure = handler
    }

    // MARK: - Auth (no bearer)

    func requestOtp(phone: String) async throws -> RequestOtpResponse {
        let data = try await send(
            path: "/auth/request-otp", method: "POST",
            body: ["phone": phone], authenticated: false
        )
        return try decode(RequestOtpResponse.self, from: data)
    }

    func verifyOtp(phone: String, code: String) async throws -> VerifyOtpResponse {
        let data = try await send(
            path: "/auth/verify-otp", method: "POST",
            body: ["phone": phone, "code": code], authenticated: false
        )
        let resp = try decode(VerifyOtpResponse.self, from: data)
        tokens.save(access: resp.accessToken, refresh: resp.refreshToken)
        return resp
    }

    /// Exchange a verified Firebase ID token for Knock Knock session tokens.
    func firebaseAuth(idToken: String) async throws -> VerifyOtpResponse {
        let data = try await send(
            path: "/auth/firebase", method: "POST",
            body: ["idToken": idToken], authenticated: false
        )
        let resp = try decode(VerifyOtpResponse.self, from: data)
        tokens.save(access: resp.accessToken, refresh: resp.refreshToken)
        return resp
    }

    /// Fire-and-forget diagnostic beacon for client-side auth failures that
    /// never reach a human (App Review's device, a user who just closes the
    /// app on an error). Never throws to the caller and never blocks the auth
    /// flow it's called from; a delivery failure here is simply lost.
    /// `phoneCountry` is the dial code only ("+1"), never the full number.
    func reportDiagnostic(event: String, detail: String = "", phoneCountry: String) async {
        var body: [String: Any] = [
            "event": event,
            "phoneCountry": phoneCountry,
            "os": "iOS \(Self.osVersion)",
            "device": Self.deviceModelIdentifier,
            "app": Config.fullVersion
        ]
        if !detail.isEmpty { body["detail"] = detail }
        _ = try? await send(path: "/diagnostics", method: "POST",
                            jsonObject: body, authenticated: false, allowEmpty: true)
    }

    private static var osVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    /// Hardware identifier ("iPhone17,2") rather than the generic marketing
    /// name, so a report is actually useful for narrowing down a device-model
    /// specific failure like the one that caused the 2.1a rejection.
    private static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier += String(UnicodeScalar(UInt8(value)))
        }
    }

    func logout() async {
        guard let refresh = tokens.refreshToken else { tokens.clear(); return }
        _ = try? await send(
            path: "/auth/logout", method: "POST",
            body: ["refreshToken": refresh], authenticated: false, allowEmpty: true
        )
        tokens.clear()
    }

    // MARK: - Session window

    func fetchSessionWindow() async throws -> SessionWindow {
        let data = try await send(path: "/session", method: "GET")
        return try decode(SessionWindow.self, from: data)
    }

    // MARK: - Profile

    func me() async throws -> MeView {
        let data = try await send(path: "/me", method: "GET")
        return try decode(MeView.self, from: data)
    }

    func updateMe(displayName: String? = nil, birthdate: String? = nil,
                 gender: Gender? = nil, interestedIn: [Gender]? = nil,
                 ageMin: Int? = nil, ageMax: Int? = nil, bio: String? = nil) async throws -> MeView {
        var body: [String: Any] = [:]
        if let displayName { body["displayName"] = displayName }
        if let birthdate { body["birthdate"] = birthdate }
        if let gender { body["gender"] = gender.rawValue }
        if let interestedIn { body["interestedIn"] = interestedIn.map(\.rawValue) }
        if let ageMin { body["ageMin"] = ageMin }
        if let ageMax { body["ageMax"] = ageMax }
        if let bio { body["bio"] = bio }
        let data = try await send(path: "/me", method: "PATCH", jsonObject: body)
        return try decode(MeView.self, from: data)
    }

    struct PhotoUploadResponse: Codable { let photoUrl: String; let photoUpdatedAt: Date }

    /// Raw-body upload: `PUT /me/photo`, `Content-Type: image/jpeg`. Caller is
    /// responsible for resizing/compressing first (max 1024px, JPEG q0.8).
    func uploadPhoto(_ jpegData: Data) async throws -> PhotoUploadResponse {
        let data = try await sendRaw(path: "/me/photo", method: "PUT", body: jpegData,
                                     contentType: "image/jpeg")
        return try decode(PhotoUploadResponse.self, from: data)
    }

    func deletePhoto() async throws {
        _ = try await send(path: "/me/photo", method: "DELETE", allowEmpty: true)
    }

    /// Fetch someone's photo bytes with bearer auth (there is no public photo
    /// URL). 404 when they have none; the caller should fall back to initials.
    func photoData(for userId: String) async throws -> Data {
        try await perform(path: "/users/\(userId)/photo", method: "GET", bodyData: nil,
                          authenticated: true, allowEmpty: false)
    }

    func submitLocation(lat: Double, lng: Double) async throws {
        _ = try await send(path: "/me/location", method: "PUT",
                           jsonObject: ["lat": lat, "lng": lng], allowEmpty: true)
    }

    func deleteAccount() async throws {
        _ = try await send(path: "/me", method: "DELETE", allowEmpty: true)
    }

    // MARK: - Push

    /// Standard APNs alert token so the backend can push doors-open, match and
    /// message notifications. No VoIP push framework anymore — `kind` is always "apns".
    func registerPushToken(_ token: String) async throws {
        _ = try await send(path: "/push/register", method: "POST", jsonObject: [
            "pushToken": token,
            "kind": "apns",
            "platform": "ios",
            "appVersion": Config.appVersion
        ])
    }

    func unregisterPushToken(_ token: String) async throws {
        _ = try await send(path: "/push/register", method: "DELETE", body: [
            "pushToken": token
        ], allowEmpty: true)
    }

    func registerDevice(pushToken: String, platform: String = "ios") async throws {
        _ = try await send(path: "/devices", method: "POST", body: [
            "pushToken": pushToken,
            "platform": platform,
            "appVersion": Config.appVersion
        ], allowEmpty: true)
    }

    // MARK: - Lobby + matching

    func joinLobby() async throws -> LobbyResponse {
        let data = try await send(path: "/lobby/join", method: "POST", allowEmpty: false)
        return try decode(LobbyResponse.self, from: data)
    }

    func lobbyHeartbeat() async throws -> LobbyResponse {
        let data = try await send(path: "/lobby/heartbeat", method: "POST", allowEmpty: false)
        return try decode(LobbyResponse.self, from: data)
    }

    func leaveLobby() async throws {
        _ = try await send(path: "/lobby", method: "DELETE", allowEmpty: true)
    }

    struct CurrentDateResponse: Codable { var date: DateSession? }

    func currentDate() async throws -> DateSession? {
        let data = try await send(path: "/dates/current", method: "GET")
        return try decode(CurrentDateResponse.self, from: data).date
    }

    func datesToday() async throws -> [DateHistoryEntry] {
        let data = try await send(path: "/dates/today", method: "GET")
        return try decode([DateHistoryEntry].self, from: data)
    }

    func leaveDate(id: String) async throws {
        _ = try await send(path: "/dates/\(id)/leave", method: "POST", allowEmpty: true)
    }

    func decideDate(id: String, explore: Bool) async throws -> DecisionResponse {
        let data = try await send(path: "/dates/\(id)/decision", method: "POST",
                                  jsonObject: ["explore": explore])
        return try decode(DecisionResponse.self, from: data)
    }

    // MARK: - Matches + chat

    func matches() async throws -> [MatchSummary] {
        let data = try await send(path: "/matches", method: "GET")
        return try decode([MatchSummary].self, from: data)
    }

    func messages(matchId: String, before: String? = nil, limit: Int = 50) async throws -> MessagesPage {
        var path = "/matches/\(matchId)/messages?limit=\(limit)"
        if let before { path += "&before=\(before)" }
        let data = try await send(path: path, method: "GET")
        return try decode(MessagesPage.self, from: data)
    }

    func sendMessage(matchId: String, body: String) async throws -> Message {
        let data = try await send(path: "/matches/\(matchId)/messages", method: "POST",
                                  jsonObject: ["body": body])
        return try decode(Message.self, from: data)
    }

    func markRead(matchId: String) async throws {
        _ = try await send(path: "/matches/\(matchId)/read", method: "POST", allowEmpty: true)
    }

    func unmatch(matchId: String) async throws {
        _ = try await send(path: "/matches/\(matchId)", method: "DELETE", allowEmpty: true)
    }

    // MARK: - Safety

    func block(userId: String) async throws {
        _ = try await send(path: "/users/\(userId)/block", method: "POST", allowEmpty: true)
    }

    func unblock(userId: String) async throws {
        _ = try await send(path: "/users/\(userId)/block", method: "DELETE", allowEmpty: true)
    }

    func report(userId: String, reason: ReportReason, details: String = "",
               dateId: String? = nil, matchId: String? = nil) async throws {
        var body: [String: Any] = ["reason": reason.rawValue, "details": details]
        if let dateId { body["dateId"] = dateId }
        if let matchId { body["matchId"] = matchId }
        _ = try await send(path: "/users/\(userId)/report", method: "POST",
                           jsonObject: body, allowEmpty: true)
    }

    // MARK: - Token refresh

    func refreshTokens() async throws {
        guard let refresh = tokens.refreshToken else {
            throw APIError.notAuthenticated
        }
        let req = try makeRequest(path: "/auth/refresh", method: "POST",
                                  body: ["refreshToken": refresh], authenticated: false)
        let (data, response) = try await transport(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(status: -1) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.unauthorized
        }
        let resp = try decode(RefreshResponse.self, from: data)
        tokens.updateAccess(resp.accessToken, refresh: resp.refreshToken)
    }

    // MARK: - Request plumbing

    private func send(path: String, method: String,
                      body: [String: String]? = nil,
                      authenticated: Bool = true,
                      allowEmpty: Bool = false) async throws -> Data {
        let bodyData = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await perform(path: path, method: method, bodyData: bodyData,
                                 authenticated: authenticated, allowEmpty: allowEmpty)
    }

    private func send(path: String, method: String,
                      jsonObject: [String: Any],
                      authenticated: Bool = true,
                      allowEmpty: Bool = false) async throws -> Data {
        let bodyData = try JSONSerialization.data(withJSONObject: jsonObject)
        return try await perform(path: path, method: method, bodyData: bodyData,
                                 authenticated: authenticated, allowEmpty: allowEmpty)
    }

    private func sendRaw(path: String, method: String, body: Data,
                         contentType: String) async throws -> Data {
        return try await perform(path: path, method: method, bodyData: body,
                                 authenticated: true, allowEmpty: false,
                                 contentType: contentType)
    }

    private func perform(path: String, method: String, bodyData: Data?,
                         authenticated: Bool, allowEmpty: Bool,
                         contentType: String = "application/json",
                         isRetry: Bool = false) async throws -> Data {
        var req = try makeRawRequest(path: path, method: method, bodyData: bodyData,
                                     authenticated: authenticated, contentType: contentType)
        let (data, response) = try await transport(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(status: -1) }

        if http.statusCode == 401 && authenticated && !isRetry {
            // Silent refresh, then retry once.
            try await performRefresh()
            req = try makeRawRequest(path: path, method: method, bodyData: bodyData,
                                     authenticated: authenticated, contentType: contentType)
            return try await perform(path: path, method: method, bodyData: bodyData,
                                     authenticated: authenticated, allowEmpty: allowEmpty,
                                     contentType: contentType, isRetry: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            if let env = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                throw APIError.server(code: env.error.code,
                                      message: env.error.message,
                                      retryAfter: env.error.retryAfter,
                                      status: http.statusCode)
            }
            throw APIError.http(status: http.statusCode)
        }

        return data
    }

    /// Coalesced refresh so concurrent 401s only trigger one network call.
    /// Stays on the actor throughout so `tokens`/`onAuthFailure` access is safe.
    private func performRefresh() async throws {
        if let task = refreshTask {
            try await task.value
            return
        }
        // The work runs as an actor-isolated async method; the Task only exists
        // so concurrent callers can await the same in-flight refresh.
        let task = Task { try await self.runRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func runRefresh() async throws {
        do {
            try await refreshTokens()
        } catch {
            tokens.clear()
            onAuthFailure?()
            throw error
        }
    }

    private func transport(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }
    }

    private func makeRequest(path: String, method: String,
                             body: [String: String]?, authenticated: Bool) throws -> URLRequest {
        let bodyData = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try makeRawRequest(path: path, method: method, bodyData: bodyData,
                                  authenticated: authenticated, contentType: "application/json")
    }

    private func makeRawRequest(path: String, method: String, bodyData: Data?,
                                authenticated: Bool, contentType: String) throws -> URLRequest {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let bodyData {
            req.httpBody = bodyData
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token = tokens.accessToken else { throw APIError.notAuthenticated }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// ISO8601 with optional fractional seconds (backend uses RFC3339).
    static var iso8601WithFractional: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFrac.date(from: string) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: string) { return d }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Bad date: \(string)")
        }
    }
}
