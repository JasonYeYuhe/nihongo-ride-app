import Testing
import Foundation
@testable import GameCore

/// `PromptClock` is `RunClock` restarted per word, and the one thing it adds is the one thing
/// worth testing directly: **restarting preserves the paused state.**
///
/// That clause exists because a prompt boundary can happen while the app says the learner is
/// away — `GameSession.skip()` is bound to Enter in `PracticeView`, which has no pause overlay
/// and only a `scenePhase` signal — and a new prompt whose clock started running during the
/// remainder of that absence would then be graded on it. Worse, silently: the later
/// `resumeTyping()` finds nothing paused and does nothing, so the excluded stretch is simply
/// lost.
///
/// It is tested here rather than only through a session because the session-level route to it is
/// narrow, and *an assertion that no defect can break looks exactly like one that holds*. The
/// first draft of the session test asserted this and survived a mutation that removed the clause
/// entirely — it paused after the boundary rather than across it.
@Suite("PromptClock — the paused flag outlives the prompt")
struct PromptClockTests {
    private let t0 = Date(timeIntervalSince1970: 0)
    private func t(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test("a restart while paused starts the next prompt stopped")
    func restartPreservesPause() {
        var clock = PromptClock(startedAt: t0)
        clock.pause(at: t(10))
        clock.restart(at: t(20))                    // the prompt boundary, while away
        #expect(clock.isPaused, "the app has not come back, so the new prompt is not running")
        #expect(clock.elapsed(at: t(300)) == 0, "…and no part of the absence is ridden time")
        clock.resume(at: t(300))
        #expect(!clock.isPaused)
        #expect(clock.elapsed(at: t(305)) == 5, Comment(rawValue: "only the five seconds since "
                + "the learner returned are this prompt's"))
    }

    @Test("…and the control: a restart while running starts the next prompt running")
    func restartWhileRunningKeepsRunning() {
        // Without this, the assertion above would also pass on a clock that was permanently
        // paused after any pause ever.
        var clock = PromptClock(startedAt: t0)
        clock.pause(at: t(10))
        clock.resume(at: t(20))
        clock.restart(at: t(30))
        #expect(!clock.isPaused)
        #expect(clock.elapsed(at: t(35)) == 5)
    }

    @Test("pausing twice does not restart the pause, and a stray resume credits nothing")
    func idempotence() {
        // The three app signals overlap — backgrounding while the pause overlay is up — so a
        // second pause must not discard the first one's start. Inherited from RunClock and
        // asserted here because PromptClock is what the sessions actually hold.
        var clock = PromptClock(startedAt: t0)
        clock.pause(at: t(10))
        clock.pause(at: t(50))                      // must be ignored
        clock.resume(at: t(60))
        #expect(clock.elapsed(at: t(60)) == 10, "the excluded stretch is 10→60, not 50→60")
        clock.resume(at: t(90))                     // stray resume, nothing paused
        #expect(clock.elapsed(at: t(90)) == 40)
    }
}
