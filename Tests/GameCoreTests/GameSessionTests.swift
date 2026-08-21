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

    // MARK: v1.21 §B — sentence runs that follow what the learner is studying

    /// Shaped like the shipped data: `exJP` keeps its 。 and `exKana` does not, because the
    /// typing target cannot contain punctuation a romaji keyboard has no way to produce.
    /// A fixture that punctuated the kana would make every "type it to completion" assertion
    /// vacuously pass — the word would simply never finish.
    private func sentenceEntry(_ id: String, jp: String?, kana: String?,
                               tokens: [[String]]? = nil) -> VocabEntry {
        VocabEntry(id: id, surface: "犬", kana: "いぬ", partsOfSpeech: ["n"],
                   jlpt: .n5, meanings: ["en": ["dog"]],
                   exampleJP: jp, exampleEN: "A dog.", exampleZH: "狗。",
                   exampleKana: kana, exampleTokens: kana == nil ? nil : tokens)
    }

    private var pool: VocabStore {
        VocabStore(entries: [
            sentenceEntry("has-1", jp: "犬だ。", kana: "いぬだ",
                          tokens: [["犬", "いぬ"], ["だ", "だ"], ["。", "。"]]),
            sentenceEntry("has-2", jp: "猫だ。", kana: "ねこだ",
                          tokens: [["猫", "ねこ"], ["だ", "だ"], ["。", "。"]]),
            sentenceEntry("no-kana", jp: "10キロ。", kana: nil),
            sentenceEntry("no-sentence", jp: nil, kana: nil),
        ])
    }

    private func sentenceConfig(_ n: Int = 5) -> GameSession.Config {
        var c = GameSession.Config(); c.newWordCount = n; return c
    }

    /// A saved list is a list of WORDS. Five percent of the corpus has no sentence, and an
    /// id synced from a newer device may not resolve here at all — so the run is built from
    /// the intersection, and the count the menu shows must be that same intersection.
    @Test("a list-sourced run keeps only the ids that resolve to a typeable sentence")
    func listSourcedPool() {
        let ids = ["has-1", "missing", "no-kana", "no-sentence", "has-2", "has-1"]
        let kept = GameSession.sentenceEntries(ids: ids, vocab: pool).map(\.id)
        #expect(kept == ["has-1", "has-2"])   // deduped, and in the list's own order

        let session = GameSession.makeSentence(ids: ids, vocab: pool, config: sentenceConfig())
        #expect(session.mode == .sentence)
        #expect(session.wordCount == 2)
        #expect(session.wordList.allSatisfy { $0.partsOfSpeech == ["sentence"] })
    }

    /// The regression this guards is silent padding. `makeSentence` falls back to the whole
    /// corpus when a level has nothing, which is right for a content gap and wrong here: a
    /// learner who asked for their list's sentences and got two of someone else's has no way
    /// to tell which two. A short run is honest; a padded one lies.
    @Test("a list-sourced run is never padded from the corpus")
    func listSourcedNeverPads() {
        let one = GameSession.makeSentence(ids: ["has-1"], vocab: pool, config: sentenceConfig())
        #expect(one.wordCount == 1)

        let none = GameSession.makeSentence(ids: ["no-kana", "missing"], vocab: pool,
                                            config: sentenceConfig())
        #expect(none.wordCount == 0)
        // Empty at construction, so the caller's build-then-guard keeps the learner on the
        // menu instead of flashing a results screen for a run with no keystrokes (v1.15 §D).
        #expect(none.isFinished == true)

        // …while the level-scoped builder still has its fallback, deliberately.
        let level = GameSession.makeSentence(vocab: pool, config: sentenceConfig())
        #expect(level.wordCount == 2)
    }

    /// Due-scoped runs ask the SRS store for cards that can carry a sentence, rather than
    /// asking for five and dropping the ones that cannot — the difference between a run of
    /// five and a run of one when the due stack is mostly sentence-less words.
    @Test("a due-sourced run draws only from due cards that have a sentence")
    func dueSourcedPool() {
        var review = ReviewStore()
        let now = Date()
        for id in ["has-1", "no-kana", "no-sentence", "has-2"] {
            review.record(entryID: id, outcome: TypingOutcome(completed: false, mistakes: 3), on: now)
        }
        let tomorrow = now.addingTimeInterval(24 * 3600)
        #expect(GameSession.dueSentenceCount(review: review, on: tomorrow, vocab: pool) == 2)

        let session = GameSession.makeSentence(due: review, on: tomorrow, vocab: pool,
                                               config: sentenceConfig())
        #expect(session.mode == .sentence)
        #expect(session.wordCount == 2)
        #expect(Set(session.wordList.map(\.id)) == ["has-1", "has-2"])
    }

    /// Nothing due is not an error and must not become a hollow run.
    @Test("a due-sourced run with nothing due is empty, not padded")
    func dueSourcedEmpty() {
        let session = GameSession.makeSentence(due: ReviewStore(), vocab: pool,
                                               config: sentenceConfig())
        #expect(session.wordCount == 0)
        #expect(session.isFinished == true)
    }

    /// The structural half of the sentence-mode SRS red line. `RunCompletion` refuses the
    /// merge downstream, but a due-sourced run is the first sentence run built FROM a review
    /// store, so it is the first one that could plausibly be handed that store to write back
    /// into. It is not, and this locks that in: type a sentence to completion and the store
    /// the run was sourced from is untouched.
    @Test("a due-sourced run cannot write back into the store it was drawn from")
    func dueSourcedWritesNothingBack() {
        var review = ReviewStore()
        let now = Date()
        review.record(entryID: "has-1", outcome: TypingOutcome(completed: false, mistakes: 3), on: now)
        let before = review.card(for: "has-1")

        let session = GameSession.makeSentence(due: review, on: now.addingTimeInterval(24 * 3600),
                                               vocab: pool, config: sentenceConfig())
        for ch in KanaRomanizer.romaji(for: session.currentKana ?? "") { session.input(ch) }

        #expect(review.card(for: "has-1") == before)
        #expect(RunCompletion(mode: session.mode, recordsSRS: session.config.recordsSRS)
                    .persistsSRS == false)
    }

    // MARK: v1.21 §A — dictation

    /// Dictation inherits sentence mode's answer to the SRS question, and for a stronger
    /// reason: a listening failure charged to one word's review card is even further from
    /// what that card measures than a typing failure across a whole sentence.
    @Test("a dictation run never writes SRS, but still logs a ride and shows results")
    func dictationDoesNotPersistSRS() {
        let done = RunCompletion(mode: .dictation, recordsSRS: true)
        #expect(done.persistsSRS == false)
        #expect(done.logsRide == true)
        #expect(done.showsResults == true)
        // …and the modes that DO persist still do.
        #expect(RunCompletion(mode: .journey, recordsSRS: true).persistsSRS == true)
        #expect(RunCompletion(mode: .timeAttack, recordsSRS: true).persistsSRS == true)
    }

    /// The whole honesty of the mode rests on this filter. A sentence the synthesizer was
    /// measured to read differently from its own `exKana` would play one thing and grade
    /// another, so it must never be drawn — while staying perfectly usable in sentence mode,
    /// where the reading is shown rather than spoken.
    @Test("dictation never draws a sentence whose audio was measured to disagree with it")
    func dictationExcludesMismatches() {
        let all = GameSession.makeDictation(vocab: pool, excluding: [], config: sentenceConfig())
        #expect(Set(all.wordList.map(\.id)) == ["has-1", "has-2"])

        let filtered = GameSession.makeDictation(vocab: pool, excluding: ["has-1"],
                                                 config: sentenceConfig())
        #expect(Set(filtered.wordList.map(\.id)) == ["has-2"])
        #expect(filtered.mode == .dictation)

        // Excluding everything leaves an empty run, not a run padded with the excluded ones.
        let none = GameSession.makeDictation(vocab: pool, excluding: ["has-1", "has-2"],
                                             config: sentenceConfig())
        #expect(none.wordCount == 0)
        #expect(none.isFinished == true)

        // Sentence mode is untouched by the dictation exclusions — the sentence is still
        // perfectly good to READ, and withholding it there would be a silent content loss.
        let sentence = GameSession.makeSentence(vocab: pool, config: sentenceConfig())
        #expect(Set(sentence.wordList.map(\.id)) == ["has-1", "has-2"])
    }

    /// The typing target is the same one sentence mode uses. What changes is that nothing
    /// on screen shows it — but the card the engine hands the view still carries the kanji
    /// sentence, because the reveal needs it.
    @Test("a dictation card carries the sentence to be typed and the kanji to reveal")
    func dictationCardShape() {
        let session = GameSession.makeDictation(vocab: pool, excluding: ["has-2"],
                                                config: sentenceConfig())
        #expect(session.currentKana == "いぬだ")
        #expect(session.currentExampleJP == "犬だ。")
        #expect(session.currentExampleTokens?.isEmpty == false)
    }

    /// Replays are counted but never priced. If hearing a sentence again cost score or
    /// combo, the cheapest strategy would be to guess rather than listen — the opposite of
    /// what the mode is for. The count exists so the results can say what the score cannot.
    @Test("replays are counted, reset per sentence, and never affect the score")
    func replaysAreCountedNotCharged() {
        let session = GameSession.makeDictation(vocab: pool, excluding: [], config: sentenceConfig())
        session.noteReplay()
        session.noteReplay()
        #expect(session.replays == 2)
        #expect(session.currentReplays == 2)

        let scoreBefore = session.score
        let comboBefore = session.combo
        session.noteReplay()
        #expect(session.score == scoreBefore)
        #expect(session.combo == comboBefore)

        // Finishing a sentence carries the run total forward and restarts the per-card count.
        for ch in KanaRomanizer.romaji(for: session.currentKana ?? "") { session.input(ch) }
        #expect(session.replays == 3)
        #expect(session.currentReplays == 0)
    }

    // MARK: v1.22 §A — dictation follows the learner too

    /// Two filters stack and the second is invisible from the first: a word can have a
    /// perfectly good sentence and still be unusable for dictation. The count the menu shows
    /// has to be the second number, not the first, or it promises a run it cannot give.
    @Test("a list-sourced dictation pool drops both the sentence-less and the withheld")
    func dictationFromListStacksBothFilters() {
        let ids = ["has-1", "has-2", "no-kana", "missing"]
        #expect(GameSession.sentenceEntries(ids: ids, vocab: pool).map(\.id) == ["has-1", "has-2"])
        #expect(GameSession.dictationEntries(ids: ids, vocab: pool, excluding: ["has-2"])
                    .map(\.id) == ["has-1"])

        let session = GameSession.makeDictation(ids: ids, vocab: pool, excluding: ["has-2"],
                                                config: sentenceConfig())
        #expect(session.mode == .dictation)
        #expect(session.wordCount == 1)

        // …and it is never padded back up to the run size from elsewhere.
        let none = GameSession.makeDictation(ids: ids, vocab: pool,
                                             excluding: ["has-1", "has-2"],
                                             config: sentenceConfig())
        #expect(none.wordCount == 0)
        #expect(none.isFinished == true)
    }

    /// The due query has to apply BOTH filters itself rather than asking for five cards and
    /// discarding the ones it cannot use — the difference between a run of two and a run of
    /// one when half the due stack is withheld.
    @Test("a due-sourced dictation run asks only for cards it can actually play")
    func dictationFromDueFiltersInTheQuery() {
        var review = ReviewStore()
        let now = Date()
        for id in ["has-1", "has-2", "no-kana", "no-sentence"] {
            review.record(entryID: id, outcome: TypingOutcome(completed: false, mistakes: 3), on: now)
        }
        let tomorrow = now.addingTimeInterval(24 * 3600)

        #expect(GameSession.dueSentenceCount(review: review, on: tomorrow, vocab: pool) == 2)
        #expect(GameSession.dueDictationCount(review: review, on: tomorrow, vocab: pool,
                                              excluding: ["has-2"]) == 1)

        let session = GameSession.makeDictation(due: review, on: tomorrow, vocab: pool,
                                                excluding: ["has-2"], config: sentenceConfig())
        #expect(session.wordCount == 1)
        #expect(session.wordList.first?.id == "has-1")
        #expect(session.mode == .dictation)
    }

    /// Same red line as every other sentence run: the store it was drawn from is not the
    /// store it can write to. Dictation grades a whole heard sentence; that must not land
    /// on the review card of the one word it teaches.
    @Test("a due-sourced dictation run writes nothing back into the store it came from")
    func dictationFromDueWritesNothingBack() {
        var review = ReviewStore()
        let now = Date()
        review.record(entryID: "has-1", outcome: TypingOutcome(completed: false, mistakes: 3), on: now)
        let before = review.card(for: "has-1")

        let session = GameSession.makeDictation(due: review, on: now.addingTimeInterval(24 * 3600),
                                                vocab: pool, excluding: [], config: sentenceConfig())
        for ch in KanaRomanizer.romaji(for: session.currentKana ?? "") { session.input(ch) }

        #expect(review.card(for: "has-1") == before)
        #expect(RunCompletion(mode: session.mode, recordsSRS: session.config.recordsSRS)
                    .persistsSRS == false)
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

@Suite("Furigana — v1.18")
struct FuriganaTests {

    /// The red line: in sentence mode the example IS the typing target, so ruby over it would
    /// hand the learner the answer. GameView gates on `session.mode != .sentence`; this
    /// asserts the mode is reported truthfully so that gate can work.
    @Test("sentence mode reports its mode, so the view can suppress ruby")
    func sentenceModeIsVisible() {
        var config = GameSession.Config()
        config.mode = .sentence
        let session = GameSession(
            words: [VocabEntry(id: "s", surface: "犬だ。", kana: "いぬだ",
                               partsOfSpeech: ["sentence"], jlpt: .n5, meanings: ["en": ["dog"]])],
            config: config)
        #expect(session.mode == .sentence)

        var journey = GameSession.Config()
        journey.mode = .journey
        let other = GameSession(
            words: [VocabEntry(id: "w", surface: "犬", kana: "いぬ",
                               partsOfSpeech: ["n"], jlpt: .n5, meanings: ["en": ["dog"]])],
            config: journey)
        #expect(other.mode == .journey)
    }

    /// Tokens reach the view or there is nothing to render ruby from.
    @Test("the session exposes the example's furigana tokens")
    func tokensReachTheView() {
        let entry = VocabEntry(id: "e", surface: "犬", kana: "いぬ", partsOfSpeech: ["n"],
                               jlpt: .n5, meanings: ["en": ["dog"]],
                               exampleJP: "犬だ。", exampleEN: "A dog.",
                               exampleKana: "いぬだ",
                               exampleTokens: [["犬", "いぬ"], ["だ", "だ"], ["。", "。"]])
        let session = GameSession(words: [entry], config: GameSession.Config())
        #expect(session.currentExampleTokens?.count == 3)
        #expect(session.currentExampleTokens?.first == ["犬", "いぬ"])
    }
}

// MARK: - The stumbled-word list, driven through a real run

/// Everything else about `StumbledWords` is tested against hand-built traces, which proves the
/// arithmetic and proves nothing about the wiring. A `MistakeEvent` carries only what the
/// session puts in it, and the attribution needs two fields to survive the trip: `entryID`, and
/// a `targetKana` that IS the sentence's reading. A sentence run rebuilds its items with
/// `kana: exampleKana`, so both hold — but that is a fact about `sentenceSession`, not a law,
/// and nothing else in the suite would notice if it changed. These play a run instead.
@Suite("Stumbled words, end to end")
struct StumbledWordsRunTests {

    /// Types a session for real, refusing twice at kana index `mistypeAt`.
    ///
    /// Correct keys come from `expectedNextCharacters` and wrong ones from its complement, so
    /// the typist never guesses — a brute-force typist would record every wrong guess as a
    /// mistake and the trace under test would be its own noise.
    private func play(_ session: GameSession, mistypeAt kanaIndex: Int) -> MistakeTrace {
        let session = session
        var injected = 0
        var steps = 0
        while !session.isFinished, steps < 4_000 {
            steps += 1
            let expected = session.expectedNextCharacters
            guard !expected.isEmpty else { session.skip(); continue }
            if session.completedKanaCount == kanaIndex, injected < 2,
               let wrong = "aiueokstnhmyrwgzdbpj".first(where: { !expected.contains($0) }) {
                _ = session.input(wrong)
                injected += 1
                continue
            }
            _ = session.input(expected.sorted()[0])
        }
        return session.mistakes
    }

    /// A shipped entry whose sentence has at least three content tokens, so aiming at the
    /// second one makes an off-by-one walk visible.
    private func sentenceEntry() throws -> VocabEntry {
        try #require(VocabStore.shared.entries.first {
            $0.isTypeableSentence && ($0.exampleTokens?.filter { $0[1].count > 0 }.count ?? 0) >= 3
        })
    }

    /// Same shape as `cleanEntry`, but the second token must BE a particle.
    private func cleanParticleEntry() throws -> (entry: VocabEntry, index: Int, expected: String) {
        let particles = Set(["を", "は", "へ", "が", "に", "で", "と", "も", "の"])
        let entry = try #require(VocabStore.shared.entries.first { e in
            guard e.isTypeableSentence, let t = e.exampleTokens, t.count >= 3,
                  t[0].count >= 2, t[1].count >= 2 else { return false }
            return !t[0][1].isEmpty && particles.contains(t[1][0])
        })
        let tokens = try #require(entry.exampleTokens)
        return (entry, tokens[0][1].count, tokens[1][0])
    }

    /// The two modes disagree about particles on purpose, and the disagreement is the test:
    /// one run, one set of refusals, one flag apart.
    @Test("a particle is a listening stumble in dictation and coach material on screen")
    func particlesSplitByMode() throws {
        let vocab = VocabStore.shared
        let (entry, index, expected) = try cleanParticleEntry()
        var config = GameSession.Config()
        config.newWordCount = 1
        let trace = play(GameSession.makeDictation(ids: [entry.id], vocab: vocab, config: config),
                         mistypeAt: index)
        #expect(StumbledWords.from(trace, vocab: vocab, includesParticles: true)
                    .map(\.surface) == [expected])
        #expect(StumbledWords.from(trace, vocab: vocab, includesParticles: false).isEmpty)
    }

    @Test("a real sentence run names the word the refusals landed in")
    func sentenceRunNamesTheWord() throws {
        let vocab = VocabStore.shared
        let entry = try sentenceEntry()
        var config = GameSession.Config()
        config.newWordCount = 1
        let index = try #require(entry.exampleTokens?.first?[1].count)
        let target = try #require(entry.exampleToken(atReadingIndex: index))

        let session = GameSession.makeSentence(ids: [entry.id], vocab: vocab, config: config)
        let stumbles = StumbledWords.from(play(session, mistypeAt: index), vocab: vocab)
        #expect(stumbles.map(\.surface) == [target.surface])
        #expect(stumbles.first?.refusals == 2)
    }

    @Test("a dictation run reports the same way — the mode does not change the attribution")
    func dictationRunNamesTheWord() throws {
        let vocab = VocabStore.shared
        let entry = try sentenceEntry()
        var config = GameSession.Config()
        config.newWordCount = 1
        let index = try #require(entry.exampleTokens?.first?[1].count)
        let target = try #require(entry.exampleToken(atReadingIndex: index))

        let session = GameSession.makeDictation(ids: [entry.id], vocab: vocab, config: config)
        #expect(StumbledWords.from(play(session, mistypeAt: index), vocab: vocab)
                    .map(\.surface) == [target.surface])
    }

    /// Found by the pre-submission review, not by any test: the results screen keyed its chips
    /// by `reading`, and 35 shipped sentences carry two spellings of one reading. Two stumbles
    /// that read alike must stay two distinct values, or the ForEach drawing them has duplicate
    /// ids and renders whichever it likes.
    @Test("two words that read alike are two stumbles, distinguishable")
    func sameReadingDifferentSurface() throws {
        let vocab = VocabStore.shared
        // A real sentence containing two spellings of one reading.
        let kana = CharacterSet(charactersIn: "\u{3041}"..."\u{30FF}")
        let entry = try #require(vocab.entries.first { e in
            guard e.isTypeableSentence, let tokens = e.exampleTokens else { return false }
            var byReading: [String: Set<String>] = [:]
            for token in tokens where token.count >= 2 && !token[1].isEmpty
                && token[1].unicodeScalars.allSatisfy(kana.contains) {
                byReading[token[1], default: []].insert(token[0])
            }
            return byReading.values.contains { $0.count > 1 }
        })
        let tokens = try #require(entry.exampleTokens)
        var byReading: [String: [Int]] = [:]     // reading -> reading-index of each occurrence
        var consumed = 0
        for token in tokens where token.count >= 2 {
            let reading = token[1].filter { !"。、!?「」・".contains($0) }
            if reading.isEmpty { continue }
            byReading[reading, default: []].append(consumed)
            consumed += reading.count
        }
        let collidingIndices = try #require(byReading.values.first { $0.count > 1 })

        var trace = MistakeTrace()
        var order = 0
        for index in collidingIndices.prefix(2) {
            for _ in 0..<2 {          // two refusals each, so both clear minimumRefusals
                trace.record(MistakeEvent(targetKana: entry.exampleKana!, entryID: entry.id,
                                          acceptedRomaji: "", rejected: "q",
                                          expectedNext: [], kanaIndex: index, order: order))
                order += 1
            }
        }
        let stumbles = StumbledWords.from(trace, vocab: vocab)
        #expect(stumbles.count == 2)
        #expect(Set(stumbles).count == 2, "two stumbles collapsed into one identity")
        // …and this is what the screen used to key on, which is why it had to change.
        #expect(Set(stumbles.map(\.reading)).count == 1)
    }

    @Test("a word run over the same entry produces nothing")
    func wordRunStaysOut() throws {
        let vocab = VocabStore.shared
        let entry = try sentenceEntry()
        var config = GameSession.Config()
        config.newWordCount = 1
        // Same entry, ordinary word run: the target is the WORD's reading, so indexing
        // exTokens with these events would name a word at random.
        let session = GameSession.makeWeak(ids: [entry.id], vocab: vocab, config: config)
        #expect(StumbledWords.from(play(session, mistypeAt: 1), vocab: vocab).isEmpty)
    }
}

// MARK: - What a lapsed entry IS, per mode (v1.25 §B)

/// The results screen draws lapsed entries as words. In two modes they are not words.
///
/// `GameSession.sentenceSession` wraps each sentence as a `VocabEntry` whose `surface` is the
/// whole sentence and whose `kana` is the whole reading, so a sentence or dictation run's
/// `lapsedEntries` are sentences wearing a word's shape. The results screen rendered them in
/// 116pt word cells: 「友達と映画を見ました。」 wrapped over two lines, captioned with one word's
/// gloss, and announced by VoiceOver as "Save 〈whole sentence〉" — while the star saved the
/// headword, a word the cell never named.
///
/// `GameMode.lapsesAreWords` is the one predicate the tile and the list now share. This checks
/// it against what the BUILDERS actually produce rather than restating the list of modes, which
/// would be the same rule written twice.
@Suite("A lapsed entry is only a word in the modes where it is one")
struct LapsesAreWordsTests {

    private static func store() -> VocabStore {
        VocabStore(entries: (0..<8).map { i in
            VocabEntry(id: "w\(i)", surface: "水\(i)", kana: "みず\(i)",
                       partsOfSpeech: ["n"], jlpt: .n5, meanings: ["en": ["water"]],
                       exampleJP: "これは水\(i)です。", exampleEN: "This is water.",
                       exampleKana: "これはみず\(i)です",
                       exampleTokens: [["これ", "これ"], ["は", "は"], ["水\(i)", "みず\(i)"],
                                       ["です", "です"], ["。", "。"]])
        })
    }

    @Test("the predicate matches what the session builders actually queue")
    func predicateMatchesTheBuilders() throws {
        let vocab = Self.store()
        var config = GameSession.Config()
        config.newWordCount = 4
        config.reviewWordCount = 0

        // A sentence run queues entries whose surface is the SENTENCE.
        let sentence = GameSession.makeSentence(vocab: vocab, config: config)
        let queuedSentence = try #require(sentence.wordList.first)
        #expect(queuedSentence.surface.count > 4,
                "a sentence run should queue a whole sentence, not a word: \(queuedSentence.surface)")
        #expect(GameMode.sentence.lapsesAreWords == false)

        // A word run queues the words themselves.
        var wordConfig = config
        wordConfig.mode = .journey
        let journey = GameSession.make(config: wordConfig, vocab: vocab, review: ReviewStore())
        let queuedWord = try #require(journey.wordList.first)
        #expect(vocab.entry(id: queuedWord.id)?.surface == queuedWord.surface,
                "a word run should queue the entry as it is stored")
        #expect(GameMode.journey.lapsesAreWords)
    }

    /// The predicate must not quietly become "everything is a word", which would restore the
    /// bug while every other assertion still passed.
    @Test("exactly the sentence-shaped modes are excluded")
    func onlySentenceShapedModesAreExcluded() {
        let excluded = GameMode.allCases.filter { !$0.lapsesAreWords }
        #expect(Set(excluded) == [.sentence, .dictation],
                Comment(rawValue: "excluded: \(excluded)"))
    }
}

