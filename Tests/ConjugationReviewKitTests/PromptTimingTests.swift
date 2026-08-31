import Testing
import Foundation
import GameCore
import RomajiKana
import ReviewKit
import VocabKit
@testable import ConjugationReviewKit

/// **The conjugation drill now has a clock, and it stops when the app says the learner is not
/// typing.** This file was `NoPromptTimingTests`, whose stated job was to pin a known-false
/// comment *"so it cannot quietly become true (or stay false) unnoticed"* — and it says of
/// itself: *"When the prompt clock IS wired, these tests go red, and that is their whole job."*
/// It is wired, they went red, and this is the same file asserting the other side.
///
/// WHAT WAS WRONG, kept because the shape recurs. `ConjugationSRSCard.quality(from:)` ends
/// `outcome.durationRatio <= 1.5 ? 5 : 4` under a comment that claimed parity with
/// `SRSCard.quality(from:)`. The rubric text WAS the same; the behaviour was not, because
/// `ConjugationSession` built its `TypingOutcome` without a `durationRatio`, so the value
/// defaulted to 1.0 and the comparison was a constant. Every clean answer graded 5, and q=5 adds
/// 0.10 to the ease factor while q=4 adds exactly 0.000 — so the forms a learner laboured over
/// left the rotation faster than a vocabulary card.
///
/// **And the negative-control discipline is kept rather than retired.** Every assertion below
/// about the new behaviour is paired with one that must come out the other way, driven through
/// the same harness with one variable changed. "A slow answer grades 4" would also pass on a
/// session that graded everything 4; "the pause is honoured" would also pass on a session with
/// no clock at all. The pairs are what make either half evidence.
@Suite("The conjugation drill's prompt clock")
struct PromptTimingTests {

    private static func prompt() -> ConjugationPrompt {
        ConjugationPrompt(sourceID: "a", surface: "食べる", dictKana: "たべる", gloss: "eat",
                          verbClass: .ichidan, targetForm: .polite, conjugatedKana: "たべます")
    }

    /// A clock the test moves explicitly. It does NOT advance when read — the sessions consult
    /// `now()` at several points (prompt start, pause, resume, grading) and a self-advancing
    /// clock would make the elapsed time depend on how many times the implementation happened
    /// to look, which is a property of the code rather than of the learner.
    private final class TestClock: @unchecked Sendable {
        private var t: Date
        init(_ start: Date = Date(timeIntervalSince1970: 0)) { t = start }
        func advance(_ seconds: TimeInterval) { t = t.addingTimeInterval(seconds) }
        func read() -> Date { t }
    }

    /// たべます is 4 kana. Hidden: `2.0 + 4 × 0.8 = 5.2 s`, and q=5 needs `ratio <= 1.5`, so the
    /// budget is **7.8 s**. Visible: `0 + 3.2 = 3.2 s`, budget **4.8 s**. Stated here in seconds
    /// because that is the form a learner experiences, and because a test that recomputed the
    /// constants from the config would pass whatever they were — the defect where a check
    /// re-derives its own key and cannot fail.
    private static let hiddenBudget: TimeInterval = 7.8
    private static let visibleBudget: TimeInterval = 4.8

    /// Types the whole answer, having spent `elapsed` seconds on it, and returns the grade the
    /// learner's schedule receives. `pause`/`resume`, when given, bracket a stretch the app
    /// declared not-typing.
    private static func grade(assistance: AssistanceMode, elapsed: TimeInterval,
                              pausedFor: TimeInterval = 0) -> Int {
        let clock = TestClock()
        var config = ConjugationSession.Config()
        config.assistance = assistance
        let session = ConjugationSession(prompts: [prompt()], config: config, now: clock.read)
        var seen: TypingOutcome?
        session.onOutcome = { _, outcome in seen = outcome }
        if pausedFor > 0 {
            session.pauseTyping()
            clock.advance(pausedFor)
            session.resumeTyping()
        }
        clock.advance(elapsed)
        for character in KanaRomanizer.romaji(for: "たべます") { session.input(character) }
        guard let outcome = seen, outcome.completed, outcome.mistakes == 0 else {
            return -1   // the harness did not produce a clean answer; every caller checks
        }
        return ConjugationSRSCard.quality(from: ConjugationOutcome(
            completed: outcome.completed, mistakes: outcome.mistakes,
            usedHint: outcome.usedHint, durationRatio: outcome.durationRatio))
    }

    @Test("a laboured clean answer is graded 4 — and a quick one is still graded 5")
    func timingNowReachesTheGrade() {
        let quick = Self.grade(assistance: .off, elapsed: Self.hiddenBudget - 1)
        let laboured = Self.grade(assistance: .off, elapsed: Self.hiddenBudget + 1)
        // The pair is the point. `laboured == 4` alone would pass on a drill that graded
        // everything 4, which is a different bug in the opposite direction.
        #expect(quick == 5, Comment(rawValue: "an answer inside the budget must still be a 5, "
                + "or the fix has replaced 'always 5' with 'always 4'"))
        #expect(laboured == 4, "an answer over the budget must be a 4 — this is the defect")
    }

    @Test("paused time is not thinking time: the same wall clock grades differently")
    func pausingExcludesTheStretch() {
        // Identical typing, identical wall clock. The only difference is whether the app said
        // the learner had stopped — which is exactly what a pause overlay, a sheet, or the app
        // going to the background says.
        let interrupted = Self.grade(assistance: .off, elapsed: 3, pausedFor: 60)
        let neverPaused = Self.grade(assistance: .off, elapsed: 63)
        #expect(interrupted == 5, Comment(rawValue: "a rider who paused for a minute and then "
                + "answered in three seconds answered in three seconds"))
        #expect(neverPaused == 4, Comment(rawValue: "…and the control must come out the other "
                + "way, or the pause proved nothing: 63 unpaused seconds is over the budget"))
    }

    @Test("the recall allowance is withheld when the answer is on screen")
    func visibleAnswerGetsNoAllowance() {
        // One elapsed time, between the two budgets, so it lands on opposite sides of them.
        let between = (Self.visibleBudget + Self.hiddenBudget) / 2      // 6.3 s
        #expect(Self.grade(assistance: .always, elapsed: between) == 4,
                Comment(rawValue: "with the romaji of the answer on screen there is nothing to "
                        + "recall, so the allowance must not be granted"))
        #expect(Self.grade(assistance: .off, elapsed: between) == 5,
                Comment(rawValue: "…and blind recall in the same time must keep it, or the two "
                        + "cases are not being distinguished at all"))
    }

    @Test("the budgets are the ones documented, to the second")
    func budgetBoundaries() {
        // Half a second either side of the stated boundary. This is what pins the two
        // constants: changing `recallAllowanceSeconds` or `secondsPerKanaBaseline` moves these
        // and the suite says so in seconds a learner would recognise, rather than by restating
        // the constants back to themselves.
        #expect(Self.grade(assistance: .off, elapsed: Self.hiddenBudget - 0.5) == 5)
        #expect(Self.grade(assistance: .off, elapsed: Self.hiddenBudget + 0.5) == 4)
        #expect(Self.grade(assistance: .always, elapsed: Self.visibleBudget - 0.5) == 5)
        #expect(Self.grade(assistance: .always, elapsed: Self.visibleBudget + 0.5) == 4)
    }

    /// The ride had the same defect in a milder form, and it is fixed by the same clock:
    /// `GameSession.durationRatio` was raw wall time, while the ride's own `RunClock` had
    /// stopped for the pause. So a rider who paused mid-word was graded on the pause.
    ///
    /// Observed through the ease factor rather than asserted on the grade, because that is the
    /// thing that reaches the learner: SM-2 here adds 0.10 at q=5 and exactly 0.000 at q=4, so
    /// the ease factor IS the grade.
    @Test("the ride's word clock stops too — a paused word is not a slow word")
    func gameSessionHonoursThePause() throws {
        func easeAfterTyping(pausedFor: TimeInterval, thenSeconds elapsed: TimeInterval) throws -> Double {
            let entry = VocabEntry(id: "w", surface: "食べる", kana: "たべる",
                                   partsOfSpeech: ["v"], jlpt: .n5, meanings: ["en": ["eat"]])
            let clock = TestClock()
            var config = GameSession.Config()
            config.recordsSRS = true
            let session = GameSession(words: [entry], review: ReviewStore(),
                                      config: config, now: clock.read)
            if pausedFor > 0 {
                session.pauseTyping()
                clock.advance(pausedFor)
                session.resumeTyping()
            }
            clock.advance(elapsed)
            for character in KanaRomanizer.romaji(for: "たべる") { session.input(character) }
            return try #require(session.review.card(for: "w"),
                                "GameSession recorded nothing — the harness is broken").easeFactor
        }
        // たべる is 3 kana → baseline 2.4 s → q=5 needs 3.6 s or less.
        let fresh = SRSCard(id: "unused").easeFactor
        let interrupted = try easeAfterTyping(pausedFor: 300, thenSeconds: 2)
        let neverPaused = try easeAfterTyping(pausedFor: 0, thenSeconds: 302)
        #expect(interrupted > fresh, Comment(rawValue: "five minutes of pause followed by two "
                + "seconds of typing is two seconds of typing, and must earn the q=5 increment"))
        #expect(neverPaused == fresh, Comment(rawValue: "…and the control must NOT, or the "
                + "pause is not what made the difference"))
    }

    /// A prompt boundary that happens **while the app is away**, which is the case that made
    /// `PromptClock` a type rather than two `RunClock`s.
    ///
    /// The first draft of this test paused AFTER the boundary rather than across it, so it
    /// asserted the right sentence about the wrong moment and survived a mutation that deleted
    /// the clause entirely — a green assertion that no defect could break. `skip()` is what
    /// makes the boundary reachable while paused: `PracticeView` binds it to Enter and has no
    /// pause overlay, only a `scenePhase` signal. `PromptClockTests` holds the same property at
    /// the unit level, because this route is narrow and a narrow route is easy to lose.
    @Test("a prompt that begins while the app is away does not start counting")
    func pauseSurvivesThePromptBoundary() {
        let clock = TestClock()
        var config = ConjugationSession.Config()
        config.assistance = .off
        func verb(_ id: String, _ surface: String, _ kana: String, _ answer: String) -> ConjugationPrompt {
            ConjugationPrompt(sourceID: id, surface: surface, dictKana: kana, gloss: "g",
                              verbClass: .godanM, targetForm: .polite, conjugatedKana: answer)
        }
        let three = [Self.prompt(),
                     verb("b", "飲む", "のむ", "のみます"),
                     verb("c", "読む", "よむ", "よみます")]
        let session = ConjugationSession(prompts: three, config: config, now: clock.read)
        var grades: [Int] = []
        session.onOutcome = { (_: ConjugationPrompt, outcome: TypingOutcome) in
            grades.append(ConjugationSRSCard.quality(from: ConjugationOutcome(
                completed: outcome.completed, mistakes: outcome.mistakes,
                usedHint: outcome.usedHint, durationRatio: outcome.durationRatio)))
        }
        for character in KanaRomanizer.romaji(for: "たべます") { session.input(character) }
        session.pauseTyping()                    // the app goes away…
        session.skip()                           // …and the prompt boundary happens anyway
        clock.advance(600)                       // ten minutes elsewhere
        #expect(session.isTypingPaused, Comment(rawValue: "the session must still consider "
                + "itself paused across the prompt boundary"))
        session.resumeTyping()
        clock.advance(1)
        for character in KanaRomanizer.romaji(for: "よみます") { session.input(character) }
        #expect(grades == [5, 0, 5], Comment(rawValue: "the third answer took one second of "
                + "ridden time; ten minutes of absence that began before its prompt even loaded "
                + "is not the learner hesitating. (The 0 is the skipped prompt.)"))
    }
}
