import Foundation
import CallKit
import AVFoundation

/// Bridges Slide calls to the system call UI via CallKit (CXProvider) so calls
/// ring natively and integrate with the OS call experience.
protocol CallKitManagerDelegate: AnyObject {
    func callKitDidAnswer(callId: UUID)
    func callKitDidEnd(callId: UUID)
    func callKitDidSetMuted(callId: UUID, muted: Bool)
}

final class CallKitManager: NSObject, @unchecked Sendable {
    static let shared = CallKitManager()

    weak var delegate: CallKitManagerDelegate?

    private let provider: CXProvider
    private let callController = CXCallController()

    /// Maps our UUIDs to call ids (server-side string ids).
    private(set) var activeCallId: UUID?

    /// Short connected/ended chimes (see Resources/RINGTONE.md). Held strongly so
    /// playback isn't cut off by deallocation.
    private var chimePlayer: AVAudioPlayer?

    private func playChime(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.7
            player.prepareToPlay()
            player.play()
            chimePlayer = player
        } catch {
            // Non-fatal: a missing/unreadable chime just means no sound.
        }
    }

    override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.phoneNumber, .generic]
        config.includesCallsInRecents = true
        // Use a bundled custom ringtone only when one is present; otherwise CallKit
        // falls back to the default system ringtone. (See Resources/RINGTONE.md.)
        if Bundle.main.url(forResource: "ringtone", withExtension: "caf") != nil {
            config.ringtoneSound = "ringtone.caf"
        }
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: - Incoming

    func reportIncomingCall(uuid: UUID, handle: String, displayName: String,
                            hasVideo: Bool, completion: ((Error?) -> Void)? = nil) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.localizedCallerName = displayName
        update.hasVideo = hasVideo
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if error == nil { self?.activeCallId = uuid }
            completion?(error)
        }
    }

    // MARK: - Outgoing

    func startOutgoingCall(uuid: UUID, handle: String, displayName: String, hasVideo: Bool) {
        let cxHandle = CXHandle(type: .generic, value: handle)
        let action = CXStartCallAction(call: uuid, handle: cxHandle)
        action.isVideo = hasVideo
        action.contactIdentifier = displayName
        callController.request(CXTransaction(action: action)) { [weak self] error in
            if error == nil { self?.activeCallId = uuid }
        }

        let update = CXCallUpdate()
        update.localizedCallerName = displayName
        update.hasVideo = hasVideo
        provider.reportCall(with: uuid, updated: update)
    }

    func reportOutgoingConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        playChime("pickup")
    }

    // MARK: - End

    func endCall(uuid: UUID) {
        let action = CXEndCallAction(call: uuid)
        callController.request(CXTransaction(action: action)) { _ in }
    }

    func reportCallEnded(uuid: UUID, reason: CXCallEndedReason = .remoteEnded) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        playChime("hangup")
        if activeCallId == uuid { activeCallId = nil }
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        activeCallId = nil
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        delegate?.callKitDidAnswer(callId: action.callUUID)
        playChime("pickup")
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        delegate?.callKitDidEnd(callId: action.callUUID)
        if activeCallId == action.callUUID { activeCallId = nil }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        delegate?.callKitDidSetMuted(callId: action.callUUID, muted: action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}
