import Foundation

/// Ticks once a second and derives countdown strings from a `SessionWindow`
/// or a date's `endsAt`, corrected for clock drift using the server's
/// reported time at the moment the window was last fetched.
@MainActor
final class SessionClock: ObservableObject {
    @Published private(set) var now: Date = Date()

    private var timer: Timer?
    /// serverTime - localTime, captured whenever `update(from:)` runs.
    private var serverOffset: TimeInterval = 0

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    deinit { timer?.invalidate() }

    /// Recalibrate against the server's clock (call whenever `/session` is
    /// refetched).
    func update(from window: SessionWindow) {
        serverOffset = window.serverTime.timeIntervalSince(Date())
    }

    private func tick() {
        now = Date().addingTimeInterval(serverOffset)
    }

    /// "2h 14m" / "41m" / "38s" style countdown, big-and-light on Tonight.
    func countdown(to target: Date) -> String {
        let remaining = max(0, target.timeIntervalSince(now))
        let totalSeconds = Int(remaining)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    /// "4:32" mm:ss countdown — the date timer.
    func mmss(to target: Date) -> String {
        let remaining = max(0, target.timeIntervalSince(now))
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Seconds left until `target`, clamped to zero.
    func secondsRemaining(to target: Date) -> TimeInterval {
        max(0, target.timeIntervalSince(now))
    }

    /// 1.0 (just started) -> 0.0 (time's up) between `start` and `end`, for
    /// `CountdownRing`.
    func progress(from start: Date, to end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let remaining = max(0, end.timeIntervalSince(now))
        return min(1, max(0, remaining / total))
    }
}
