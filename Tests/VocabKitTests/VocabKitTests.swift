import Testing
import RomajiKana
@testable import VocabKit

@Suite("VocabKit")
struct VocabKitTests {
    let store = VocabStore.shared

    @Test("packs load across all five JLPT levels")
    func loads() {
        #expect(!store.isEmpty)
        #expect(store.entries.count >= 500)
        for level in JLPTLevel.allCases {
            #expect(!store.entries(level: level).isEmpty, "no entries for \(level.label)")
        }
    }

    @Test("every entry has English and Chinese meanings")
    func meaningsPresent() {
        for entry in store.entries {
            #expect(!entry.meanings(for: "en").isEmpty, "\(entry.id) missing en gloss")
            #expect(!entry.meanings(for: "zh").isEmpty, "\(entry.id) missing zh gloss")
        }
    }

    /// Cross-validation: every reading, typed via its generated romaji hint, must
    /// complete on the engine. This catches any non-kana / mistyped reading in the
    /// data and proves the romanizer round-trips on real vocabulary.
    @Test("every reading is typeable by the engine")
    func readingsAreTypeable() {
        for entry in store.entries {
            var matcher = KanaInputMatcher(target: entry.kana)
            var allAccepted = true
            for character in entry.romaji where matcher.input(character) == .rejected {
                allAccepted = false
                break
            }
            #expect(allAccepted && matcher.isComplete,
                    "‘\(entry.romaji)’ should type ‘\(entry.kana)’ (\(entry.id))")
        }
    }

    @Test("entry ids are unique")
    func uniqueIDs() {
        let ids = store.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("difficulty stays within 0...1 and varies")
    func difficultyBounds() {
        for entry in store.entries {
            #expect(entry.difficulty >= 0 && entry.difficulty <= 1, "\(entry.id): \(entry.difficulty)")
        }
        // The pack should contain a spread of difficulties, not all-identical.
        #expect(Set(store.entries.map { Int($0.difficulty * 100) }).count > 5)
    }

    @Test("ordered() is sorted easiest-first")
    func orderedSorted() {
        let ordered = store.ordered()
        #expect(ordered.count == store.entries.count)
        for i in 1 ..< ordered.count {
            #expect(ordered[i - 1].difficulty <= ordered[i].difficulty)
        }
    }

    @Test("meaning lookup falls back for an unknown language")
    func meaningFallback() {
        let entry = try! #require(store.entry(id: "n5-gakkou"))
        #expect(entry.meanings(for: "fr") == entry.meanings(for: "en"))  // unknown → en fallback
        #expect(entry.gloss(for: "zh") == "学校")
    }

    @Test("level filtering and id lookup")
    func levelFilter() {
        let n5Count = store.entries(level: .n5).count
        #expect(n5Count >= 100)
        #expect(n5Count < store.entries.count)            // higher levels exist too
        #expect(store.entry(id: "n5-mizu")?.kana == "みず")
        #expect(store.entry(id: "does-not-exist") == nil)
    }

    @Test("readings are globally unique across levels")
    func globallyUnique() {
        let kana = store.entries.map(\.kana)
        #expect(Set(kana).count == kana.count)
    }

    @Test("practice passages load and every kana is typeable by the engine")
    func passages() {
        let store = PassageStore.shared
        #expect(store.passages.count >= 30)
        for passage in store.passages {
            var matcher = KanaInputMatcher(target: passage.kana)
            var allAccepted = true
            for character in KanaRomanizer.romaji(for: passage.kana)
                where matcher.input(character) == .rejected {
                allAccepted = false; break
            }
            #expect(allAccepted && matcher.isComplete,
                    "passage \(passage.id) ‘\(passage.kana)’ failed to type")
            #expect(!passage.meaning(for: "en").isEmpty)
            #expect(!passage.meaning(for: "zh").isEmpty)
        }
    }

    @Test("every level carries example sentences with translations")
    func exampleSentences() {
        for level in JLPTLevel.allCases {
            let withExamples = store.entries(level: level).filter { $0.exampleJP != nil }
            #expect(withExamples.count >= 50, "\(level.label) has too few example sentences")
        }
        let sample = try! #require(store.entries.first { $0.exampleJP != nil })
        #expect(sample.exampleTranslation(for: "en") != nil)
        #expect(sample.exampleTranslation(for: "zh") != nil)
    }
}

// MARK: - v1.23 groundwork: turning a position in a sentence back into a word

@Suite("Which word was the learner typing")
struct ExampleTokenLocationTests {

    /// 「犬が走る。」 — readings いぬ / が / はしる, and the 。 contributes nothing because
    /// exKana has no punctuation (a romaji keyboard cannot produce it).
    private let entry = VocabEntry(
        id: "x", surface: "犬", kana: "いぬ", partsOfSpeech: ["n"], jlpt: .n5,
        meanings: ["en": ["dog"]],
        exampleJP: "犬が走る。", exampleKana: "いぬがはしる",
        exampleTokens: [["犬", "いぬ"], ["が", "が"], ["走る", "はしる"], ["。", "。"]])

    /// Every index in the reading maps to the word that covers it. This is the whole point:
    /// a sentence run counts mistakes and cannot name what was got wrong, and the tokens
    /// have carried the answer since v1.18.
    @Test("every position in the reading names the word it belongs to")
    func everyPositionMaps() {
        let expected = ["犬", "犬", "が", "走る", "走る", "走る"]   // いぬ|が|はしる
        for (index, surface) in expected.enumerated() {
            #expect(entry.exampleToken(atReadingIndex: index)?.surface == surface,
                    Comment(rawValue: "index \(index) of \(entry.exampleKana!)"))
        }
    }

    /// The walk has to stay aligned with `exampleKana`, which drops punctuation. If the 。
    /// token consumed a position the mapping would slide by one for every sentence with
    /// mid-sentence punctuation, and name the word BEFORE the one the learner mistyped.
    @Test("punctuation tokens consume no position")
    func punctuationIsSkipped() {
        let comma = VocabEntry(
            id: "y", surface: "雨", kana: "あめ", partsOfSpeech: ["n"], jlpt: .n5,
            meanings: ["en": ["rain"]],
            exampleJP: "雨だ、行こう。", exampleKana: "あめだいこう",
            exampleTokens: [["雨", "あめ"], ["だ", "だ"], ["、", "、"], ["行こう", "いこう"], ["。", "。"]])
        #expect(comma.exampleKana?.count == 6)
        #expect(comma.exampleToken(atReadingIndex: 2)?.surface == "だ")
        #expect(comma.exampleToken(atReadingIndex: 3)?.surface == "行こう")   // not 、
    }

    /// A stale index must return nothing rather than the last word by accident — the caller
    /// would then name a word the learner never touched.
    @Test("an out-of-range index names nothing")
    func outOfRangeIsNil() {
        #expect(entry.exampleToken(atReadingIndex: 6) == nil)
        #expect(entry.exampleToken(atReadingIndex: 99) == nil)
        #expect(entry.exampleToken(atReadingIndex: -1) == nil)
    }

    /// An entry with no tokens is the 14 digit/middle-dot sentences and every non-sentence
    /// card. It must answer nothing, not crash.
    @Test("an entry without tokens answers nothing")
    func noTokens() {
        let bare = VocabEntry(id: "z", surface: "水", kana: "みず", partsOfSpeech: ["n"],
                              jlpt: .n5, meanings: ["en": ["water"]])
        #expect(bare.exampleToken(atReadingIndex: 0) == nil)
    }

    /// The invariant this rests on, checked against every shipped sentence rather than
    /// assumed: the tokens' readings reconstruct `exKana` exactly, so a cumulative walk
    /// cannot drift. If this ever fails, the mapping silently names wrong words.
    @Test("token readings reconstruct exKana for every shipped sentence")
    func readingsReconstructTheWholeCorpus() {
        let punctuation: Set<Character> = ["。", "、", "！", "？", "「", "」", "・"]
        var broken: [String] = []
        for e in VocabStore.shared.entries {
            guard let kana = e.exampleKana, let tokens = e.exampleTokens else { continue }
            let rebuilt = tokens.compactMap { $0.count >= 2 ? $0[1] : nil }
                .joined()
                .filter { !punctuation.contains($0) }
            if rebuilt != kana { broken.append("\(e.id): \(rebuilt) != \(kana)") }
        }
        #expect(broken.isEmpty, Comment(rawValue: "\(broken.count) sentence(s) whose tokens do "
                                                  + "not rebuild their reading:\n"
                                                  + broken.prefix(5).joined(separator: "\n")))
    }
}

// MARK: - Which words stopped the learner

@Suite("Stumbled words")
struct StumbledWordsTests {

    private let sentence = VocabEntry(
        id: "s1", surface: "潜入", kana: "せんにゅう", partsOfSpeech: ["n"], jlpt: .n1,
        meanings: ["en": ["infiltration"]],
        exampleJP: "警官が潜入した。", exampleKana: "けいかんがせんにゅうした",
        exampleTokens: [["警官", "けいかん"], ["が", "が"], ["潜入", "せんにゅう"],
                        ["し", "し"], ["た", "た"], ["。", "。"]])

    private var store: VocabStore {
        VocabStore(entries: [sentence,
                             VocabEntry(id: "w1", surface: "水", kana: "みず",
                                        partsOfSpeech: ["n"], jlpt: .n5,
                                        meanings: ["en": ["water"]])])
    }

    private func refusal(_ id: String?, target: String, at index: Int, order: Int) -> MistakeEvent {
        MistakeEvent(targetKana: target, entryID: id, acceptedRomaji: "",
                     rejected: "x", expectedNext: ["n"], kanaIndex: index, order: order)
    }

    /// The whole point: a sentence run can now name the word instead of counting.
    @Test("refusals inside a word are attributed to that word")
    func attributesToTheWord() {
        var trace = MistakeTrace()
        // three refusals inside せんにゅう (indices 5,6,7 of けいかんがせんにゅうした)
        for (i, index) in [5, 6, 7].enumerated() {
            trace.record(refusal("s1", target: sentence.exampleKana!, at: index, order: i))
        }
        let stumbles = StumbledWords.from(trace, vocab: store)
        #expect(stumbles.count == 1)
        #expect(stumbles.first?.surface == "潜入")
        #expect(stumbles.first?.reading == "せんにゅう")
        #expect(stumbles.first?.refusals == 3)
    }

    /// A word run's mistakes already name their own word, and its `targetKana` is the word's
    /// reading — not the sentence's. Indexing exTokens with it would name a word at random,
    /// so those events must be ignored entirely. This is the guard that keeps the two
    /// explanations from contaminating each other.
    @Test("a word run's refusals are not attributed to sentence words")
    func wordRunsAreIgnored() {
        var trace = MistakeTrace()
        for i in 0..<3 {
            trace.record(refusal("w1", target: "みず", at: 0, order: i))
            // …and an event whose id IS a sentence entry but whose target is the WORD, which
            // is what a journey run over that same entry produces.
            trace.record(refusal("s1", target: "せんにゅう", at: 0, order: 10 + i))
        }
        #expect(StumbledWords.from(trace, vocab: store).isEmpty)
    }

    /// One slip inside a word is a typo. The list is meant to be the words that actually
    /// stopped the learner, and a list of everything they ever fumbled is a list nobody reads.
    @Test("a single slip is not a stumble")
    func singleSlipDropped() {
        var trace = MistakeTrace()
        trace.record(refusal("s1", target: sentence.exampleKana!, at: 0, order: 0))
        #expect(StumbledWords.from(trace, vocab: store).isEmpty)
        #expect(StumbledWords.from(trace, vocab: store, minimumRefusals: 1).count == 1)
    }

    /// Unresolvable ids and passages (no id at all) must not crash or invent a word.
    @Test("events with no resolvable entry are skipped")
    func unresolvableSkipped() {
        var trace = MistakeTrace()
        trace.record(refusal(nil, target: "あいう", at: 0, order: 0))
        trace.record(refusal("gone", target: "あいう", at: 1, order: 1))
        #expect(StumbledWords.from(trace, vocab: store).isEmpty)
    }

    /// Two runs with the same refusals must produce the same order — a results list that
    /// reshuffles between identical runs looks broken.
    @Test("the order is stable")
    func stableOrder() {
        var trace = MistakeTrace()
        for (i, index) in [0, 1, 5, 6].enumerated() {   // 警官 twice, 潜入 twice
            trace.record(refusal("s1", target: sentence.exampleKana!, at: index, order: i))
        }
        let a = StumbledWords.from(trace, vocab: store)
        let b = StumbledWords.from(trace, vocab: store)
        #expect(a == b)
        // Two words, two refusals each — so the tie-break decides the order, and it has to
        // decide it the same way every time. Ties break on the reading, ascending.
        #expect(a == [StumbledWords.Stumble(surface: "警官", reading: "けいかん", refusals: 2),
                      StumbledWords.Stumble(surface: "潜入", reading: "せんにゅう", refusals: 2)])
    }
}

// MARK: - What keeps sentence mistakes and word mistakes apart

@Suite("Sentence/word attribution guard")
struct AttributionGuardTests {

    /// `StumbledWords` tells a sentence run's mistakes from a word run's by comparing the
    /// event's target against `exampleKana`. That works because a word's reading and its
    /// sentence's reading differ — which is true of 6,723 of the 6,724 shipped sentences and
    /// is a property of the DATA, not of the code.
    ///
    /// The exception is こんにちは, whose example sentence is the word. The guard misfires
    /// there, and harmlessly: the sentence is one content token, so the walk names こんにちは
    /// — the word the learner was in fact typing. That is what this pins. A future entry
    /// whose sentence equals its reading but splits into several tokens would name the wrong
    /// one, and this is where it stops.
    @Test("any entry whose sentence reads like its word must be a single token")
    func collisionsAreSingleToken() throws {
        let colliding = VocabStore.shared.entries.filter { $0.exampleKana == $0.kana }
        #expect(!colliding.isEmpty, "no collisions at all means the probe stopped measuring")
        for entry in colliding {
            let content = try #require(entry.exampleTokens).filter { !$0[1].isEmpty && $0[1] != "。" }
            #expect(content.count == 1,
                    "\(entry.id): sentence reads like the word but splits into \(content.count) tokens")
            #expect(content.first?[0] == entry.surface, "\(entry.id): token is not the word itself")
        }
    }
}
