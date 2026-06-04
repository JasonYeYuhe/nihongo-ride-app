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
