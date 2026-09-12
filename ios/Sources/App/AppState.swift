import SwiftUI
import Combine

/// Top-level app phases.
enum AppPhase: Equatable {
    case loading
    case onboarding
    case profileSetup
    case home
}

/// The date flow's state machine (SPEC §2.4). `RootView` presents a
/// `fullScreenCover` for any case other than `.none`. All server events
/// (WebSocket + lobby-heartbeat poll fallback) funnel through `AppState`;
/// views never talk to `SignalingClient` or the lobby/date endpoints directly.
enum DateFlow: Equatable {
    case none
    case waiting(since: Date)
    /// Doors closed while waiting in the lobby. Transient: LobbyView shows
    /// "Doors are closed for tonight." for a beat, then AppState moves this
    /// to `.none` itself (see `closeLobby`) so the message is actually seen
    /// instead of the fullScreenCover dismissing out from under it.
    case closed
    case inDate(DateSession)
    case deciding(DateSession, endReason: String)
    case result(DecisionResult, DateSession)
}

/// One chat message plus its optimistic send state.
struct ChatMessage: Identifiable, Hashable {
    enum Status: Hashable { case sent, pending, failed }
    var message: Message
    var status: Status = .sent
    var id: String { message.id }
}

/// Where a tapped push notification should take the user (SPEC §2.3 "Push
/// routing"). `RootView`/`MainTabView` observe `AppState.pendingRoute` and
/// clear it once handled.
enum NotificationRoute: Equatable {
    case chat(matchId: String)
    case matches
    case tonight
}

/// Owns auth/session state and the cross-cutting services. Injected as an
/// `@EnvironmentObject`. See the header comments on each Features/* file for
/// exactly which of these a view is expected to read/call.
@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .loading
    @Published var me: MeView?
    @Published var sessionWindow: SessionWindow?
    @Published var dateFlow: DateFlow = .none
    @Published var matches: [MatchSummary] = []
    @Published var datesToday: [DateHistoryEntry] = []
    @Published private(set) var messagesByMatch: [String: [ChatMessage]] = [:]
    /// matchIds whose full history has actually been fetched from
    /// `GET /matches/:id/messages`. `messagesByMatch[matchId]` alone can't
    /// tell us that — a live WS `message` event seeds it with just one
    /// message before the chat is ever opened (see `applyIncomingMessage`).
    private var historyLoadedMatchIds: Set<String> = []
    /// The server's real "is there more history before this?" per match,
    /// seeded from `MessagesPage.hasMore` on the initial `loadMessages`
    /// fetch. `ChatViewModel` reads this to seed its own `hasMoreOlder`
    /// instead of assuming `true`, which used to send every re-opened chat
    /// on a wasted (and visually disruptive) pagination round trip even
    /// when history was already exhausted.
    private(set) var hasMoreOlderByMatch: [String: Bool] = [:]
    /// True once the first `refreshMatches()` (success or failure) has
    /// completed, so MatchesView can show a spinner instead of the "no
    /// matches" empty state while the initial fetch is still in flight.
    @Published private(set) var matchesLoaded = false

    /// Routing hooks a tapped notification or a "Say hi" from MatchMadeView
    /// sets; the relevant view reads it, navigates, then clears it.
    @Published var pendingRoute: NotificationRoute?
    /// Set by ChatView while it's the visible chat, so AppDelegate can
    /// suppress a foreground banner for a message that's already on screen.
    @Published var activeChatMatchId: String?
    /// Set when a `match_removed` event lands for the currently open chat, so
    /// ChatView can show "This match ended." and pop.
    @Published var matchEndedToastMatchId: String?
    /// True when `bootstrap()` has an authenticated session but couldn't
    /// reach the server after retrying (offline, DNS, backend down) — never
    /// set for an actually-invalid session, which signs out instead.
    /// `LoadingView` reads this to offer a manual retry rather than the app
    /// silently sitting on a wordmark forever.
    @Published var bootstrapUnreachable = false

    let api = APIClient.shared
    let tokens = TokenStore.shared
    let signaling = SignalingClient()
    let sessionClock = SessionClock()
    let locationService = LocationService.shared

    private var lobbyHeartbeatTask: Task<Void, Never>?
    private var sessionPollTask: Task<Void, Never>?

    init() {
        signaling.delegate = self
        Task { [weak self] in
            guard let self else { return }
            await api.setAuthFailureHandler { [weak self] in
                Task { @MainActor in self?.logoutLocally() }
            }
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        if seedScreenshotSceneIfRequested() { return }

        guard tokens.isAuthenticated else {
            phase = .onboarding
            return
        }
        bootstrapUnreachable = false
        // A plain connectivity blip (no network, DNS, backend mid-deploy) on
        // cold launch must never bounce an already-signed-in user back to
        // onboarding — their tokens are still good. Retry with backoff first;
        // only an actual "your session is invalid" response signs out. Mock
        // mode has no real backend to retry against, so it falls straight
        // through to the mock fallback like before instead of waiting out
        // retries that can only fail.
        let attempts = Config.useMockData ? 1 : 3
        for attempt in 0..<attempts {
            do {
                let user = try await api.me()
                me = user
                phase = user.profileComplete ? .home : .profileSetup
                await postAuthSetup()
                return
            } catch APIError.unauthorized, APIError.notAuthenticated {
                logoutLocally()
                return
            } catch {
                if attempt < attempts - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (1 << attempt)))
                    continue
                }
                if Config.useMockData {
                    me = MockData.me
                    phase = .home
                    await postAuthSetup()
                } else {
                    // Stay signed in, on the loading screen, with a manual
                    // retry — never `.onboarding` for a network error alone.
                    bootstrapUnreachable = true
                }
            }
        }
    }

    /// "Try again" on the unreachable-loading screen.
    func retryBootstrap() {
        Task { await bootstrap() }
    }

    private func postAuthSetup() async {
        signaling.connect()
        startSessionPollLoop()
        await refreshMatches()
        // Re-asserts push registration for whichever account is signed in
        // now. `didRegisterForRemoteNotificationsWithDeviceToken` only fires
        // once per process on its own, so a second, already-onboarded user
        // logging in without a relaunch would otherwise never claim this
        // device's token — this call re-triggers that callback.
        NotificationService.registerForRemoteNotifications()
    }

    func didAuthenticate(user: MeView) {
        me = user
        phase = user.profileComplete ? .home : .profileSetup
        Task { await postAuthSetup() }
    }

    func appBecameActive() async {
        guard tokens.isAuthenticated else { return }
        signaling.reconnectNow()
        await refreshSession()
        await refreshMatches()
    }

    func appEnteredBackground() {
        // Keep the socket up mid-date or while waiting in the lobby (so a
        // partner-left/matched event still arrives); otherwise let it go idle.
        switch dateFlow {
        case .inDate, .waiting:
            break
        case .none, .closed, .deciding, .result:
            signaling.disconnect()
        }
    }

    // MARK: - Auth lifecycle

    func logout() {
        let flow = dateFlow
        Task {
            switch flow {
            case .inDate(let date):
                try? await self.api.leaveDate(id: date.id)
            case .waiting:
                try? await self.api.leaveLobby()
            default:
                break
            }
            // Drop this device's push binding first so a message/match/
            // doors-open push meant for the next account on this device
            // never gets delivered while this one is still signed in to it.
            if let token = self.tokens.devicePushToken {
                try? await self.api.unregisterPushToken(token)
            }
            await self.api.logout()
            await MainActor.run { self.logoutLocally() }
        }
    }

    func logoutLocally() {
        signaling.disconnect()
        stopLobbyHeartbeatLoop()
        stopSessionPollLoop()
        NotificationService.cancelDoorsOpenReminder()
        tokens.clear()
        me = nil
        sessionWindow = nil
        matches = []
        matchesLoaded = false
        datesToday = []
        messagesByMatch = [:]
        historyLoadedMatchIds = []
        hasMoreOlderByMatch = [:]
        dateFlow = .none
        phase = .onboarding
    }

    func deleteAccount() async {
        try? await api.deleteAccount()
        logoutLocally()
    }

    // MARK: - Session window

    func refreshSession() async {
        do {
            let window = try await api.fetchSessionWindow()
            sessionWindow = window
            sessionClock.update(from: window)
        } catch {
            if Config.useMockData, sessionWindow == nil {
                sessionWindow = MockData.sessionOpen
                sessionClock.update(from: MockData.sessionOpen)
            }
        }
        if let sessionWindow, !sessionWindow.isOpen, case .waiting = dateFlow {
            closeLobby()
        }
    }

    /// Doors closed while waiting in the lobby (either this session poll or a
    /// `session_closed` heartbeat error). Shows "Doors are closed for
    /// tonight." for a beat before actually dismissing, instead of flipping
    /// `dateFlow` straight to `.none` and yanking the cover away mid-sentence.
    private func closeLobby() {
        stopLobbyHeartbeatLoop()
        guard case .waiting = dateFlow else { return }
        dateFlow = .closed
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, case .closed = self.dateFlow else { return }
            self.dateFlow = .none
        }
    }

    /// Refreshes `/session` every 60s per SPEC §2.3 ("Loads /session on
    /// appear/foreground and every 60 s"). Runs for the lifetime of the app
    /// once signed in; harmless to call `bootstrap`'s postAuthSetup more than
    /// once since this guards against a duplicate task.
    private func startSessionPollLoop() {
        guard sessionPollTask == nil else { return }
        sessionPollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshSession()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func stopSessionPollLoop() {
        sessionPollTask?.cancel()
        sessionPollTask = nil
    }

    func refreshDatesToday() async {
        do {
            datesToday = try await api.datesToday()
        } catch {
            if Config.useMockData, datesToday.isEmpty { datesToday = MockData.datesToday }
        }
    }

    // MARK: - Lobby / date state machine

    func startLookingForDate() async {
        guard dateFlow == .none else { return }
        dateFlow = .waiting(since: Date())
        do {
            let resp = try await api.joinLobby()
            handleLobbyResponse(resp)
        } catch let error as APIError {
            await handleLobbyError(error)
        } catch {
            if Config.useMockData {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard case .waiting = dateFlow else { return }
                applyDateMatched(MockData.dateSession(with: MockData.profiles.randomElement() ?? MockData.profiles[0],
                                                      secondsLeft: 300))
                return
            }
        }
        if case .waiting = dateFlow { startLobbyHeartbeatLoop() }
    }

    func cancelLooking() async {
        switch dateFlow {
        case .waiting:
            stopLobbyHeartbeatLoop()
            dateFlow = .none
            try? await api.leaveLobby()
        case .closed:
            // "Back" on the transient "doors are closed" beat — no lobby
            // membership left to leave, just dismiss right away.
            dateFlow = .none
        default:
            break
        }
    }

    private func startLobbyHeartbeatLoop() {
        guard lobbyHeartbeatTask == nil else { return }
        lobbyHeartbeatTask = Task { [weak self] in
            while let self, case .waiting = self.dateFlow, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard case .waiting = self.dateFlow else { break }
                do {
                    let resp = try await self.api.lobbyHeartbeat()
                    self.handleLobbyResponse(resp)
                } catch let error as APIError {
                    await self.handleLobbyError(error)
                } catch {
                    break
                }
            }
            self?.lobbyHeartbeatTask = nil
        }
    }

    private func stopLobbyHeartbeatLoop() {
        lobbyHeartbeatTask?.cancel()
        lobbyHeartbeatTask = nil
    }

    private func handleLobbyResponse(_ resp: LobbyResponse) {
        guard resp.status == "matched", let date = resp.date else { return }
        applyDateMatched(date)
    }

    /// `date_matched` from the server, or a `matched` lobby/heartbeat
    /// response. Deduped by date id so a delayed WS delivery after the
    /// heartbeat poll already caught it is a no-op.
    private func applyDateMatched(_ date: DateSession) {
        if case .inDate(let existing) = dateFlow, existing.id == date.id { return }
        stopLobbyHeartbeatLoop()
        dateFlow = .inDate(date)
        SoundEffects.play(.found)
        Haptics.impact()
    }

    /// `date_ended` from the server. Ignored for any date id other than the
    /// one currently on screen.
    private func applyDateEnded(dateId: String, reason: String) {
        guard case .inDate(let date) = dateFlow, date.id == dateId else { return }
        dateFlow = .deciding(date, endReason: reason)
        SoundEffects.play(.ended)
    }

    /// 409/422 from `/lobby/join` or `/lobby/heartbeat`.
    private func handleLobbyError(_ error: APIError) async {
        switch error.code {
        case "session_closed":
            closeLobby()
        case "profile_incomplete", "location_required":
            stopLobbyHeartbeatLoop()
            dateFlow = .none
            phase = .profileSetup
        case "date_in_progress":
            // The error body carries the date, but APIError only surfaces
            // {code,message,retryAfter}; recover it with a follow-up GET
            // instead of threading the payload through. See openIssues.
            stopLobbyHeartbeatLoop()
            if let date = try? await api.currentDate() {
                applyDateMatched(date)
            } else {
                dateFlow = .none
            }
        default:
            break
        }
    }

    /// Returns nil on success (the flow has already moved to `.result`), or an
    /// inline message for `DecisionView` to show when the answer didn't
    /// register — a plain failure, or a 409 because the caller already
    /// answered differently and can't change it.
    @discardableResult
    func decide(explore: Bool) async -> String? {
        guard case .deciding(let date, _) = dateFlow else { return nil }
        do {
            let resp = try await api.decideDate(id: date.id, explore: explore)
            applyDecision(resp, date: date)
            return nil
        } catch let error as APIError where error.status == 409 {
            // A changed answer is rejected server-side; the original stands.
            return "Your first answer already went through. That one stands."
        } catch {
            if Config.useMockData {
                let mockResult: DecisionResult = explore
                    ? .matched(MockData.matches[0])
                    : .passed
                if case .matched(let match) = mockResult { upsertMatch(match) }
                dateFlow = .result(mockResult, date)
                return nil
            }
            return "Couldn't save that. Check your connection and try again."
        }
    }

    private func applyDecision(_ resp: DecisionResponse, date: DateSession) {
        let result: DecisionResult
        switch resp.status {
        case "matched":
            let match = resp.match ?? MatchSummary(id: date.id, partner: date.partner,
                                                   createdAt: Date(), lastMessage: nil, unreadCount: 0)
            upsertMatch(match)
            result = .matched(match)
            SoundEffects.play(.match)
            Haptics.success()
        case "passed":
            result = .passed
        default:
            result = .waiting
        }
        dateFlow = .result(result, date)
    }

    /// The client-side 5-minute timer (DateViewModel) hit zero. The
    /// server's own date-expirer will also end the date and publish
    /// `date_ended {reason: "timeout"}` momentarily, but SPEC §2.3 wants the
    /// knock-knock cue to move straight to DecisionView rather than waiting
    /// on that round trip. Deduped by date id like every other transition.
    func handleLocalDateTimeout(_ date: DateSession) {
        guard case .inDate(let current) = dateFlow, current.id == date.id else { return }
        dateFlow = .deciding(date, endReason: "timeout")
    }

    /// "Done for tonight" / dismissing the result screen.
    func dismissDateFlow() {
        stopLobbyHeartbeatLoop()
        dateFlow = .none
    }

    /// "Say hi" on MatchMadeView: close the date flow and hand a route to
    /// MatchesView so it can push straight into the chat.
    func openChat(matchId: String) {
        dismissDateFlow()
        pendingRoute = .chat(matchId: matchId)
    }

    func setActiveChatMatchId(_ matchId: String?) {
        activeChatMatchId = matchId
    }

    // MARK: - Matches

    func refreshMatches() async {
        defer { matchesLoaded = true }
        do {
            matches = try await api.matches()
        } catch {
            if Config.useMockData, matches.isEmpty { matches = MockData.matches }
        }
    }

    func markRead(matchId: String) async {
        if let idx = matches.firstIndex(where: { $0.id == matchId }) {
            matches[idx].unreadCount = 0
        }
        try? await api.markRead(matchId: matchId)
    }

    private func upsertMatch(_ match: MatchSummary) {
        if let idx = matches.firstIndex(where: { $0.id == match.id }) {
            matches[idx] = match
        } else {
            matches.insert(match, at: 0)
        }
    }

    func unmatch(matchId: String) async {
        matches.removeAll { $0.id == matchId }
        messagesByMatch[matchId] = nil
        historyLoadedMatchIds.remove(matchId)
        hasMoreOlderByMatch.removeValue(forKey: matchId)
        try? await api.unmatch(matchId: matchId)
    }

    func block(userId: String) async {
        matches.removeAll { $0.partner.id == userId }
        try? await api.block(userId: userId)
    }

    func report(userId: String, reason: ReportReason, details: String = "",
               dateId: String? = nil, matchId: String? = nil) async {
        try? await api.report(userId: userId, reason: reason, details: details,
                              dateId: dateId, matchId: matchId)
    }

    // MARK: - Chat

    func loadMessages(matchId: String) async {
        guard !historyLoadedMatchIds.contains(matchId) else { return }
        do {
            let page = try await api.messages(matchId: matchId)
            messagesByMatch[matchId] = page.messages.map { ChatMessage(message: $0) }
            historyLoadedMatchIds.insert(matchId)
            hasMoreOlderByMatch[matchId] = page.hasMore
        } catch {
            if Config.useMockData {
                messagesByMatch[matchId] = MockData.transcript.map { ChatMessage(message: $0) }
                historyLoadedMatchIds.insert(matchId)
                // The mock transcript is a fixed, non-paginated fixture —
                // there's nothing further back to page in.
                hasMoreOlderByMatch[matchId] = false
            }
        }
    }

    /// Pages backwards. Returns whether there's more to load: `true`/`false`
    /// from the server's own `hasMore`, or `nil` if the request itself failed
    /// (a network hiccup, not "reached the start of history") so the caller
    /// can leave its own "more to load" flag untouched and retry later
    /// instead of latching it permanently off.
    func loadOlderMessages(matchId: String) async -> Bool? {
        guard let first = messagesByMatch[matchId]?.first else { return false }
        do {
            let page = try await api.messages(matchId: matchId, before: first.id)
            let older = page.messages.map { ChatMessage(message: $0) }
            messagesByMatch[matchId] = older + (messagesByMatch[matchId] ?? [])
            hasMoreOlderByMatch[matchId] = page.hasMore
            return page.hasMore
        } catch {
            return nil
        }
    }

    /// Optimistic send: appends a `.pending` bubble immediately, swaps it for
    /// the server's copy on success, marks it `.failed` (retryable via
    /// `retryMessage`) otherwise.
    @discardableResult
    func sendMessage(matchId: String, body: String) async -> Message? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let tempId = "pending-\(UUID().uuidString)"
        let optimistic = Message(id: tempId, matchId: matchId, senderId: me?.id ?? "",
                                 body: trimmed, createdAt: Date())
        messagesByMatch[matchId, default: []].append(ChatMessage(message: optimistic, status: .pending))
        Haptics.tap()
        do {
            let sent = try await api.sendMessage(matchId: matchId, body: trimmed)
            replacePending(matchId: matchId, tempId: tempId, with: sent)
            updateLastMessage(matchId: matchId, from: sent)
            SoundEffects.play(.message)
            return sent
        } catch {
            markFailed(matchId: matchId, tempId: tempId)
            return nil
        }
    }

    func retryMessage(matchId: String, tempId: String) async {
        guard var list = messagesByMatch[matchId],
              let idx = list.firstIndex(where: { $0.id == tempId }) else { return }
        let body = list[idx].message.body
        list[idx].status = .pending
        messagesByMatch[matchId] = list
        do {
            let sent = try await api.sendMessage(matchId: matchId, body: body)
            replacePending(matchId: matchId, tempId: tempId, with: sent)
            updateLastMessage(matchId: matchId, from: sent)
        } catch {
            markFailed(matchId: matchId, tempId: tempId)
        }
    }

    private func replacePending(matchId: String, tempId: String, with message: Message) {
        guard var list = messagesByMatch[matchId] else { return }
        // The WS echo of our own send can land and get appended (see
        // applyIncomingMessage) before this HTTP response comes back. If the
        // real id is already in the list, this call is a no-op instead of a
        // second copy.
        guard !list.contains(where: { $0.message.id == message.id }) else { return }
        if let idx = list.firstIndex(where: { $0.id == tempId }) {
            list[idx] = ChatMessage(message: message, status: .sent)
        } else {
            list.append(ChatMessage(message: message, status: .sent))
        }
        messagesByMatch[matchId] = list
    }

    private func markFailed(matchId: String, tempId: String) {
        guard var list = messagesByMatch[matchId],
              let idx = list.firstIndex(where: { $0.id == tempId }) else { return }
        list[idx].status = .failed
        messagesByMatch[matchId] = list
    }

    private func updateLastMessage(matchId: String, from message: Message) {
        guard let idx = matches.firstIndex(where: { $0.id == matchId }) else { return }
        matches[idx].lastMessage = LastMessage(id: message.id, senderId: message.senderId,
                                               body: message.body, createdAt: message.createdAt)
        let match = matches.remove(at: idx)
        matches.insert(match, at: 0)
    }

    private func applyIncomingMessage(matchId: String, message: Message) {
        var list = messagesByMatch[matchId] ?? []
        guard !list.contains(where: { $0.message.id == message.id }) else { return }
        // The server echoes a just-sent message back to the sender's own
        // socket, and that echo frequently arrives before the POST /messages
        // response does. If this is our own message and there's still a
        // pending/failed bubble with the same body waiting for its real id,
        // resolve that bubble in place instead of appending a second one
        // (replacePending, running second, then finds the real id already
        // present and no-ops).
        if message.senderId == me?.id,
           let idx = list.lastIndex(where: { $0.status != .sent && $0.message.body == message.body }) {
            list[idx] = ChatMessage(message: message, status: .sent)
        } else {
            list.append(ChatMessage(message: message))
        }
        messagesByMatch[matchId] = list
        updateLastMessage(matchId: matchId, from: message)
        guard message.senderId != me?.id else { return }
        if let idx = matches.firstIndex(where: { $0.id == matchId }) {
            matches[idx].unreadCount += 1
        }
        if activeChatMatchId == matchId {
            SoundEffects.play(.message_received)
        }
    }

    // MARK: - Profile

    @discardableResult
    func updateProfile(displayName: String? = nil, birthdate: String? = nil,
                       gender: Gender? = nil, interestedIn: [Gender]? = nil,
                       ageMin: Int? = nil, ageMax: Int? = nil, bio: String? = nil) async -> Bool {
        do {
            let updated = try await api.updateMe(displayName: displayName, birthdate: birthdate,
                                                 gender: gender, interestedIn: interestedIn,
                                                 ageMin: ageMin, ageMax: ageMax, bio: bio)
            me = updated
            return true
        } catch {
            guard Config.useMockData else { return false }
            var m = me ?? MockData.meIncomplete
            if let displayName { m.displayName = displayName }
            if let birthdate { m.birthdate = birthdate }
            if let gender { m.gender = gender }
            if let interestedIn { m.interestedIn = interestedIn }
            if let ageMin { m.ageMin = ageMin }
            if let ageMax { m.ageMax = ageMax }
            if let bio { m.bio = bio }
            m.profileComplete = m.displayName != nil && m.birthdate != nil
                && m.gender != nil && !m.interestedIn.isEmpty
            me = m
            return true
        }
    }

    @discardableResult
    func uploadPhoto(_ jpegData: Data) async -> Bool {
        do {
            let resp = try await api.uploadPhoto(jpegData)
            me?.hasPhoto = true
            me?.photoUrl = resp.photoUrl
            me?.photoUpdatedAt = resp.photoUpdatedAt
            return true
        } catch {
            if Config.useMockData { me?.hasPhoto = true; return true }
            return false
        }
    }

    func deletePhoto() async {
        me?.hasPhoto = false
        me?.photoUrl = nil
        try? await api.deletePhoto()
    }

    @discardableResult
    func submitLocation() async -> Bool {
        let ok = await locationService.submitLocation()
        if ok { me?.hasLocation = true } else if Config.useMockData { me?.hasLocation = true }
        return ok || Config.useMockData
    }

    // MARK: - Notification routing

    /// Called by AppDelegate when a notification is tapped.
    func routeNotification(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }
        switch type {
        case "message":
            if let matchId = userInfo["matchId"] as? String {
                pendingRoute = .chat(matchId: matchId)
            }
        case "match_made":
            pendingRoute = .matches
        case "doors_open":
            pendingRoute = .tonight
        default:
            break
        }
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}

// MARK: - Signaling delegate

extension AppState: SignalingClientDelegate {
    nonisolated func signaling(_ client: SignalingClient, didReceive event: SignalingEvent) {
        Task { @MainActor in
            switch event {
            case .dateMatched(let date):
                self.applyDateMatched(date)
            case .dateEnded(let dateId, let reason):
                self.applyDateEnded(dateId: dateId, reason: reason)
            case .matchMade(let match):
                self.upsertMatch(match)
                Haptics.success()
            case .matchRemoved(let matchId):
                self.matches.removeAll { $0.id == matchId }
                self.messagesByMatch[matchId] = nil
                self.historyLoadedMatchIds.remove(matchId)
                self.hasMoreOlderByMatch.removeValue(forKey: matchId)
                if self.activeChatMatchId == matchId {
                    self.matchEndedToastMatchId = matchId
                }
            case .message(let matchId, let message):
                self.applyIncomingMessage(matchId: matchId, message: message)
            case .connected, .unknown:
                break
            }
        }
    }

    nonisolated func signalingDidConnect(_ client: SignalingClient) {}
    nonisolated func signalingDidDisconnect(_ client: SignalingClient) {}
}

// MARK: - Screenshot / debug scenes (SPEC §2.5, DEBUG launch arg `-scene <name>`)

private extension AppState {
    func seedScreenshotSceneIfRequested() -> Bool {
        guard let scene = ProcessInfo.processInfo.arguments.sceneArgument else { return false }
        switch scene {
        case "welcome", "phone", "code":
            // OnboardingFlow reads the same `-scene` argument to pick its step.
            phase = .onboarding
        case "setupName":
            me = MockData.meIncomplete
            phase = .profileSetup
        case "setupShowMe":
            var m = MockData.meIncomplete
            m.displayName = "Alex"
            m.birthdate = "1996-04-02"
            m.gender = .nonbinary
            me = m
            phase = .profileSetup
        case "tonightClosed":
            seedHome()
            sessionWindow = MockData.sessionClosed
            sessionClock.update(from: MockData.sessionClosed)
        case "tonightOpen":
            seedHome()
            sessionWindow = MockData.sessionOpen
            sessionClock.update(from: MockData.sessionOpen)
        case "lobby":
            seedHome()
            sessionWindow = MockData.sessionOpen
            sessionClock.update(from: MockData.sessionOpen)
            dateFlow = .waiting(since: Date())
        case "date":
            seedHome()
            dateFlow = .inDate(MockData.dateSession(secondsLeft: 192))
        case "decision":
            seedHome()
            dateFlow = .deciding(MockData.dateSession(secondsLeft: 0), endReason: "timeout")
        case "match":
            seedHome()
            let match = MockData.matches[0]
            dateFlow = .result(.matched(match), MockData.dateSession())
        case "matches":
            seedHome()
        case "chat":
            seedHome()
            messagesByMatch["m1"] = MockData.transcript.map { ChatMessage(message: $0) }
            historyLoadedMatchIds.insert("m1")
            hasMoreOlderByMatch["m1"] = false
            pendingRoute = .chat(matchId: "m1")
        case "profile":
            seedHome()
        default:
            return false
        }
        return true
    }

    func seedHome() {
        me = MockData.me
        phase = .home
        matches = MockData.matches
        matchesLoaded = true
        datesToday = MockData.datesToday
        if sessionWindow == nil {
            sessionWindow = MockData.sessionOpen
            sessionClock.update(from: MockData.sessionOpen)
        }
    }
}

extension Array where Element == String {
    /// Reads `-scene <name>` out of `ProcessInfo.arguments`. DEBUG only: a
    /// Release build ignores this launch argument entirely, so mock/screenshot
    /// scenes can never be triggered outside development builds.
    var sceneArgument: String? {
        #if DEBUG
        guard let idx = firstIndex(of: "-scene"), idx + 1 < count else { return nil }
        return self[idx + 1]
        #else
        return nil
        #endif
    }
}
