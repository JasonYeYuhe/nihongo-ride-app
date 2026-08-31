import Foundation

/// How long the learner has actually been *working on the current word or prompt*, excluding
/// time the app itself said they were not typing.
///
/// **Two defects share this type, and they are the same defect.** `GameSession` measured a
/// word's duration as raw wall clock (`now() - wordStartedAt`), so a rider who opened the pause
/// overlay mid-word, or backgrounded the app, or opened the add-to-lists sheet, was graded on
/// the time they were away — the ride's own `RunClock` had already stopped for exactly those
/// three signals, and the per-word grade had not. And `ConjugationSession` measured nothing at
/// all, so every clean conjugation answer was graded 5 however long it took. The first is
/// `PLAN-V1.26` §B4; the second is its §C, deferred there because "there is no correct clock to
/// copy — `GameSession.durationRatio` is itself raw wall time". This is that clock.
///
/// It is `RunClock` restarted per prompt, and deliberately not a second implementation of the
/// same arithmetic: *one rule written twice will drift* is a lesson this repo has paid for three
/// times. The only thing this type adds is the part that made copying tempting — **restarting
/// preserves the paused state**, because a prompt can complete while the app is backgrounded and
/// the next one must not start running.
public struct PromptClock: Equatable, Sendable {
    private var clock: RunClock
    /// Whether the app currently says the learner is not typing. Held here, and not read off
    /// `clock`, because it has to survive `restart(at:)` — the flag belongs to the session, not
    /// to any one prompt.
    public private(set) var isPaused: Bool

    public init(startedAt: Date, paused: Bool = false) {
        var clock = RunClock(startedAt: startedAt)
        if paused { clock.pause(at: startedAt) }
        self.clock = clock
        self.isPaused = paused
    }

    /// Begins timing a new prompt. A clock that was paused stays paused.
    public mutating func restart(at instant: Date) {
        self = PromptClock(startedAt: instant, paused: isPaused)
    }

    /// The rider stopped: pause overlay, a sheet over the game, or the app leaving the
    /// foreground. Idempotent, because those three overlap in practice.
    public mutating func pause(at instant: Date) {
        clock.pause(at: instant)
        isPaused = true
    }

    /// The rider resumed. Ignored when not paused, so a stray resume cannot credit time.
    public mutating func resume(at instant: Date) {
        clock.resume(at: instant)
        isPaused = false
    }

    /// Seconds spent on this prompt, correct while still paused.
    public func elapsed(at instant: Date) -> TimeInterval { clock.elapsed(at: instant) }
}
