import AudioToolbox

/// Tiny, asset-free sound cues via system sounds — no audio session juggling,
/// safe on device and simulator. Used sparingly: moments that matter, not chrome.
enum SoundEffects {
    /// Short bright "they're here" tink when the other person joins the call.
    static func connected() { AudioServicesPlaySystemSound(1057) }

    /// Soft tock when a call ends — the door closing.
    static func ended() { AudioServicesPlaySystemSound(1306) }
}
