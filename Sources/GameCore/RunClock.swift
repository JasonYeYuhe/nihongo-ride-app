import Foundation

/// How long a run has actually been *ridden*, excluding time the rider was not typing
/// because the app said so.
///
/// The run's duration used to be plain wall clock — `Date() - runStartedAt` — while the
/// game's own timer already stopped for three things: the pause overlay, the add-to-lists
/// sheet, and (on iOS) the app leaving the foreground. So a 60-second Time Attack paused
/// for five minutes was written to the ride journal at about one sixth of the speed the
/// rider actually typed, and that number is permanent: it is the row in the Ride Log, a
/// point on the speed sparkline, a bar in Stats, and a candidate for `bestWPM`.
///
/// A value type with no clock of its own — every method takes the instant — so the whole
/// thing is testable without waiting for time to pass.
public struct RunClock: Equatable, Sendable {
    private let startedAt: Date
    /// When the current pause began, if one is in progress.
    private var pausedAt: Date?
    /// Time already excluded by completed pauses.
    private var excluded: TimeInterval = 0

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    /// Pausing while already paused is ignored rather than restarting the pause — the three
    /// signals overlap in practice (backgrounding the app while the pause overlay is up),
    /// and the second one must not discard the first one's start.
    public mutating func pause(at instant: Date) {
        guard pausedAt == nil else { return }
        pausedAt = instant
    }

    /// Resuming when not paused is ignored, so a stray resume cannot credit the rider with
    /// time they did not spend.
    public mutating func resume(at instant: Date) {
        guard let began = pausedAt else { return }
        excluded += max(0, instant.timeIntervalSince(began))
        pausedAt = nil
    }

    public var isPaused: Bool { pausedAt != nil }

    /// Ridden time as of `instant`. Correct while still paused — a run can END paused (the
    /// user backgrounds the app and it is terminated), and the in-flight pause has to come
    /// off too or that whole stretch is counted as riding.
    public func elapsed(at instant: Date) -> TimeInterval {
        let inFlight = pausedAt.map { max(0, instant.timeIntervalSince($0)) } ?? 0
        return max(0, instant.timeIntervalSince(startedAt) - excluded - inFlight)
    }

    /// Words per minute over the ridden time, by the app's convention: a run under two
    /// seconds, or with no correct keystrokes, has no meaningful speed.
    ///
    /// Lives here rather than at the call site so the Ride Log, the sparkline and the live
    /// readout cannot drift into three different definitions of the same number.
    public func wpm(correctKeystrokes: Int, at instant: Date) -> Double {
        let seconds = elapsed(at: instant)
        guard seconds >= 2, correctKeystrokes > 0 else { return 0 }
        return (Double(correctKeystrokes) / 5.0) / (seconds / 60)
    }
}
