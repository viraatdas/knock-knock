import Foundation
import PushKit
import CallKit

/// Bridges Apple PushKit (VoIP pushes) to CallKit so an incoming call/knock
/// rings natively even when the app is backgrounded, locked, or killed.
///
/// Flow:
///   APNs VoIP push (topic `app.exla.slide.voip`)
///     → `pushRegistry(_:didReceiveIncomingPushWith:)`
///     → CallKitManager.reportIncomingCall (REQUIRED on every VoIP push, or
///       iOS terminates the app for not reporting a call)
///     → on CallKit answer, AppState joins the call via the normal accept path.
///
/// iOS launches the app into the background to deliver a VoIP push, so this
/// works from a cold start.
final class PushService: NSObject, @unchecked Sendable {
    static let shared = PushService()

    private let registry = PKPushRegistry(queue: .main)

    /// The most recent VoIP token (hex), retained so we can (re)register once
    /// the user is authenticated even if the token arrived before sign-in.
    private(set) var voipToken: String?

    /// Invoked when a VoIP push arrives. AppState wires this up to surface the
    /// call and join it on answer. Parameters mirror the push payload.
    var onIncomingCall: ((_ callId: String, _ fromUserId: String?,
                          _ fromName: String?, _ callType: CallType,
                          _ videoEnabled: Bool, _ ringStyle: String) -> Void)?

    private override init() { super.init() }

    /// Register for VoIP pushes. Safe to call once at launch.
    func start() {
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }
}

// MARK: - PKPushRegistryDelegate

extension PushService: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        guard type == .voIP else { return }
        let hex = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        voipToken = hex
        // Register with the backend if we're already signed in; otherwise the
        // post-sign-in hook in AppState will pick up `voipToken`.
        Task { _ = try? await APIClient.shared.registerPushToken(hex) }
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        voipToken = nil
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }

        let dict = payload.dictionaryPayload
        let callId = (dict["callId"] as? String) ?? (dict["id"] as? String) ?? ""
        let eventType = (dict["type"] as? String) ?? "incoming_call"
        let isTapOnly = eventType == "knock" || ((dict["knock"] as? Bool) == true && callId.isEmpty)
        guard eventType == "incoming_call", !isTapOnly, !callId.isEmpty else {
            completion()
            return
        }
        let fromUserId = dict["fromUserId"] as? String
        let fromName = Self.sanitizedName(dict["fromName"] as? String) ?? "Slide"
        let callTypeRaw = (dict["callType"] as? String) ?? CallType.oneToOne.rawValue
        let callType = CallType(rawValue: callTypeRaw) ?? .oneToOne
        let hasVideo = Self.boolValue(dict["videoEnabled"]) ?? true
        let ringStyle = (dict["ringStyle"] as? String)
            ?? ((Self.boolValue(dict["knock"]) ?? false) ? "knock" : "call")
        // Knocks ring anonymously — the whole point is "knock knock, who's
        // there?": you find out by answering. Normal calls show the name.
        let isKnock = ringStyle == "knock"
        let displayName = isKnock ? "Knock knock…" : fromName
        let handle = isKnock ? "Knock Knock" : fromName

        // CRITICAL: report an incoming call to CallKit synchronously on every
        // VoIP push, before returning, or iOS will kill the app. We mint a
        // stable UUID derived from the callId so the in-app accept path can
        // match this CallKit call to the server-side call.
        let uuid = Self.uuid(for: callId)
        CallKitManager.shared.reportIncomingCall(
            uuid: uuid, handle: handle, displayName: displayName,
            hasVideo: hasVideo) { _ in completion() }

        // Hand off to the app layer so answering actually joins the call.
        onIncomingCall?(callId, fromUserId, fromName, callType, hasVideo, ringStyle)
    }

    /// Derive a stable UUID from the server call id so the CallKit call UUID is
    /// the same one AppState uses for this call. Falls back to a random UUID.
    static func uuid(for callId: String) -> UUID {
        if let u = UUID(uuidString: callId) { return u }
        // Deterministic UUID from an arbitrary string via a hash of its bytes.
        var bytes = Array(callId.utf8)
        var digest = [UInt8](repeating: 0, count: 16)
        for (i, b) in bytes.enumerated() { digest[i % 16] ^= b &+ UInt8(i & 0xff) }
        // Set version (4) and variant bits so it's a well-formed UUID.
        digest[6] = (digest[6] & 0x0f) | 0x40
        digest[8] = (digest[8] & 0x3f) | 0x80
        bytes.removeAll()
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3],
                           digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11],
                           digest[12], digest[13], digest[14], digest[15]))
    }

    private static func sanitizedName(_ value: String?) -> String? {
        guard let name = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              name.localizedCaseInsensitiveCompare("unknown") != .orderedSame,
              name.localizedCaseInsensitiveCompare("someone") != .orderedSame else {
            return nil
        }
        return name
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool:
            return b
        case let s as String:
            if s.caseInsensitiveCompare("true") == .orderedSame { return true }
            if s.caseInsensitiveCompare("false") == .orderedSame { return false }
            return nil
        case let n as NSNumber:
            return n.boolValue
        default:
            return nil
        }
    }
}
