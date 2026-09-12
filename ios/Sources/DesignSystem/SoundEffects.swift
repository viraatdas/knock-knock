import AVFoundation

/// Bundled `.caf` sound cues, played via `AVAudioPlayer`. Deliberately never
/// touches the shared `AVAudioSession` category — `RealCallService` owns that
/// for the date's `.playAndRecord` session, and a sound effect fired mid-date
/// (the 5-minute knock-knock, the last-10-seconds tick) must not fight it.
/// Safe to call from anywhere, including the simulator: a missing file is a
/// silent no-op, never a crash.
enum Sound: String, CaseIterable {
    /// Two warm knocks: the 5-minute mark ends the date.
    case knockknock
    /// A single knock: the 7 PM doors-open push sound, the welcome greeting.
    case knock
    /// Rising three-note marimba: a match.
    case match
    /// Two quick rising notes: partner found / date starting.
    case found
    /// Two soft descending notes: the date is over.
    case ended
    /// A short soft tick: the last 10 seconds, once per second.
    case tick
    /// Soft pop on sending a chat message.
    case message
    /// Slightly lower pop for an incoming chat message.
    case message_received
}

enum SoundEffects {
    private static var players: [Sound: AVAudioPlayer] = [:]

    /// Play a cue. Preloads and caches the player on first use.
    static func play(_ sound: Sound) {
        guard let player = player(for: sound) else { return }
        player.currentTime = 0
        player.play()
    }

    private static func player(for sound: Sound) -> AVAudioPlayer? {
        if let existing = players[sound] { return existing }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") else {
            return nil
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[sound] = player
        return player
    }
}
