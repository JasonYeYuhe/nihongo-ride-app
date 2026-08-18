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
        #expect(a == [StumbledWords.Stumble(surface: "警官", reading: "けいかん", refusals: 2, entryID: nil),
                      StumbledWords.Stumble(surface: "潜入", reading: "せんにゅう", refusals: 2, entryID: "s1")])
    }
}

// MARK: - Turning a stumbled word back into a word you can do something with

/// v1.24 §A. A chip is a surface and a reading; saving, listing or riding it needs a
/// `VocabEntry.id`. Everything here is about the rule that turns one into the other, and every
/// case that must NOT turn into one — which is the half that decides whether the feature is
/// honest, because a wrong id offers the learner a card for a word they never saw.
@Suite("Resolving a stumbled word to an entry")
struct StumbledWordResolutionTests {

    /// 生 is the homograph this rule exists for: one written form, two entries, two readings.
    private let namaEntry = VocabEntry(id: "nama", surface: "生", kana: "なま",
                                       partsOfSpeech: ["n"], jlpt: .n3, meanings: ["en": ["raw"]])
    private let seiEntry = VocabEntry(id: "sei", surface: "生", kana: "せい",
                                      partsOfSpeech: ["n"], jlpt: .n2, meanings: ["en": ["life"]])
    private let team = VocabEntry(id: "team", surface: "チーム", kana: "チーム",
                                  partsOfSpeech: ["n"], jlpt: .n3, meanings: ["en": ["team"]])
    private let hand = VocabEntry(id: "hand", surface: "手", kana: "て",
                                  partsOfSpeech: ["n"], jlpt: .n5, meanings: ["en": ["hand"]])
    /// The one shipped entry whose surface is a bare particle (n3-b612 で/で, "and, then").
    private let deConjunction = VocabEntry(id: "de", surface: "で", kana: "で",
                                           partsOfSpeech: ["conj"], jlpt: .n3,
                                           meanings: ["en": ["and", "then"]])

    private var store: VocabStore {
        VocabStore(entries: [namaEntry, seiEntry, team, hand, deConjunction])
    }

    @Test("both halves must agree — an exact pair resolves")
    func exactPairResolves() {
        #expect(store.entry(surface: "手", reading: "て")?.id == "hand")
    }

    /// The failure this whole design is built around. 手 is written 手 and read て; a token
    /// written 手 but read something else is not this entry, and naming it anyway is how
    /// "resolve the ambiguity by regressing to the common answer" gets into a release.
    @Test("a surface match with a disagreeing reading resolves to nothing")
    func surfaceOnlyIsRefused() {
        #expect(store.entry(surface: "手", reading: "しゅ") == nil)
    }

    /// The measured trap: kana-only tokens are usually function morphemes, and a reading index
    /// always finds some noun spelled that way. て is the te-form connective 2,130 times in the
    /// shipped corpus; 手 is a hand. The learner stumbled on the first and must not be offered
    /// the second.
    @Test("a reading match with no written form behind it resolves to nothing")
    func readingOnlyIsRefused() {
        #expect(store.entry(surface: "て", reading: "て") == nil)
    }

    /// `exTokens` writes a loanword's reading in hiragana while the entry stores katakana.
    /// They are one word — 33 shipped sentences say so — and the folding is `KanaScript`'s,
    /// the same one the typing matcher uses, not a second copy of the rule.
    @Test("katakana and hiragana readings are the same reading")
    func katakanaFolds() {
        #expect(store.entry(surface: "チーム", reading: "ちーむ")?.id == "team")
        #expect(store.entry(surface: "チーム", reading: "チーム")?.id == "team")
    }

    /// An ambiguous key has no right answer, so it gets none. First-wins would be a coin toss
    /// dressed as a lookup.
    @Test("a pair claimed by two entries resolves to neither")
    func ambiguousPairIsDropped() {
        let twins = VocabStore(entries: [
            VocabEntry(id: "a", surface: "同", kana: "どう", partsOfSpeech: ["n"], jlpt: .n3,
                       meanings: ["en": ["same"]]),
            VocabEntry(id: "b", surface: "同", kana: "どう", partsOfSpeech: ["n"], jlpt: .n1,
                       meanings: ["en": ["ditto"]])])
        #expect(twins.entry(surface: "同", reading: "どう") == nil)
    }

    /// Blocked on the token, not on the lookup — the corpus really does contain で/で, and a
    /// learner who misheard the で of 電車で would otherwise be handed a conjunction card.
    @Test("a grammatical particle never resolves, even when the corpus has an entry for it")
    func particlesNeverResolve() {
        #expect(store.entry(surface: "で", reading: "で") == nil)
        // …and the entry is genuinely there, so this test is measuring the block and not an
        // empty store.
        #expect(store.entry(id: "de") != nil)
    }

    // MARK: Layer 1 — the word the sentence was written to teach

    private func sentence(teaching entry: VocabEntry, tokens: [[String]], kana: String) -> VocabEntry {
        VocabEntry(id: entry.id, surface: entry.surface, kana: entry.kana,
                   partsOfSpeech: entry.partsOfSpeech, jlpt: entry.jlpt, meanings: entry.meanings,
                   exampleJP: tokens.map { $0[0] }.joined(), exampleKana: kana, exampleTokens: tokens)
    }

    @Test("the taught word resolves to its own entry without consulting the index")
    func taughtWordResolves() {
        let taught = sentence(teaching: namaEntry,
                              tokens: [["生", "なま"], ["の", "の"], ["魚", "さかな"]],
                              kana: "なまのさかな")
        // A store that does NOT contain the taught entry: the id can only have come from the
        // entry in hand, which is the property this path is for.
        let bare = VocabStore(entries: [hand])
        #expect(StumbledWords.entryID(for: (surface: "生", reading: "なま"),
                                      taughtBy: taught, in: bare) == "nama")
    }

    /// The reason layer 1 checks the reading too. A sentence teaching 生/なま that contains
    /// 生 read せい must not have the せい token attributed to the なま entry just because the
    /// characters match — that is the surface-only failure wearing a different hat.
    @Test("the taught word's id is not applied to a homograph read differently")
    func taughtWordDoesNotSwallowItsHomograph() {
        let taught = sentence(teaching: namaEntry,
                              tokens: [["生", "せい"], ["活", "かつ"]], kana: "せいかつ")
        #expect(StumbledWords.entryID(for: (surface: "生", reading: "せい"),
                                      taughtBy: taught, in: VocabStore(entries: [namaEntry])) == nil)
        // With the せい entry present it resolves — to せい, via the pair index, not to なま.
        #expect(StumbledWords.entryID(for: (surface: "生", reading: "せい"),
                                      taughtBy: taught, in: store) == "sei")
    }

    // MARK: What the run will contain

    /// The count-vs-run contract in its smallest form: the ids come from one function, so a
    /// caller cannot compute the number one way and the ride another.
    @Test("rideableIDs drops the chips that name nothing and applies the run's own predicate")
    func rideableIDsFilter() {
        let chips = [
            StumbledWords.Stumble(surface: "手", reading: "て", refusals: 3, entryID: "hand"),
            StumbledWords.Stumble(surface: "て", reading: "て", refusals: 2, entryID: nil),
            StumbledWords.Stumble(surface: "生", reading: "なま", refusals: 2, entryID: "nama"),
        ]
        #expect(StumbledWords.rideableIDs(in: chips, resolves: store.resolvesID) == ["hand", "nama"])
        // A withdrawn entry is dropped by the run builder, so it must be dropped by the count.
        let withoutNama = VocabStore(entries: [hand, team])
        #expect(StumbledWords.rideableIDs(in: chips, resolves: withoutNama.resolvesID) == ["hand"])
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

// MARK: - The resolution rule, measured against the corpus it will actually run on

/// The stop rule for v1.24 §A: the resolution numbers are re-measured here, at build time,
/// rather than quoted from the plan. A number in a document is a number that was true once.
///
/// Two of these assert a floor and one asserts an invariant, and the invariant is the one that
/// matters. A coverage floor tells you the feature still does something; the invariant tells
/// you that everything it does is *right*, exhaustively, over all 41,000-odd tokens the
/// shipped sentences contain — which is the property a learner's saved-word list depends on.
@Suite("Stumbled-word resolution over the shipped corpus")
struct ShippedResolutionTests {

    private static let punctuation: Set<Character> = ["。", "、", "！", "？", "「", "」", "・"]

    /// Every (token, owning entry) pair in the shipped sentences.
    private static var corpusTokens: [(token: (surface: String, reading: String), owner: VocabEntry)] {
        var out: [(token: (surface: String, reading: String), owner: VocabEntry)] = []
        for entry in VocabStore.shared.entries where entry.isTypeableSentence {
            for token in entry.exampleTokens ?? [] where token.count >= 2 {
                guard !token[1].allSatisfy({ Self.punctuation.contains($0) }), !token[1].isEmpty
                else { continue }
                out.append(((surface: token[0], reading: token[1]), entry))
            }
        }
        return out
    }

    /// The safety invariant, and the reason the rule refuses so much.
    ///
    /// Whatever a token resolves to, that entry must be written the way the token is written
    /// AND read the way the token is read. Not "usually" — every single time, or the app is
    /// offering somebody a card for a word that was never on their screen. This is the one
    /// property that makes it safe to hang a ★ off a chip.
    @Test("a token never resolves to an entry that is written or read differently")
    func resolutionNeverNamesADifferentWord() {
        var checked = 0
        for (token, owner) in Self.corpusTokens {
            guard let id = StumbledWords.entryID(for: token, taughtBy: owner, in: .shared),
                  let named = VocabStore.shared.entry(id: id) else { continue }
            checked += 1
            #expect(named.surface == token.surface,
                    "\(owner.id): token \(token.surface)/\(token.reading) resolved to \(named.surface)/\(named.kana)")
            #expect(KanaScript.katakanaToHiragana(named.kana)
                        == KanaScript.katakanaToHiragana(token.reading),
                    "\(owner.id): token \(token.surface)/\(token.reading) resolved to \(named.surface)/\(named.kana)")
        }
        // An invariant that inspected nothing is not an invariant. This is the shape of the
        // "clean number from an untested instrument" failure this project keeps logging.
        #expect(checked > 20_000, "only \(checked) tokens resolved — the walk stopped measuring")
    }

    /// Particles are blocked on the token in every mode, and the corpus contains an entry that
    /// would otherwise be matched (で/で). Exhaustive rather than sampled, because the block is
    /// one `contains` away from being deleted by accident.
    @Test("no grammatical particle anywhere in the corpus resolves to a word")
    func noParticleResolves() {
        var particleTokens = 0
        for (token, owner) in Self.corpusTokens
        where JapaneseParticles.single.contains(token.surface) {
            particleTokens += 1
            #expect(StumbledWords.entryID(for: token, taughtBy: owner, in: .shared) == nil,
                    "\(owner.id): particle \(token.surface) resolved")
        }
        #expect(particleTokens > 5_000, "only \(particleTokens) particle tokens seen — the scan is wrong")
        // …and the entry that makes this a real block rather than a vacuous one is still there.
        // If it is ever retired this test keeps passing for the wrong reason, so say so here.
        #expect(VocabStore.shared.entries.contains(where: { JapaneseParticles.single.contains($0.surface) }),
                "no entry has a particle surface any more, so the block above is vacuous and proves nothing")
    }

    /// Coverage, re-measured. The floors are set well below what was measured (58.4% of content
    /// tokens, 74.1% of the ones containing kanji) so that ordinary corpus maintenance does not
    /// turn the suite red, and high enough that the feature silently degrading does.
    @Test("the rule still resolves most of the vocabulary a learner would want to save")
    func coverageFloorsHold() {
        var content = 0, contentResolved = 0, kanji = 0, kanjiResolved = 0
        for (token, owner) in Self.corpusTokens {
            if JapaneseParticles.single.contains(token.surface) { continue }
            let resolved = StumbledWords.entryID(for: token, taughtBy: owner, in: .shared) != nil
            content += 1
            if resolved { contentResolved += 1 }
            if token.surface.contains(where: { $0.isKanji }) {
                kanji += 1
                if resolved { kanjiResolved += 1 }
            }
        }
        #expect(content > 40_000, "only \(content) content tokens — the corpus walk is wrong")
        let contentRate = Double(contentResolved) / Double(content)
        let kanjiRate = Double(kanjiResolved) / Double(kanji)
        #expect(contentRate > 0.50, "content-token resolution fell to \(contentRate)")
        #expect(kanjiRate > 0.65, "kanji-token resolution fell to \(kanjiRate)")
    }
}

private extension Character {
    /// CJK unified ideographs. Deliberately not `isIdeographic`, which also takes kana marks.
    var isKanji: Bool {
        unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
    }
}
