import Testing
import Foundation
import VocabKit
import ReviewKit
@testable import GameCore

/// v1.16 §A. The app had an always-on romaji display and a reveal path that charges the
/// honest price (usedHint, minimal score, SRS lapse) — fully scored, fully tested, and
/// reachable from nowhere: no view ever called `revealHint()`. Both plan reviewers rejected
/// auto-showing corrections mid-word; this is the replacement. These tests pin the three
/// promises: the answer is only ever OFFERED, taking it costs what it always cost, and a
/// slipped finger or a held key is not "struggle".
@Suite("One assistance policy")
struct AssistanceTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func word(_ id: String = "w1", kana: String = "こんにちは") -> VocabEntry {
        VocabEntry(id: id, surface: kana, kana: kana, partsOfSpeech: ["n"],
                   jlpt: .n5, meanings: ["en": ["hello"]])
    }

    private func session(_ mode: AssistanceMode, gameMode: GameMode = .journey,
                         words: [VocabEntry]? = nil,
                         clock: @escaping () -> Date) -> GameSession {
        var config = GameSession.Config()
        config.assistance = mode
        config.mode = gameMode
        return GameSession(words: words ?? [word()], config: config, now: clock)
    }

    // MARK: the detector

    @Test("a held key is one attempt, however long it is held")
    func autorepeatIsOneAttempt() {
        var d = StruggleDetector()
        let key = StruggleDetector.StateKey(wordIndex: 0, kanaIndex: 4, acceptedRomaji: "konnichi")
        // Autorepeat at ~15 keys/s: same character, 67 ms apart, forever.
        for i in 0..<50 {
            d.record("w", at: key, time: at(Double(i) * 0.067))
        }
        #expect(d.attempts == 1, "50 autorepeats counted as \(d.attempts) attempts")
    }

    @Test("a held key can never reach the offer threshold by itself")
    func heldKeyNeverReachesThreshold() {
        // The REAL macOS autorepeat profile, which the uniform-interval test above does not
        // model: an initial delay (default 375 ms — above `repeatGap`, so it counts), then a
        // fast periodic stream (default 90 ms — below it, so it does not). The system values
        // on this machine are unset, i.e. these defaults. A learner who rests a finger on a
        // wrong key must not be told they are stuck.
        var d = StruggleDetector()
        let key = StruggleDetector.StateKey(wordIndex: 0, kanaIndex: 4, acceptedRomaji: "konnichi")
        d.record("w", at: key, time: at(0))                 // the press itself
        d.record("w", at: key, time: at(0.375))             // first repeat, past the gap
        for i in 1...80 { d.record("w", at: key, time: at(0.375 + Double(i) * 0.090)) }
        #expect(d.attempts == 2, "a hold is worth 2, got \(d.attempts)")
        #expect(d.attempts < GameSession.struggleOfferThreshold,
                "the threshold must stay strictly above what one held key can produce")
    }

    @Test("deliberate re-presses of the same key DO count")
    func deliberateRepeatCounts() {
        var d = StruggleDetector()
        let key = StruggleDetector.StateKey(wordIndex: 0, kanaIndex: 4, acceptedRomaji: "konnichi")
        d.record("w", at: key, time: at(0))
        d.record("w", at: key, time: at(1.0))    // a second, considered press
        d.record("w", at: key, time: at(2.2))
        #expect(d.attempts == 3)
    }

    @Test("a different matcher state is a different struggle")
    func stateChangeResets() {
        var d = StruggleDetector()
        let k1 = StruggleDetector.StateKey(wordIndex: 0, kanaIndex: 4, acceptedRomaji: "konnichi")
        let k2 = StruggleDetector.StateKey(wordIndex: 0, kanaIndex: 5, acceptedRomaji: "konnichiha")
        d.record("w", at: k1, time: at(0))
        d.record("x", at: k1, time: at(1))
        #expect(d.attempts == 2)
        d.record("q", at: k2, time: at(2))
        #expect(d.attempts == 1, "progress must clear the count — same-word-different-place is a new wall")
    }

    // MARK: the offer, end to end

    @Test("struggling at the same kana produces an offer; taking it charges the lapse")
    func offerAndItsPrice() {
        var now = t0
        let s = session(.afterStruggle, clock: { now })
        // Type up to the は of こんにちは, then hit the wall the way a learner does.
        for c in "konnichi" { _ = s.input(c) }
        #expect(!s.assistanceOffered)
        #expect(!s.romajiVisible, "afterStruggle shows nothing until asked")

        for (i, c) in ["w", "o", "w"].enumerated() {
            now = t0.addingTimeInterval(Double(i + 1))
            _ = s.input(Character(c))
        }
        #expect(s.assistanceOffered, "three distinct refusals at は is the definition of stuck")

        s.revealHint()
        #expect(s.romajiVisible, "the reveal shows the answer for THIS word")
        #expect(!s.assistanceOffered, "the offer is consumed")

        for c in "ha" { _ = s.input(c) }
        #expect(s.wordsCompleted == 1)
        // The price: revealed words score minimally and lapse — the pre-existing path.
        #expect(s.score == 10, "a revealed word must not score like a recalled one, got \(s.score)")
    }

    @Test("accepted progress cancels the struggle")
    func progressResets() {
        var now = t0
        let s = session(.afterStruggle, clock: { now })
        for c in "konnichi" { _ = s.input(c) }
        now = at(1); _ = s.input("w")
        now = at(2); _ = s.input("x")
        #expect(!s.assistanceOffered, "two attempts is not yet stuck")
        _ = s.input("h")                       // correct key — the learner worked it out
        now = at(3); _ = s.input("z")
        now = at(4); _ = s.input("q")
        #expect(!s.assistanceOffered, "the count must restart after progress")
    }

    @Test("the reveal no longer turns hints on for the rest of the run")
    func revealIsPerWord() {
        // The old revealHint() set showRomajiHint = true SESSION-WIDE: one reveal put the
        // answer on screen for every later word. Unreachable from the UI, so nobody hit it —
        // but the offer makes it reachable, so the scope had to be fixed first.
        var now = t0
        let s = session(.afterStruggle, words: [word("w1"), word("w2", kana: "ねこ")],
                        clock: { now })
        for c in "konnichi" { _ = s.input(c) }
        for (i, c) in ["w", "o", "w"].enumerated() {
            now = t0.addingTimeInterval(Double(i + 1)); _ = s.input(Character(c))
        }
        s.revealHint()
        for c in "ha" { _ = s.input(c) }
        #expect(s.wordsCompleted == 1)
        #expect(!s.romajiVisible, "word 2 must start hidden again")
        #expect(!s.isRevealed)
    }

    @Test("Time Attack never offers")
    func timeAttackExcluded() {
        var now = t0
        let s = session(.afterStruggle, gameMode: .timeAttack, clock: { now })
        for c in "konnichi" { _ = s.input(c) }
        for i in 1...6 {
            now = t0.addingTimeInterval(Double(i))
            _ = s.input(i % 2 == 0 ? "w" : "o")
        }
        #expect(!s.assistanceOffered, "the timer runs regardless; an offer there is a trap")
    }

    @Test("always shows, off stays silent — and neither ever offers")
    func alwaysAndOff() {
        var now = t0
        let a = session(.always, clock: { now })
        #expect(a.romajiVisible)
        let o = session(.off, clock: { now })
        #expect(!o.romajiVisible)
        for c in "konnichi" { _ = o.input(c) }
        for i in 1...6 {
            now = t0.addingTimeInterval(Double(i))
            _ = o.input(i % 2 == 0 ? "w" : "o")
        }
        #expect(!o.assistanceOffered, "off means off — the learner asked to be left alone")
    }

    @Test("a pause makes the struggle stale")
    func pauseResets() {
        var now = t0
        let s = session(.afterStruggle, clock: { now })
        for c in "konnichi" { _ = s.input(c) }
        now = at(1); _ = s.input("w")
        now = at(2); _ = s.input("o")
        s.resetStruggle()                       // what the pause/background hook calls
        now = at(3); _ = s.input("w")
        #expect(!s.assistanceOffered, "the learner had time to think; the count starts over")
    }
}
