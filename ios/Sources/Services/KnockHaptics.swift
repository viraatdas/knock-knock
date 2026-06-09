import Foundation
import CoreHaptics
import AudioToolbox

/// Plays the physical sensation of a knock: a sharp transient ("thud") via
/// CoreHaptics plus a short, asset-free system "tock" sound per tap.
///
/// Asset-free by design — no bundled audio files. The sound uses
/// `AudioServicesPlaySystemSound`, which is reliable on device and simulator and
/// needs no audio-session juggling. The haptic uses a single sharp transient so
/// the caller and callee feel the same rhythm tap-for-tap.
///
/// Safe to call from anywhere: every method is a no-op when the device has no
/// haptic engine (e.g. the simulator) and the engine is created lazily.
/// What a knock sounds like — the user picks their own "door material" in
/// Profile. All system-provided short percussive sounds, no bundled assets.
enum KnockSound: String, CaseIterable {
    case wood, glass, soft

    var title: String {
        switch self {
        case .wood: return "Wood"
        case .glass: return "Glass"
        case .soft: return "Soft"
        }
    }

    var soundID: SystemSoundID {
        switch self {
        case .wood: return 1306   // Tock — classic knuckle on wood
        case .glass: return 1057  // Tink — bright, like a ring on glass
        case .soft: return 1104   // muted tap
        }
    }

    static var current: KnockSound {
        get {
            KnockSound(rawValue: UserDefaults.standard.string(forKey: "knockSound") ?? "") ?? .wood
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "knockSound")
        }
    }
}

@MainActor
final class KnockHaptics {
    static let shared = KnockHaptics()

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {}

    /// Warm up the haptic engine so the first tap fires without latency.
    func prepare() {
        guard supportsHaptics else { return }
        ensureEngine()
    }

    /// Fire one knock: a sharp haptic transient + the user's chosen knock
    /// sound. Call this once per tap — both when the caller taps the pad and
    /// when a knock is received.
    func knock() {
        AudioServicesPlaySystemSound(KnockSound.current.soundID)
        playTransient()
    }

    // MARK: - CoreHaptics

    private func ensureEngine() {
        guard supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            // Recreate the player path if the engine is reset out from under us.
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    private func playTransient() {
        guard supportsHaptics else { return }
        ensureEngine()
        guard let engine else { return }
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
        let event = CHHapticEvent(eventType: .hapticTransient,
                                  parameters: [intensity, sharpness],
                                  relativeTime: 0)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // If the engine misbehaves, drop it so the next call rebuilds it.
            engine.stop()
            self.engine = nil
        }
    }
}
