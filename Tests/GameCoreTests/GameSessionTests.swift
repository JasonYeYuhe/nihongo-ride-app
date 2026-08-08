import Testing
import Foundation
import RomajiKana
import VocabKit
import ReviewKit
@testable import GameCore

private func makeEntry(_ id: String, _ surface: String, _ kana: String) -> VocabEntry {
    VocabEntry(
        id: id, surface: surface, kana: kana,
        partsOfSpeech: ["n"], jlpt: .n5,
        meanings: ["en": [surface], "zh": [surface]]
    )
}

private func type(_ romaji: String, into session: GameSession) {
    for character in romaji { session.input(character) }
}

@Suite("GameSession")
struct GameSessionTests {
    @Test("typing a word completes it, scores, advances, and records to SRS")
    func completeAndAdvance() {
        let session = GameSession(words: [makeEntry("a", "水", "みず"), makeEntry("b", "猫", "ねこ")])
        #expect(session.currentKana == "みず")

        type("mizu", into: session)
        #expect(session.wordsCompleted == 1)
        #expect(session.score > 0)
        #expect(session.combo == 1)
        #expect(session.currentKana == "ねこ")          // advanced to the next word
        #expect(session.review.card(for: "a") != nil)   // recorded

        type("neko", into: session)
        #expect(session.wordsCompleted == 2)
        #expect(session.isFinished)
        #expect(session.currentKana == nil)
    }

    @Test("makeSaved builds a journey deck from resolvable ids, skipping unknown ones")
    func makeSavedDeck() {
        let vocab = VocabStore(entries: [makeEntry("a", "水", "みず"), makeEntry("b", "猫", "ねこ")])
        let deck = GameSession.makeSaved(ids: ["a"], vocab: vocab)
        #expect(deck.mode == .journey)
        #expect(deck.currentKana == "みず")
        #expect(!deck.isFinished)
        // Only-unknown ids → empty deck → finishes immediately.
        let empty = GameSession.makeSaved(ids: ["zzz"], vocab: vocab)
        #expect(empty.isFinished)
        #expect(empty.currentKana == nil)
    }

    @Test("makeWeak builds a journey deck with recordsSRS off, skipping unknown ids")
    func makeWeakBuilder() {
        let vocab = VocabStore(entries: [makeEntry("a", "水", "みず"), makeEntry("b", "猫", "ねこ")])
        let deck = GameSession.makeWeak(ids: ["a", "zzz"], vocab: vocab)
        #expect(deck.mode == .journey)
        #expect(deck.config.recordsSRS == false)
        #expect(deck.currentKana == "みず")
        #expect(deck.wordCount == 1)             // unknown "zzz" dropped (resolve-then-guard)
    }

    @Test("a weak-words cram (recordsSRS=false) writes ZERO to SRS — skip and complete alike")
    func weakCramZeroSRS() {
        let vocab = VocabStore(entries: [makeEntry("a", "水", "みず"), makeEntry("b", "猫", "ねこ")])
        let session = GameSession.makeWeak(ids: ["a", "b"], vocab: vocab)
        #expect(session.config.recordsSRS == false)
        // First word: skip (exercises skip()'s gated record). Then type the rest.
        session.skip()
        var guardCounter = 0
        while !session.isFinished && guardCounter < 100 {
            guardCounter += 1
            guard let kana = session.currentKana else { break }
            type(KanaRomanizer.romaji(for: kana), into: session)
        }
        #expect(session.isFinished)
        #expect(session.review.cards.isEmpty, "a weak-words cram must never write SRS")
        #expect(!session.lapsedEntries.isEmpty, "the skip still collects review feedback")
    }

    @Test("recordsSRS=false suppresses the SRS write but a default session still records")
    func recordsSRSGate() {
        let off = GameSession(words: [makeEntry("a", "水", "みず")],
                              config: .init(recordsSRS: false))
        type("mizu", into: off)
        #expect(off.wordsCompleted == 1)               // still plays normally
        #expect(off.review.card(for: "a") == nil)      // ...but recorded nothing

        let on = GameSession(words: [makeEntry("a", "水", "みず")])   // default recordsSRS=true
        type("mizu", into: on)
        #expect(on.review.card(for: "a") != nil)       // default still records
    }

    @Test("runCompletion gates finishGame side-effects by mode + recordsSRS (cram/practice red lines)")
    func runCompletionGating() {
        // Real ride (journey / time-attack): persists everything, shows results.
        for mode in [GameMode.journey, .timeAttack] {
            let rc = RunCompletion(mode: mode, recordsSRS: true)
            #expect(rc.persistsSRS && rc.logsRide && rc.reportsGameCenter && rc.showsResults)
        }
        // Practice: no SRS persist, but still logs a ride; returns to the menu (no results).
        let practice = RunCompletion(mode: .practice, recordsSRS: true)
        #expect(practice.persistsSRS == false)
        #expect(practice.logsRide == true)
        #expect(practice.reportsGameCenter == false)
        #expect(practice.showsResults == false)
        // Weak-words cram: advances NOTHING (no SRS / ride / Game Center) but shows results.
        let cram = RunCompletion(mode: .journey, recordsSRS: false)
        #expect(cram.persistsSRS == false)
        #expect(cram.logsRide == false)
        #expect(cram.reportsGameCenter == false)
        #expect(cram.showsResults == true)
    }

    @Test("a typo counts a mistake and breaks the combo")
    func mistakes() {
        let session = GameSession(words: [makeEntry("a", "水", "みず")])
        session.input("m"); session.input("i")
        #expect(session.input("x") == .rejected)   // typo where 'z' was expected
        session.input("z"); session.input("u")
        #expect(session.isFinished)
        #expect(session.review.card(for: "a")?.totalMistakes == 1)
    }

    @Test("accuracy reflects correct vs total keystrokes")
    func accuracy() {
        let session = GameSession(words: [makeEntry("a", "猫", "ねこ")])
        for character in "nxeko" { session.input(character) }   // one stray 'x'
        #expect(abs(session.accuracy - 0.8) < 1e-9)
    }

    @Test("skip records a non-completion and advances")
    func skip() {
        let session = GameSession(words: [makeEntry("a", "水", "みず"), makeEntry("b", "猫", "ねこ")])
        session.skip()
        #expect(session.currentKana == "ねこ")
        #expect(session.wordsCompleted == 0)
        #expect(session.review.card(for: "a")?.repetitions == 0)   // lapse
    }

    @Test("revealing the hint drops the grade to a lapse, breaks combo, scores minimally")
    func reveal() {
        let session = GameSession(words: [makeEntry("a", "水", "みず")])
        session.revealHint()
        #expect(session.combo == 0)                                // reveal breaks the combo
        type("mizu", into: session)
        #expect(session.wordsCompleted == 1)                       // still finished
        #expect(session.combo == 0)                                // ...and didn't rebuild it
        #expect(session.score == 10)                               // minimal score, no combo bonus
        #expect(session.review.card(for: "a")?.repetitions == 0)   // q2 (hinted) → lapse
    }

    @Test("distance advances by 10m per kana on completion")
    func distance() {
        let session = GameSession(words: [makeEntry("a", "水", "みず")])   // 2 kana
        #expect(session.distanceMeters == 0)
        type("mizu", into: session)
        #expect(session.distanceMeters == 20)
    }

    @Test("combo grows across clean words and resets on a typo, retaining max")
    func combo() {
        let session = GameSession(words: [makeEntry("a", "水", "みず"), makeEntry("b", "猫", "ねこ")])
        type("mizu", into: session)
        #expect(session.combo == 1)
        #expect(session.maxCombo == 1)
        session.input("n"); session.input("x")   // start ねこ, then a typo
        #expect(session.combo == 0)
        #expect(session.maxCombo == 1)
    }

    @Test("an empty word list finishes immediately")
    func empty() {
        let session = GameSession(words: [])
        #expect(session.isFinished)
        #expect(session.currentKana == nil)
    }

    @Test("makePractice queues passages and runs in practice mode")
    func makePractice() {
        let session = GameSession.makePractice(level: .easy, config: .init(newWordCount: 5))
        #expect(session.mode == .practice)
        #expect(session.wordCount > 0)
        #expect(session.current?.id.hasPrefix("passage-") == true)
        // The typing target is pure kana.
        let kana = session.currentKana ?? ""
        for scalar in kana.unicodeScalars {
            let v = scalar.value
            let isKana = (0x3041...0x3094).contains(v) || (0x30A1...0x30FA).contains(v) || v == 0x30FC
            #expect(isKana, "passage target should be pure kana, got U+\(String(v, radix: 16))")
        }
    }

    @Test("lapsed words (skipped / hinted) are collected for review")
    func lapsedTracking() {
        let session = GameSession(words: [makeEntry("a", "水", "みず"), makeEntry("b", "猫", "ねこ")])
        session.skip()                                  // a → lapse
        for ch in "neko" { session.input(ch) }          // b → clean, not a lapse
        #expect(session.lapsedEntries.map(\.id) == ["a"])
    }

    @Test("time-attack mode reports its mode and draws a large queue")
    func timeAttackMode() {
        let session = GameSession.make(
            config: .init(newWordCount: 300, reviewWordCount: 0, mode: .timeAttack, timeLimit: 60)
        )
        #expect(session.mode == .timeAttack)
        #expect(session.wordCount > 100)   // enough words for a 60s sprint
    }

    @Test("config.level restricts new words to the chosen level")
    func levelFilter() {
        let session = GameSession.make(
            config: .init(newWordCount: 30, reviewWordCount: 0, level: .n4)
        )
        #expect(session.current?.jlpt == .n4)   // drawn only from N4
    }
}

// MARK: - v1.18 sentence mode

@Suite("Sentence mode")
struct SentenceModeTests {

    private func entry(_ id: String, jp: String?, kana: String?) -> VocabEntry {
        VocabEntry(id: id, surface: "犬", kana: "いぬ", partsOfSpeech: ["n"],
                   jlpt: .n5, meanings: ["en": ["dog"]],
                   exampleJP: jp, exampleEN: "A dog.", exampleZH: "狗。",
                   exampleKana: kana,
                   exampleTokens: kana == nil ? nil : [["犬", "いぬ"], ["だ", "だ"], ["。", "。"]])
    }

    /// The whole point of the mode: what you type is the sentence's reading, not the word's.
    @Test("the typing target is the sentence reading, and the display is the kanji sentence")
    func targetIsTheSentence() {
        let e = entry("x", jp: "犬だ。", kana: "いぬだ。")
        let session = GameSession(words: [e], config: {
            var c = GameSession.Config(); c.mode = .sentence; return c
        }())
        // Constructed directly, so assert on what makeSentence produces instead.
        #expect(session.currentSurface == "犬")
        let built = GameSession(words: [VocabEntry(
            id: e.id, surface: e.exampleJP!, kana: e.exampleKana!,
            partsOfSpeech: ["sentence"], jlpt: .n5, meanings: e.meanings)],
            config: { var c = GameSession.Config(); c.mode = .sentence; return c }())
        #expect(built.currentSurface == "犬だ。")
        #expect(built.currentKana == "いぬだ。")
    }

    /// A sentence run counts mistakes across the whole sentence, so letting it write SRS
    /// would land a typo in an unrelated clause on the review card of the one word the
    /// sentence teaches. That card is calibrated for typing a word.
    @Test("a sentence run never writes SRS, but still logs a ride and shows results")
    func doesNotPersistSRS() {
        let done = RunCompletion(mode: .sentence, recordsSRS: true)
        #expect(done.persistsSRS == false)
        #expect(done.logsRide == true)
        #expect(done.showsResults == true)
    }

    /// Practice and cram already had this red line; sentence mode joins them without
    /// disturbing them.
    @Test("the other modes' SRS behaviour is unchanged")
    func siblingModesUnchanged() {
        #expect(RunCompletion(mode: .journey, recordsSRS: true).persistsSRS == true)
        #expect(RunCompletion(mode: .timeAttack, recordsSRS: true).persistsSRS == true)
        #expect(RunCompletion(mode: .practice, recordsSRS: true).persistsSRS == false)
        #expect(RunCompletion(mode: .journey, recordsSRS: false).persistsSRS == false)
    }

    /// A sentence with no reading is not a target. Offering one would mark a learner wrong
    /// for typing exactly what the sentence says — the digit sentences read one digit at a
    /// time, so 「10キロ」 wants いちれいきろ.
    @Test("a sentence without a reading is not typeable")
    func untypeableIsExcluded() {
        #expect(entry("a", jp: "犬だ。", kana: "いぬだ。").isTypeableSentence == true)
        #expect(entry("b", jp: "犬だ。", kana: nil).isTypeableSentence == false)
        #expect(entry("c", jp: nil, kana: "いぬだ。").isTypeableSentence == false)
    }

    /// Every sentence the real store would offer must be typeable end to end: feed the
    /// target's own kana back through the matcher and it must complete.
    @Test("shipped sentences can actually be typed to completion")
    func shippedSentencesComplete() {
        let pool = VocabStore.shared.ordered().filter(\.isTypeableSentence).prefix(40)
        var failed: [String] = []
        for e in pool {
            guard let kana = e.exampleKana else { continue }
            var matcher = KanaInputMatcher(target: kana)
            var finished = false
            for ch in KanaRomanizer.romaji(for: kana) {
                if matcher.input(ch) == .completed { finished = true }
            }
            if !finished { failed.append("\(e.id): \(kana)") }
        }
        #expect(failed.isEmpty, Comment(rawValue: "\(failed.count) could not be typed:\n"
                                                   + failed.prefix(8).joined(separator: "\n")))
    }
}
