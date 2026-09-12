import Foundation
import SwiftUI
import AVFoundation

/// Owns the `CallService` for one date: join on appear, mirror mute/camera/
/// flip state, and the 5-minute ending sequence (60s haptic, last-10s ticks,
/// knock-knock + a 1.2s "Time!" overlay + `onTimeUp` at zero). Doesn't touch
/// `AppState.dateFlow` itself — `DateView` wires `onTimeUp` to
/// `AppState.handleLocalDateTimeout`.
@MainActor
final class DateViewModel: ObservableObject {
    let date: DateSession
    let callService: CallService
    /// AppState's server-offset-corrected clock, attached right after init
    /// (see `DateView.onAppear`) so the endgame cues fire at the same moment
    /// as the on-screen `CountdownRing`/mm:ss label, not off the device's own
    /// (possibly skewed) clock.
    private weak var clock: SessionClock?

    @Published var connectionState: CallConnectionState = .idle
    @Published var isMuted = false
    @Published var isVideoEnabled = true
    @Published var isUsingFrontCamera = true
    /// Speaker vs. earpiece routing. Video dates start on speaker (the call
    /// service configures `.defaultToSpeaker`), so this defaults to true.
    @Published var isSpeakerOn = true
    @Published var hasRemoteVideo = false
    /// True once the partner's video has shown up at least once. Distinct
    /// from `hasRemoteVideo` (which can go back to false mid-date — camera
    /// toggled off, a brief network hiccup) so the UI can tell "never
    /// connected" apart from "was connected, dropped for a moment".
    @Published private(set) var hasEverConnected = false
    /// True once 20s have passed with no remote video and the partner never
    /// showed up (SPEC: "They didn't make it" -> Decision still offered).
    /// Reset if the connection later succeeds, so a mid-date drop doesn't
    /// resurface this stale copy.
    @Published var connectingTimedOut = false
    /// True when camera access was actually denied (as opposed to just not
    /// having video yet), so DateView can explain the black local thumbnail
    /// instead of leaving it silent.
    @Published private(set) var cameraPermissionDenied = false
    /// True for the 1.2s "Time!" beat between the knock-knock cue and
    /// `onTimeUp` firing.
    @Published var showTimeUpOverlay = false

    /// Fires once, right when the "Time!" overlay finishes.
    var onTimeUp: (() -> Void)?

    private var connectTimeoutTask: Task<Void, Never>?
    private var endgameTask: Task<Void, Never>?
    private var playedSixtySecondCue = false
    private var lastTickSecond: Int?
    private var firedTimeUp = false

    init(date: DateSession) {
        self.date = date
        self.callService = CallServiceFactory.make()
        callService.delegate = self
    }

    /// Must be called before `join()` so the endgame cues use the same
    /// server-corrected clock as the visible countdown.
    func attach(clock: SessionClock) {
        self.clock = clock
    }

    func join() {
        armConnectTimeout()
        armEndgameCues()
        startMediaAndJoin()
    }

    /// "Try again" on the couldn't-connect overlay: re-does the permission
    /// preflight and call-service join without re-arming the endgame cues,
    /// which are already running against the date's own clock.
    func retryJoin() {
        connectingTimedOut = false
        armConnectTimeout()
        startMediaAndJoin()
    }

    /// Explicit camera/mic preflight (SPEC: fail cleanly instead of a silent
    /// call) before actually joining the room. On a fresh install camera
    /// authorization is `.notDetermined`, and nothing else in the call path
    /// ever prompts for it, so without this a first date silently has no
    /// video and no explanation.
    private func startMediaAndJoin() {
        Task { [weak self] in
            guard let self else { return }
            _ = await MediaPermissions.requestMicrophoneAccess()
            let cameraGranted = await MediaPermissions.requestCameraAccess()
            guard !Task.isCancelled else { return }
            self.cameraPermissionDenied = !cameraGranted
            self.callService.join(session: self.date, videoEnabled: cameraGranted)
        }
    }

    private func armConnectTimeout() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, !Task.isCancelled, !self.hasRemoteVideo else { return }
            self.connectingTimedOut = true
        }
    }

    func leave() {
        connectTimeoutTask?.cancel()
        endgameTask?.cancel()
        callService.leave()
    }

    func toggleMute() {
        isMuted.toggle()
        callService.setMuted(isMuted)
        Haptics.tap()
    }

    func toggleVideo() {
        isVideoEnabled.toggle()
        callService.setVideoEnabled(isVideoEnabled)
        Haptics.tap()
    }

    func flipCamera() {
        callService.flipCamera()
        isUsingFrontCamera = callService.isUsingFrontCamera
        Haptics.tap()
    }

    /// Explicit speaker/earpiece override. There's no system call UI here to manage
    /// routing, so this flips the shared `AVAudioSession`'s output port
    /// directly (the call's own `.playAndRecord` session stays untouched).
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
        Haptics.tap()
    }

    /// Server-offset-corrected clock against `date.endsAt` (not a
    /// locally-started countdown), so a briefly-backgrounded app still fires
    /// close to on time once it's back in the foreground, and a skewed
    /// device clock doesn't drift the cues away from what the ring/mm:ss
    /// label are showing.
    private func remainingSeconds() -> TimeInterval {
        if let clock { return clock.secondsRemaining(to: date.endsAt) }
        return max(0, date.endsAt.timeIntervalSinceNow)
    }

    private func armEndgameCues() {
        endgameTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let remaining = self.remainingSeconds()
                if remaining <= 0 { break }
                if remaining <= 60, !self.playedSixtySecondCue {
                    self.playedSixtySecondCue = true
                    Haptics.gentle()
                }
                if remaining <= 10 {
                    let second = Int(remaining.rounded(.up))
                    if second != self.lastTickSecond {
                        self.lastTickSecond = second
                        SoundEffects.play(.tick)
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard let self, !Task.isCancelled, !self.firedTimeUp else { return }
            self.firedTimeUp = true
            // A session that never actually connected has nothing to end —
            // playing the knock-knock cue and forcing Decision here would
            // stack a "Time!" overlay on top of the still-showing
            // connecting/failed state and walk the user into "keep talking
            // with X?" for a partner they never met. Leave it to the
            // server's own date-expirer (date_ended) or the user's own
            // Continue/Leave tap instead.
            guard self.hasEverConnected else { return }
            SoundEffects.play(.knockknock)
            Haptics.strong()
            self.showTimeUpOverlay = true
            // Hold the "Time!" beat for 1.2s (still connected) before the
            // room is left and AppState moves on to Decision.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self.onTimeUp?()
        }
    }
}

extension DateViewModel: CallServiceDelegate {
    nonisolated func callService(_ service: CallService, didChange state: CallConnectionState) {
        Task { @MainActor in self.connectionState = state }
    }

    nonisolated func callServiceRemoteVideoBecameAvailable(_ service: CallService) {
        Task { @MainActor in
            self.hasRemoteVideo = service.hasRemoteVideo
            if self.hasRemoteVideo {
                if !self.hasEverConnected {
                    SoundEffects.play(.found)
                }
                self.hasEverConnected = true
                // A stale "they didn't make it" from an earlier slow connect
                // must not resurface once the connection actually succeeds.
                self.connectingTimedOut = false
            }
        }
    }
}
