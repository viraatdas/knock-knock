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

    let api = APIClient.shared
    let tokens = TokenStore.shared
    let signaling = SignalingClient()

    /// Drives the incoming-call screen / in-call modal.
    @Published var activeCall: ActiveCall?

    private var didConfigure = false

    func bootstrap() async {
        if !didConfigure {
            didConfigure = true
            await api.setAuthFailureHandler { [weak self] in
                Task { @MainActor in self?.logoutLocally() }
            }
            signaling.delegate = self
        }

        // Debug/screenshot hooks: jump straight to a screen in the simulator.
        let args = ProcessInfo.processInfo.arguments
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
        }
    }

    func didAuthenticate(user: User, isNewUser: Bool) {
        currentUser = user
        phase = (isNewUser || (user.displayName?.isEmpty ?? true)) ? .needsName : .home
        signaling.connect()
        Task { await registerDeviceIfPossible() }
    }

    func didCompleteName(user: User) {
        currentUser = user
        phase = .home
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
        activeCall = nil
        phase = .onboarding
    }

    private func registerDeviceIfPossible() async {
        // Without APNs entitlements (no paid account) we register a placeholder
        // token so the device row exists; real push wiring is gated on signing.
        let placeholder = "simulator-no-apns-token"
        _ = try? await api.registerDevice(pushToken: placeholder)
    }

    // MARK: - Calls

    func startCall(to user: User, video: Bool) {
        let call = ActiveCall(direction: .outgoing,
                              remoteName: user.displayName ?? user.phone,
                              remotePhone: user.phone,
                              remoteUserId: user.id,
                              isVideo: video,
                              status: .dialing)
        activeCall = call
        Task { await placeCall(to: user, video: video, local: call) }
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

    func endActiveCall() {
        guard let call = activeCall else { return }
        if let id = call.callId {
            Task { try? await api.leaveCall(id: id) }
        }
        activeCall = nil
    }

    func acceptIncoming() {
        guard let call = activeCall, let id = call.callId else {
            activeCall?.status = .connecting
            return
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

    func declineIncoming() {
        if let id = activeCall?.callId {
            Task { try? await api.declineCall(id: id) }
        }
        activeCall = nil
    }
}

// MARK: - Signaling delegate

extension AppState: SignalingClientDelegate {
    nonisolated func signaling(_ client: SignalingClient, didReceive event: SignalingEvent) {
        Task { @MainActor in
            switch event {
            case let .incomingCall(callId, fromUserId, fromName, type):
                let call = ActiveCall(direction: .incoming,
                                      remoteName: fromName ?? "Unknown",
                                      remotePhone: "",
                                      remoteUserId: fromUserId,
                                      isVideo: type == .oneToOne ? true : true,
                                      status: .ringing)
                call.callId = callId
                self.activeCall = call
                // Ring natively via CallKit.
                CallKitManager.shared.reportIncomingCall(
                    uuid: call.uuid, handle: fromName ?? "Slide",
                    displayName: fromName ?? "Slide", hasVideo: call.isVideo)
            case let .callEnded(callId):
                if self.activeCall?.callId == callId {
                    CallKitManager.shared.reportCallEnded(uuid: self.activeCall!.uuid)
                    self.activeCall = nil
                }
            case let .callDeclined(callId, _):
                if self.activeCall?.callId == callId { self.activeCall = nil }
            case let .callAccepted(callId, _):
                if self.activeCall?.callId == callId { self.activeCall?.status = .connecting }
            default:
                break
            }
        }
    }

    nonisolated func signalingDidConnect(_ client: SignalingClient) {}
    nonisolated func signalingDidDisconnect(_ client: SignalingClient) {}
}
