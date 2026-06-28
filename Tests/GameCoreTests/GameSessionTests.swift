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
