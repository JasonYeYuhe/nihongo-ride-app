import Testing
import Foundation
import GameCore
import RomajiKana
import ReviewKit
import VocabKit
@testable import ConjugationReviewKit

/// **The conjugation drill cannot award a 4, and the rubric's own doc comment used to deny it.**
///
/// `ConjugationSRSCard.quality(from:)` ends `outcome.durationRatio <= 1.5 ? 5 : 4` under a
/// comment that claimed parity with `SRSCard.quality(from:)`. The rubric text IS the same. The
/// behaviour is not: `ConjugationSession` constructs its `TypingOutcome` without a
/// `durationRatio`, so the value defaults to 1.0, the comparison is always true, and every
/// clean answer is graded 5 no matter how long it took.
///
/// The existing rubric test could not see this and cannot be blamed for it —
/// `ConjugationReviewKitTests.qualityMapping` passes `durationRatio: 1.0` and `2.0` in by hand
/// and asserts 5 and 4. Both assertions are correct. Neither is reachable from production,
/// because production never supplies the argument. **A unit test on a predicate is not a test
/// of the thing that uses it**, and this suite exists to say so from the other side: it drives
/// a real `ConjugationSession` and asserts what the session actually emits.
///
/// The repo already knew, and said so in the wrong place: `ConjugationOutcome.durationRatio`
/// carries the doc comment "Unused by the v1.8 drill (no per-prompt timing yet)". One file
/// recorded the truth while another asserted the opposite, and nothing compared them.
///
/// v1.26 deliberately ships the finding and not the fix — see the doc comment on
/// `quality(from:)` for why the baseline is a decision this release cannot make honestly.
/// When the prompt clock IS wired, these tests go red, and that is their whole job: they pin
/// a known-false comment so it cannot quietly become true (or stay false) unnoticed.
@Suite("The conjugation drill supplies no per-prompt timing")
struct NoPromptTimingTests {

    private static func prompt() -> ConjugationPrompt {
        ConjugationPrompt(sourceID: "a", surface: "食べる", dictKana: "たべる", gloss: "eat",
                          verbClass: .ichidan, targetForm: .polite, conjugatedKana: "たべます")
    }

    /// A clock that advances thirty seconds per reading — 240 seconds to type たべます. If any
    /// timing reached the outcome at all, this could not come back as 1.0.
    private final class SlowClock: @unchecked Sendable {
        private var t = Date(timeIntervalSince1970: 0)
        /// How many times the session asked what time it is. **This is the finding**, not
        /// bookkeeping: on a clean answer `ConjugationSession` asks ZERO times, because its only
        /// `now()` call is on the mistype path. An earlier version of these tests, and the doc
        /// comment on `quality(from:)`, described "a probe driving a real session with a clock
        /// advancing 30 seconds per keystroke" — the clock was never consulted, so the 1.0 came
        /// from `TypingOutcome`'s default argument and not from a measurement of elapsed time.
        /// The conclusion was right and the account of how it was reached was not.
        private(set) var asks = 0
        func next() -> Date { asks += 1; t = t.addingTimeInterval(30); return t }
    }

    @Test("a clean answer typed absurdly slowly still reports durationRatio 1.0")
    func slowAnswerReportsNoTiming() throws {
        let clock = SlowClock()
        let session = ConjugationSession(prompts: [Self.prompt()], now: clock.next)
        var seen: TypingOutcome?
        session.onOutcome = { _, outcome in seen = outcome }
        for character in KanaRomanizer.romaji(for: "たべます") {
            session.input(character)
        }
        let outcome = try #require(seen, "the session emitted no outcome at all")
        #expect(outcome.completed)
        #expect(outcome.mistakes == 0)
        #expect(clock.asks == 0, Comment(rawValue:
            "the session consulted the clock \(clock.asks) time(s) on a clean answer. If that is "
            + "now non-zero the drill has gained timing and `quality(from:)`'s doc comment — "
            + "which says its last line is a constant — must be revisited"))
        #expect(outcome.durationRatio == 1.0, Comment(rawValue:
                "the session now supplies timing (\(outcome.durationRatio)) — the rubric's last "
                + "line is no longer a constant, so quality(from:)'s doc comment must be revisited"))
    }

    /// **The negative control, and it matters more than the result.**
    ///
    /// "The reported ratio was 1.0" is worth nothing on its own — a probe that cannot observe
    /// timing at all would report exactly that, and so would a session driven in a way that
    /// never consults the clock. (The `SlowClock` above is, on a mistake-free answer, never
    /// asked the time; that is the finding, not the method.) So the identical slow typing is
    /// driven through `GameSession`, which DOES compute a ratio from the same kind of injected
    /// clock. If this comes back 1.0 too, the harness is blind and the test above proves
    /// nothing.
    @Test("the same slow typing through GameSession DOES produce a ratio — so the probe can see timing")
    func gameSessionSeesTheSameClock() throws {
        let entry = VocabEntry(id: "w", surface: "食べる", kana: "たべる",
                               partsOfSpeech: ["v"], jlpt: .n5, meanings: ["en": ["eat"]])
        let clock = SlowClock()
        var config = GameSession.Config()
        config.recordsSRS = true
        let session = GameSession(words: [entry], review: ReviewStore(),
                                  config: config, now: clock.next)
        for character in KanaRomanizer.romaji(for: "たべる") {
            session.input(character)
        }
        // GameSession emits no callback — it records into its own store, so the grade is read
        // back from the card. SM-2 here adds 0.10 to the ease factor at q=5 and exactly 0.000
        // at q=4, so the ease factor IS the grade, observed rather than asserted.
        let card = try #require(session.review.card(for: "w"),
                                "GameSession recorded nothing — the control is broken")
        let fresh = SRSCard(id: "unused").easeFactor
        #expect(card.easeFactor == fresh, Comment(rawValue:
            "the control is blind: GameSession graded this 5 (ease \(card.easeFactor)) for typing "
            + "that took minutes, so a 5 from the conjugation session proves nothing"))
        // Stated the other way round, so the contrast is explicit: the vocabulary path grades
        // this typing 4 and the conjugation path grades identical typing 5.
        var wouldBeFive = SRSCard(id: "control")
        wouldBeFive.review(quality: 5)
        #expect(card.easeFactor < wouldBeFive.easeFactor,
                "the vocabulary path must have withheld the q=5 bonus for this to be a contrast")
    }

    /// The consequence, stated as the grade the learner's schedule actually receives. This is
    /// the assertion that matters: not "the ratio is 1.0" but "a laboured answer is graded as
    /// instant recall", which is what moves the ease factor and syncs to every device.
    @Test("so a laboured clean answer is graded 5, the same as an instant one")
    func laboredAnswerIsGradedFive() throws {
        let clock = SlowClock()
        let session = ConjugationSession(prompts: [Self.prompt()], now: clock.next)
        var seen: TypingOutcome?
        session.onOutcome = { _, outcome in seen = outcome }
        for character in KanaRomanizer.romaji(for: "たべます") {
            session.input(character)
        }
        let outcome = try #require(seen)
        // The exact conversion AppModel.recordConjugationOutcome performs. It carries the ratio
        // faithfully — the value was never dropped in transit, it was never supplied at source.
        let graded = ConjugationOutcome(completed: outcome.completed, mistakes: outcome.mistakes,
                                        usedHint: outcome.usedHint,
                                        durationRatio: outcome.durationRatio)
        #expect(ConjugationSRSCard.quality(from: graded) == 5,
                "a four is unreachable from production; if this is now 4 the clock was wired")

        // And the ease-factor consequence, so the cost is recorded next to the cause. A q=4
        // cannot LOWER an ease factor in this implementation — the delta is exactly 0.000, and
        // q <= 2 takes the lapse branch and applies no delta at all — but a q=5 RAISES it by
        // 0.10 every time, which is what makes a struggled form leave the rotation early.
        var card = ConjugationSRSCard(id: "a#polite")
        let baseline = card.easeFactor
        card.review(quality: 5)
        #expect(card.easeFactor > baseline, "q=5 must raise the ease factor for this to matter")
        var four = ConjugationSRSCard(id: "b#polite")
        let fourBaseline = four.easeFactor
        four.review(quality: 4)
        #expect(four.easeFactor == fourBaseline, "q=4 is neutral, not punitive")
    }
}
