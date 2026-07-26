import Testing
import Foundation
@testable import DiagnosticsKit
@testable import RomajiKana

/// These do NOT hand-build `MistakeEvent`s. They drive a real `KanaInputMatcher` with real
/// wrong input and classify whatever it actually produces — because the two previous attempts
/// at this taxonomy both described engine behaviour that did not exist. A test built from my
/// idea of what the matcher does would have passed for both of them.
@Suite("TypingDiagnostics — classified from what the engine really refuses")
struct TypingDiagnosticsTests {

    /// Types `romaji` at `target` and returns the event for the first refusal, exactly as
    /// `GameSession` would record it.
    private func firstMistake(typing romaji: String, at target: String,
                              entryID: String? = nil, order: Int = 0) -> MistakeEvent? {
        var matcher = KanaInputMatcher(target: target)
        for character in romaji {
            let before = matcher.typedRomaji
            let expected = matcher.expectedNextCharacters
            let index = matcher.completedKanaCount
            if matcher.input(character) == .rejected {
                return MistakeEvent(targetKana: target, entryID: entryID,
                                    acceptedRomaji: before, rejected: character,
                                    expectedNext: expected, kanaIndex: index, order: order)
            }
        }
        return nil
    }

    private func pattern(typing romaji: String, at target: String) -> TypingPattern? {
        firstMistake(typing: romaji, at: target).map(TypingDiagnostics.classify)
    }

    @Test("は / へ / を typed the way they sound")
    func particles() {
        #expect(pattern(typing: "konnichiwa", at: "こんにちは") == .particleSpelling)
        #expect(pattern(typing: "wa", at: "は") == .particleSpelling)
        #expect(pattern(typing: "o", at: "を") == .particleSpelling)
        #expect(pattern(typing: "e", at: "へ") == .particleSpelling)
    }

    @Test("a dropped sokuon")
    func sokuon() {
        #expect(pattern(typing: "ite", at: "いって") == .sokuon)
        #expect(pattern(typing: "kite", at: "きって") == .sokuon)
    }

    @Test("a small ya typed full-size")
    func smallYa() {
        #expect(pattern(typing: "kiyaku", at: "きゃく") == .smallYa)
        #expect(pattern(typing: "shiyoubi", at: "しょうび") == .smallYa)
    }

    @Test("Hepburn m before b or p")
    func hepburnM() {
        #expect(pattern(typing: "shimbun", at: "しんぶん") == .hepburnM)
    }

    @Test("input the engine ACCEPTS produces no event at all to classify")
    func acceptedInputIsNotDiagnosed() {
        // The failure both earlier drafts made, as a test: these are valid, so there is no
        // refusal, so there is nothing for the coach to say.
        for (input, target) in [("si", "し"), ("ti", "ち"), ("tu", "つ"),
                                ("renai", "れんあい"), ("kinyoubi", "きんようび"),
                                ("sinbun", "しんぶん")] {
            #expect(firstMistake(typing: input, at: target) == nil,
                    "‘\(input)’ is accepted for ‘\(target)’ and must never be diagnosed")
        }
    }

    @Test("a key that is simply wrong is 'unknown', not forced into a pattern")
    func unknownStaysUnknown() {
        // A coach that files everything under a known label will confidently misdiagnose.
        #expect(pattern(typing: "z", at: "ねこ") == .unknown)
    }

    // MARK: recurrence

    private func trace(_ attempts: [(String, String)]) -> MistakeTrace {
        var t = MistakeTrace()
        for (i, a) in attempts.enumerated() {
            if let e = firstMistake(typing: a.0, at: a.1, order: i) { t.record(e) }
        }
        return t
    }

    @Test("one slip is not a pattern; the same slip on two words is")
    func recurrence() {
        let once = TypingDiagnostics.diagnose(trace([("ite", "いって")]))
        #expect(once.first?.isRecurring == false)
        #expect(TypingDiagnostics.headline(trace([("ite", "いって")])) == nil,
                "a single mistake was promoted to a diagnosis")

        let twice = trace([("ite", "いって"), ("kite", "きって")])
        #expect(TypingDiagnostics.headline(twice)?.pattern == .sokuon)
        #expect(TypingDiagnostics.headline(twice)?.distinctWords == 2)
    }

    @Test("the same word twice is still one word")
    func sameWordDoesNotCount() {
        // Two attempts at いって is one learner hitting the same wall twice, not evidence
        // that the pattern generalises.
        let t = trace([("ite", "いって"), ("ite", "いって"), ("ite", "いって")])
        #expect(t.count == 3)
        #expect(TypingDiagnostics.diagnose(t).first?.distinctWords == 1)
        #expect(TypingDiagnostics.headline(t) == nil)
    }

    @Test("the headline is the most widespread pattern, and never 'unknown'")
    func headlinePicksBreadth() {
        let t = trace([
            ("wa", "は"), ("konnichiwa", "こんにちは"), ("o", "を"),   // 3 distinct words
            ("ite", "いって"), ("kite", "きって"),                     // 2 distinct words
            ("z", "ねこ"), ("z", "いぬ"),                              // 2 distinct, unknown
        ])
        #expect(TypingDiagnostics.headline(t)?.pattern == .particleSpelling)
        // …and unknown is still REPORTED, just never as the headline.
        #expect(TypingDiagnostics.diagnose(t).contains { $0.pattern == .unknown })
    }

    @Test("'unknown' is never the headline, even when it is the most widespread")
    func unknownNeverLeads() {
        // Mutation testing found this hole: the previous test had unknown recurring on two
        // words while a real pattern recurred on three, so removing the `!= .unknown` filter
        // changed nothing and no test noticed. Here unknown is the WIDEST pattern, and the
        // headline must still be the one the app can actually explain — or the coach opens
        // with "you made mistakes we have no name for".
        let t = trace([
            ("z", "ねこ"), ("z", "いぬ"), ("z", "とり"), ("z", "うま"),   // 4 distinct, unknown
            ("ite", "いって"), ("kite", "きって"),                        // 2 distinct, sokuon
        ])
        #expect(TypingDiagnostics.diagnose(t).first?.pattern == .unknown, "setup: unknown is widest")
        #expect(TypingDiagnostics.headline(t)?.pattern == .sokuon)
    }

    @Test("when the ONLY recurring thing is unexplainable, the coach stays quiet")
    func silentWhenOnlyUnknown() {
        let t = trace([("z", "ねこ"), ("z", "いぬ"), ("z", "とり")])
        #expect(!TypingDiagnostics.diagnose(t).isEmpty)
        #expect(TypingDiagnostics.headline(t) == nil, "said something it could not explain")
    }

    @Test("an empty run says nothing")
    func silentWhenClean() {
        #expect(TypingDiagnostics.diagnose(MistakeTrace()).isEmpty)
        #expect(TypingDiagnostics.headline(MistakeTrace()) == nil)
    }

    @Test("the trace is bounded and says so")
    func boundedTrace() {
        // Holding a key down must not turn into an unbounded log.
        var t = MistakeTrace()
        let e = firstMistake(typing: "z", at: "ねこ")!
        for _ in 0..<(MistakeTrace.capacity + 50) { t.record(e) }
        #expect(t.count == MistakeTrace.capacity)
        #expect(t.dropped == 50)
    }
}
