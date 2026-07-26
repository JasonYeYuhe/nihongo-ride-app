import Testing
import Foundation
@testable import GameCore

/// A run's recorded speed used to be computed from wall clock while the game's own timer
/// already stopped for the pause overlay, a sheet over the game, and the app leaving the
/// foreground. A 60-second Time Attack paused for five minutes went into the ride journal at
/// about one sixth of the rider's real speed — and stayed there, in the Ride Log row, the
/// speed sparkline, the Stats bar and `bestWPM`.
@Suite("RunClock — paused time is not ridden time")
struct RunClockTests {

    /// A fixed origin; every instant below is an offset from it, so nothing waits on a real
    /// clock and the arithmetic is exact.
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test("20s ridden, 180s paused, 40s ridden → 60s")
    func excludesPause() {
        var c = RunClock(startedAt: t0)
        c.pause(at: at(20))
        c.resume(at: at(200))
        #expect(c.elapsed(at: at(240)) == 60)
    }

    @Test("with no pauses it is plain wall clock")
    func noPauses() {
        let c = RunClock(startedAt: t0)
        #expect(c.elapsed(at: at(90)) == 90)
        #expect(c.elapsed(at: t0) == 0)
    }

    @Test("a run that ENDS paused still excludes the pause in flight")
    func endsWhilePaused() {
        // Real: the rider backgrounds the app mid-run and iOS terminates it. Without the
        // in-flight subtraction the whole suspended stretch counts as riding.
        var c = RunClock(startedAt: t0)
        c.pause(at: at(30))
        #expect(c.elapsed(at: at(3630)) == 30, "an hour suspended was counted as riding")
    }

    @Test("overlapping pauses do not restart the pause")
    func doublePauseIgnored() {
        // The three signals genuinely overlap: backgrounding the app while the pause overlay
        // is already up. The second pause must not discard the first one's start instant.
        var c = RunClock(startedAt: t0)
        c.pause(at: at(10))
        c.pause(at: at(15))          // ignored
        c.resume(at: at(70))
        #expect(c.elapsed(at: at(80)) == 20, "lost the first 5s of the pause")
    }

    @Test("a resume with no pause credits nothing")
    func strayResumeIgnored() {
        var c = RunClock(startedAt: t0)
        c.resume(at: at(50))
        #expect(c.elapsed(at: at(60)) == 60)
        #expect(!c.isPaused)
    }

    @Test("several pauses accumulate")
    func multiplePauses() {
        var c = RunClock(startedAt: t0)
        c.pause(at: at(10));  c.resume(at: at(40))     // 30 excluded
        c.pause(at: at(60));  c.resume(at: at(75))     // 15 excluded
        #expect(c.elapsed(at: at(100)) == 55)
    }

    @Test("elapsed never goes negative, whatever the instants")
    func neverNegative() {
        // Wall clocks move backwards (NTP, manual change, DST on a naive clock). A negative
        // duration would divide into a negative or infinite WPM and land in the journal.
        var c = RunClock(startedAt: t0)
        #expect(c.elapsed(at: at(-100)) == 0)
        c.pause(at: at(10))
        c.resume(at: at(5))                            // resumed "before" it paused
        #expect(c.elapsed(at: at(20)) == 20)
    }

    @Test("WPM uses ridden time — the whole point")
    func wpmUsesRiddenTime() {
        // 300 correct keystrokes = 60 words. Over 60 ridden seconds that is 60 wpm, whether
        // or not the rider stared at a pause overlay for three minutes in the middle.
        var c = RunClock(startedAt: t0)
        c.pause(at: at(20))
        c.resume(at: at(200))
        #expect(c.wpm(correctKeystrokes: 300, at: at(240)) == 60)

        let straight = RunClock(startedAt: t0)
        #expect(straight.wpm(correctKeystrokes: 300, at: at(60)) == 60)
        // Wall clock would have said 15 — the number that used to be written.
        #expect(straight.wpm(correctKeystrokes: 300, at: at(240)) == 15)
    }

    @Test("a run too short or with no correct keys has no speed")
    func noMeaningfulSpeed() {
        let c = RunClock(startedAt: t0)
        #expect(c.wpm(correctKeystrokes: 300, at: at(1.9)) == 0)
        #expect(c.wpm(correctKeystrokes: 0, at: at(60)) == 0)
        // The threshold is on RIDDEN time, so a long pause CAN take a wall-clock-long run
        // below it. Ten minutes of wall clock, 1.5s of actual typing → no speed.
        var paused = RunClock(startedAt: t0)
        paused.pause(at: at(1))
        paused.resume(at: at(600))
        #expect(paused.elapsed(at: at(600.5)) == 1.5)
        #expect(paused.wpm(correctKeystrokes: 300, at: at(600.5)) == 0)
        // And exactly 2s still counts — the boundary is `>= 2`, unchanged from the wall-clock
        // version, so this fix cannot quietly reclassify anyone's short runs.
        #expect(paused.wpm(correctKeystrokes: 300, at: at(601)) == 1800)
    }
}
