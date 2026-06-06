import SwiftUI
import Combine

/// Top-level app phases.
enum AppPhase: Equatable {
    case loading
    case onboarding
    case needsName        // authenticated but new user without a name
    case home
}

/// Owns auth/session state and the cross-cutting services. Injected as an
/// `@EnvironmentObject`.
@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .loading
    @Published var currentUser: User?
    @Published private(set) var contacts: [Contact] = []

    let api = APIClient.shared
    let tokens = TokenStore.shared
    let signaling = SignalingClient()

    /// Drives the incoming-call screen / in-call modal.
    @Published var activeCall: ActiveCall?

    /// Drives the incoming-knock banner overlay (lightweight, not CallKit).
    @Published var incomingKnock: IncomingKnock?

    private var didConfigure = false

    // MARK: Knock send-side state
    /// Monotonic sequence for the current outbound knock session.
    private var outgoingKnockSeq = 0
    /// Timestamp of the previous outbound tap, to compute `dt`.
    private var lastOutgoingKnockAt: Date?
    /// The user-id we're currently knocking, so a new target resets the session.
    private var outgoingKnockTarget: String?

    // MARK: Knock receive-side state
    /// Auto-clears the incoming-knock banner ~2.5s after the last received tap.
    private var incomingKnockClearTask: Task<Void, Never>?

    func bootstrap() async {
        if !didConfigure {
            didConfigure = true
            await api.setAuthFailureHandler { [weak self] in
                Task { @MainActor in self?.logoutLocally() }
            }
            signaling.delegate = self
            CallKitManager.shared.delegate = self
            // VoIP push → surface + (on answer) join the call. CallKit was
            // already told about the call inside PushService; here we mirror it
            // into app state using the same UUID so the answer path matches.
            PushService.shared.onIncomingCall = { [weak self] callId, fromUserId, fromName, callType in
                Task { @MainActor in
                    self?.receivePushedCall(callId: callId, fromUserId: fromUserId,
                                            fromName: fromName, type: callType)
                }
            }
        }

        // Debug/screenshot hooks: jump straight to a screen in the simulator.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-group") {
            // Group-call grid for screenshots.
            currentUser = MockData.me
            phase = .home
            let names = ["Amelia Stone", "Daniel Wu", "Grace Lin", "Marcus Reed", "Priya Nair"]
            let demo = ActiveCall(direction: .outgoing,
                                  remoteName: names[0],
                                  remotePhone: "",
                                  remoteUserId: "u_group",
                                  isVideo: true,
                                  status: .connecting,
                                  isGroup: true,
                                  memberNames: names)
            demo.session = MockData.callSession(for: MockData.userForContact(MockData.contacts[0]),
                                                video: true)
            activeCall = demo
            return
        }
        if args.contains("-home") || args.contains("-incall") {
            currentUser = MockData.me
            phase = .home
            if args.contains("-incall") {
                let demo = ActiveCall(direction: .outgoing,
                                      remoteName: "Amelia Stone",
                                      remotePhone: "+14155550111",
                                      remoteUserId: "u_amelia",
                                      isVideo: !args.contains("-audio"),
                                      status: .connecting)
                demo.session = MockData.callSession(for: MockData.userForContact(MockData.contacts[0]),
                                                    video: !args.contains("-audio"))
                activeCall = demo
            }
            return
        }
        if args.contains("-incoming") {
            currentUser = MockData.me
            phase = .home
            let demo = ActiveCall(direction: .incoming,
                                  remoteName: "Daniel Wu",
                                  remotePhone: "+14155550114",
                                  remoteUserId: "u_daniel",
                                  isVideo: true,
                                  status: .ringing)
            demo.callId = "demo_incoming"
            activeCall = demo
            return
        }

        guard tokens.isAuthenticated else {
            phase = .onboarding
            return
        }

        // Try to load the profile; if it fails on auth, fall back to onboarding.
        do {
            let user = try await api.me()
            currentUser = user
            phase = (user.displayName?.isEmpty ?? true) ? .needsName : .home
            signaling.connect()
            Task { await registerDeviceIfPossible() }
            Task { await refreshContactCache() }
        } catch APIError.unauthorized, APIError.notAuthenticated {
            logoutLocally()
        } catch {
            // Network down but we have tokens — proceed to home optimistically.
            if Config.useMockData {
                currentUser = MockData.me
                phase = .home
            } else {
                phase = .home
            }
            signaling.connect()
            Task { await refreshContactCache() }
        }
    }

    func didAuthenticate(user: User, isNewUser: Bool) {
        currentUser = user
        phase = (isNewUser || (user.displayName?.isEmpty ?? true)) ? .needsName : .home
        signaling.connect()
        Task { await registerDeviceIfPossible() }
        Task { await refreshContactCache() }
    }

    func didCompleteName(user: User) {
        currentUser = user
        phase = .home
        Task { await refreshContactCache() }
    }

    func logout() {
        Task {
            await api.logout()
            await MainActor.run { logoutLocally() }
        }
    }

    func logoutLocally() {
        signaling.disconnect()
        tokens.clear()
        currentUser = nil
        contacts = []
        activeCall = nil
        phase = .onboarding
    }

    func refreshContactCache() async {
        guard tokens.isAuthenticated else { return }
        do {
            let list = try await api.contacts()
            contacts = list
            refreshActiveCallDisplayName()
        } catch {
            // Contacts are a display-name enhancement. Never block calls on it.
        }
    }

    func replaceContactCache(_ list: [Contact]) {
        contacts = list
        refreshActiveCallDisplayName()
    }

    func appBecameActive() async {
        guard tokens.isAuthenticated else { return }
        signaling.connect()
        await refreshContactCache()
        await reconcileActiveRingingCall()
    }

    private func registerDeviceIfPossible() async {
        // Prefer the real PushKit VoIP token if it has already arrived. If the
        // token shows up later, PushService registers it on `didUpdate`.
        if let voip = PushService.shared.voipToken {
            _ = try? await api.registerPushToken(voip)
            return
        }
        // No VoIP token yet (e.g. simulator, or token not delivered) — register
        // a placeholder so the device row exists; the real token replaces it
        // once PushKit delivers it.
        let placeholder = "simulator-no-apns-token"
        _ = try? await api.registerDevice(pushToken: placeholder)
    }

    // MARK: - Calls

    func startCall(to user: User, video: Bool) {
        Haptics.impact()   // committing to a call
        let call = ActiveCall(direction: .outgoing,
                              remoteName: user.displayName ?? user.phone,
                              remotePhone: user.phone,
                              remoteUserId: user.id,
                              isVideo: video,
                              status: .dialing)
        activeCall = call
        Task { await placeCall(to: user, video: video, local: call) }
    }

    /// Start a group call with several people selected up front. The backend
    /// rings everyone and the SFU fans out each participant's media.
    func startGroupCall(to users: [User], video: Bool) {
        guard !users.isEmpty else { return }
        guard users.count > 1 else { startCall(to: users[0], video: video); return }
        Haptics.impact()   // committing to a group call
        let names = users.map { $0.displayName ?? $0.phone }
        let call = ActiveCall(direction: .outgoing,
                              remoteName: names.first ?? "Group",
                              remotePhone: "",
                              remoteUserId: users.first?.id,
                              isVideo: video,
                              status: .dialing,
                              isGroup: true,
                              memberNames: names)
        activeCall = call
        Task { await placeGroupCall(to: users, video: video, local: call) }
    }

    private func placeGroupCall(to users: [User], video: Bool, local: ActiveCall) async {
        do {
            let session = try await api.createCall(type: .group,
                                                   participantUserIds: users.map { $0.id })
            await MainActor.run {
                local.session = session
                local.callId = session.call.id
                local.status = .connecting
            }
        } catch {
            await MainActor.run {
                if Config.useMockData {
                    local.session = MockData.callSession(for: users[0], video: video)
                    local.status = .connecting
                } else {
                    local.status = .failed
                }
            }
        }
    }

    private func placeCall(to user: User, video: Bool, local: ActiveCall) async {
        do {
            let session = try await api.createCall(type: .oneToOne,
                                                   participantUserIds: [user.id])
            await MainActor.run {
                local.session = session
                local.callId = session.call.id
                local.status = .connecting
            }
        } catch {
            await MainActor.run {
                if Config.useMockData {
                    // Mock: synthesize a session so the in-call UI works offline.
                    local.session = MockData.callSession(for: user, video: video)
                    local.status = .connecting
                } else {
                    local.status = .failed
                }
            }
        }
    }

    /// Surface a call that arrived via a VoIP push. CallKit has already been
    /// told about this call (in PushService) using `PushService.uuid(for:)`, so
    /// we build the ActiveCall with the SAME uuid. That makes the CallKit answer
    /// callback (`callKitDidAnswer`) match this call and run `acceptIncoming`,
    /// which joins via the normal accept path — identical to an in-app
    /// `incoming_call`. If the WebSocket later delivers the same `incoming_call`,
    /// it's deduped by callId so we don't double-ring.
    func receivePushedCall(callId: String, fromUserId: String?,
                           fromName: String?, type: CallType) {
        // Already showing this call (e.g. WS arrived first) — nothing to do.
        if let existing = activeCall, existing.callId == callId { return }

        let uuid = PushService.uuid(for: callId)
        let name = displayNameForIncomingCall(fromUserId: fromUserId, fromName: fromName)
        let call = ActiveCall(direction: .incoming,
                              remoteName: name,
                              remotePhone: "",
                              remoteUserId: fromUserId,
                              isVideo: type == .oneToOne ? true : true,
                              status: .ringing,
                              isGroup: type == .group,
                              uuid: uuid)
        call.callId = callId
        activeCall = call
        CallKitManager.shared.updateCall(uuid: uuid, handle: name,
                                         displayName: name, hasVideo: call.isVideo)
        Task { await reconcileActiveRingingCall() }
        // CallKit ring was already started by PushService; no reportIncomingCall
        // here (that would double-report the same UUID).
    }

    func endActiveCall(fromCallKit: Bool = false) {
        guard let call = activeCall else { return }
        Haptics.strong()   // decisive: hang up
        if !fromCallKit {
            CallKitManager.shared.endCall(uuid: call.uuid)
        }
        if let id = call.callId {
            Task { try? await api.leaveCall(id: id) }
        }
        activeCall = nil
    }

    func acceptIncoming(fromCallKit: Bool = false) {
        guard let call = activeCall, let id = call.callId else {
            activeCall?.status = .connecting
            return
        }
        Haptics.strong()   // decisive: answer
        if !fromCallKit {
            CallKitManager.shared.answerCall(uuid: call.uuid)
        }
        call.status = .connecting
        Task {
            do {
                let session = try await api.acceptCall(id: id)
                await MainActor.run { call.session = session }
            } catch {
                await MainActor.run {
                    if Config.useMockData {
                        call.session = MockData.incomingSession(callId: id, video: call.isVideo)
                    } else {
                        call.status = .failed
                    }
                }
            }
        }
    }

    func declineIncoming(fromCallKit: Bool = false) {
        guard let call = activeCall else { return }
        Haptics.gentle()   // dismiss
        if !fromCallKit {
            CallKitManager.shared.endCall(uuid: call.uuid)
        }
        if let id = call.callId {
            Task { try? await api.declineCall(id: id) }
        }
        activeCall = nil
    }

    // MARK: - Knocks

    /// This user's outbound display name on a knock: prefer the display name,
    /// fall back to phone, then a generic label.
    private var myKnockName: String {
        if let name = currentUser?.displayName, !name.isEmpty { return name }
        if let phone = currentUser?.phone, !phone.isEmpty { return phone }
        return "Someone"
    }

    /// Send a single knock tap to `userId`. Tracks `seq` + the last-tap time so
    /// `dt` (ms since the previous tap) is filled in. Plays the caller's own
    /// sound + haptic so they feel the rhythm they're tapping. Call once per tap.
    func sendKnockTap(to userId: String) {
        // Reset the session whenever the target changes.
        if outgoingKnockTarget != userId {
            outgoingKnockTarget = userId
            outgoingKnockSeq = 0
            lastOutgoingKnockAt = nil
        }
        let now = Date()
        let dt: Int
        if let last = lastOutgoingKnockAt {
            dt = max(0, Int(now.timeIntervalSince(last) * 1000))
        } else {
            dt = 0
        }
        lastOutgoingKnockAt = now
        let seq = outgoingKnockSeq
        outgoingKnockSeq += 1

        // Local feedback so the caller feels their own taps.
        KnockHaptics.shared.knock()

        signaling.sendKnock(to: userId, fromName: myKnockName, seq: seq, dt: dt)
    }

    /// Reset the outbound knock session (e.g. when the knock pad is dismissed).
    func resetKnockSession() {
        outgoingKnockTarget = nil
        outgoingKnockSeq = 0
        lastOutgoingKnockAt = nil
    }

    /// Knock back at whoever is currently knocking us, then clear the banner.
    func knockBack() {
        guard let knock = incomingKnock, let userId = knock.fromUserId else { return }
        sendKnockTap(to: userId)
    }

    /// Escalate the incoming knock into a real call.
    func callFromKnock(video: Bool = false) {
        guard let knock = incomingKnock,
              let userId = knock.fromUserId,
              !userId.isEmpty else { return }
        let user = User(id: userId,
                        phone: "",
                        displayName: knock.displayName,
                        avatarUrl: nil,
                        createdAt: nil, lastSeenAt: nil)
        clearIncomingKnock()
        startCall(to: user, video: video)
    }

    /// Handle one received knock tap: play sound + haptic, surface/refresh the
    /// banner, bump the pulse counter, and (re)arm the auto-clear timer.
    func receiveKnock(fromUserId: String?, fromName: String?, seq: Int?, dt: Int?) {
        KnockHaptics.shared.knock()

        if let existing = incomingKnock, existing.fromUserId == fromUserId {
            existing.pulse += 1
            existing.lastName = fromName ?? existing.lastName
        } else {
            let knock = IncomingKnock(fromUserId: fromUserId, fromName: fromName)
            incomingKnock = knock
        }
        armIncomingKnockClear()
    }

    private func armIncomingKnockClear() {
        incomingKnockClearTask?.cancel()
        incomingKnockClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.incomingKnock = nil
        }
    }

    func clearIncomingKnock() {
        incomingKnockClearTask?.cancel()
        incomingKnockClearTask = nil
        incomingKnock = nil
    }
}

/// Transient state backing the incoming-knock banner. `pulse` increments on
/// every received tap so the banner can re-animate per tap.
@MainActor
final class IncomingKnock: ObservableObject, Identifiable {
    let id = UUID()
    let fromUserId: String?
    private let initialName: String?
    /// Most recently seen name (knock messages may carry it each tap).
    @Published var lastName: String?
    /// Increments per received tap; the banner observes this to re-pulse.
    @Published var pulse: Int = 0

    init(fromUserId: String?, fromName: String?) {
        self.fromUserId = fromUserId
        self.initialName = fromName
        self.lastName = fromName
    }

    var displayName: String {
        if let name = lastName, !name.isEmpty { return name }
        if let name = initialName, !name.isEmpty { return name }
        return "Someone"
    }
}

// MARK: - Signaling delegate

extension AppState: SignalingClientDelegate {
    nonisolated func signaling(_ client: SignalingClient, didReceive event: SignalingEvent) {
        Task { @MainActor in
            switch event {
            case let .incomingCall(callId, fromUserId, fromName, type):
                // If a VoIP push already surfaced this call (cold/background
                // launch), it's already ringing via CallKit — don't double-ring.
                if let existing = self.activeCall, existing.callId == callId { break }
                // Use a deterministic UUID derived from the callId so this call
                // matches any VoIP push for the same call (same CallKit UUID).
                let uuid = PushService.uuid(for: callId)
                let name = self.displayNameForIncomingCall(fromUserId: fromUserId, fromName: fromName)
                let call = ActiveCall(direction: .incoming,
                                      remoteName: name,
                                      remotePhone: "",
                                      remoteUserId: fromUserId,
                                      isVideo: type == .oneToOne ? true : true,
                                      status: .ringing,
                                      uuid: uuid)
                call.callId = callId
                self.activeCall = call
                Haptics.warning()   // attention: incoming call
                // Ring natively via CallKit.
                CallKitManager.shared.reportIncomingCall(
                    uuid: call.uuid, handle: name,
                    displayName: name, hasVideo: call.isVideo)
            case let .callEnded(callId):
                if self.activeCall?.callId == callId {
                    CallKitManager.shared.reportCallEnded(uuid: self.activeCall!.uuid)
                    self.activeCall = nil
                }
            case let .callDeclined(callId, _):
                if self.activeCall?.callId == callId {
                    CallKitManager.shared.reportCallEnded(uuid: self.activeCall!.uuid, reason: .remoteEnded)
                    self.activeCall = nil
                }
            case let .callAccepted(callId, _):
                if self.activeCall?.callId == callId { self.activeCall?.status = .connecting }
            case let .knock(fromUserId, fromName, seq, dt):
                self.receiveKnock(fromUserId: fromUserId, fromName: fromName, seq: seq, dt: dt)
            default:
                break
            }
        }
    }

    nonisolated func signalingDidConnect(_ client: SignalingClient) {}
    nonisolated func signalingDidDisconnect(_ client: SignalingClient) {}
}

private extension AppState {
    func displayNameForIncomingCall(fromUserId: String?, fromName: String?) -> String {
        if let fromUserId,
           let contact = contacts.first(where: { $0.contactUserId == fromUserId }) {
            let name = contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if let name = sanitizedRemoteName(fromName) {
            return name
        }
        return "Slide"
    }

    func sanitizedRemoteName(_ fromName: String?) -> String? {
        if let name = fromName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           name.localizedCaseInsensitiveCompare("unknown") != .orderedSame,
           name.localizedCaseInsensitiveCompare("someone") != .orderedSame {
            return name
        }
        return nil
    }

    func reconcileActiveRingingCall() async {
        guard let call = activeCall,
              call.status == .ringing,
              let callId = call.callId else { return }
        do {
            let response = try await api.calls()
            guard let serverCall = response.calls.first(where: { $0.id == callId }) else {
                clearRingingCallIfStillActive(call)
                return
            }
            switch serverCall.status {
            case .ringing:
                return
            case .active:
                if serverCall.type == .oneToOne {
                    clearRingingCallIfStillActive(call)
                }
            case .ended, .missed, .declined:
                clearRingingCallIfStillActive(call)
            }
        } catch {
            // Avoid hiding a real incoming call just because the network blipped.
        }
    }

    func clearRingingCallIfStillActive(_ call: ActiveCall) {
        guard activeCall?.id == call.id else { return }
        CallKitManager.shared.reportCallEnded(uuid: call.uuid, reason: .remoteEnded)
        activeCall = nil
    }

    func refreshActiveCallDisplayName() {
        guard let call = activeCall,
              call.direction == .incoming,
              let remoteUserId = call.remoteUserId else { return }
        let name = displayNameForIncomingCall(fromUserId: remoteUserId, fromName: call.remoteName)
        guard name != call.remoteName else { return }
        call.remoteName = name
        if !call.isGroup {
            call.memberNames = [name]
        }
        CallKitManager.shared.updateCall(uuid: call.uuid, handle: name,
                                         displayName: name, hasVideo: call.isVideo)
    }
}

// MARK: - CallKit delegate

extension AppState: CallKitManagerDelegate {
    nonisolated func callKitDidAnswer(callId: UUID) {
        Task { @MainActor in
            guard self.activeCall?.uuid == callId else { return }
            self.acceptIncoming(fromCallKit: true)
        }
    }

    nonisolated func callKitDidEnd(callId: UUID) {
        Task { @MainActor in
            guard let call = self.activeCall, call.uuid == callId else { return }
            if call.direction == .incoming && call.status == .ringing {
                self.declineIncoming(fromCallKit: true)
            } else {
                self.endActiveCall(fromCallKit: true)
            }
        }
    }

    nonisolated func callKitDidSetMuted(callId: UUID, muted: Bool) {
        // The active in-call view owns the media service instance. CallKit mute
        // state is accepted here so the system UI stays responsive.
    }
}
