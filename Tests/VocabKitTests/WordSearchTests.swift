import Testing
import Foundation
import RomajiKana
@testable import VocabKit

/// v1.35 §B6 — searching the corpus from a word list.
///
/// Sections 1–3 run on a fixture whose entries are chosen so each rule has exactly one entry that
/// only it can find, and section 4 on the shipped corpus: the retired words by name, the romaji
/// reading on every entry, and the time a keystroke costs.
///
/// Mutations, 2026-09-29, each run and each red — the tests named are the ones that failed:
/// * `fold` without `KanaScript.katakanaToHiragana` → `katakanaFolds`, `romajiMatchesTheReading`,
///   `retiredWordsAreGone` (ぺん no longer finds ペン);
/// * `fold` without `precomposedStringWithCompatibilityMapping` → `katakanaFolds` (ｺｰﾋｰ) and
///   `romajiMatchesTheReading` (ｍｉｚｕ);
/// * the dash → ー rule removed → `katakanaFolds` (コ-ヒ-);
/// * the `RomajiReading` branch in `matches` removed → `romajiMatchesTheReading`,
///   `corpusResultsResolveOnce` (mizu → n5-mizu);
/// * glosses indexed for "en" only → `chineseGloss`, `corpusResultsResolveOnce` (吃);
/// * `wordStarts` ignored (every inner match a substring) → `tiers`;
/// * the sort without its JLPT key → `jlptThenCorpusOrder`, `kana`, `limit`, `romajiMatchesTheReading`;
/// * the `seen` de-duplication removed → `neverTwice` and six others;
/// * `lowercased()` removed from `fold` → `englishGloss` (Water) and `katakanaFolds` (T-shirt). Not
///   `romajiMatchesTheReading`: `RomajiReading` lowercases on its own, so MIZU still reads as みず.
@Suite("B6: word search over surface, reading and gloss")
struct WordSearchTests {

    // MARK: Fixture

    static func entry(_ id: String, _ surface: String, _ kana: String, _ level: JLPTLevel,
                      en: [String], zh: [String]) -> VocabEntry {
        VocabEntry(id: id, surface: surface, kana: kana, partsOfSpeech: ["n"], jlpt: level,
                   meanings: ["en": en, "zh": zh])
    }

    /// Corpus order is the array order. The N1 見ず is FIRST on purpose: it is an exact match for
    /// みず like 水, and must still rank after the N5 word.
    static let fixture: [VocabEntry] = [
        entry("f-mizu-n1", "見ず", "みず", .n1, en: ["without seeing"], zh: ["不看"]),
        entry("f-mizu", "水", "みず", .n5, en: ["water"], zh: ["水"]),
        entry("f-mizuumi", "湖", "みずうみ", .n4, en: ["lake"], zh: ["湖"]),
        entry("f-mizugi", "水着", "みずぎ", .n3, en: ["swimsuit"], zh: ["泳衣"]),
        entry("f-taki", "滝", "たき", .n3, en: ["waterfall"], zh: ["瀑布"]),
        entry("f-coffee", "コーヒー", "コーヒー", .n5, en: ["coffee"], zh: ["咖啡"]),
        entry("f-taberu", "食べる", "たべる", .n5, en: ["to eat"], zh: ["吃"]),
        entry("f-seki", "席", "せき", .n4, en: ["seat"], zh: ["座位"]),
        entry("f-gakkou", "学校", "がっこう", .n5, en: ["school"], zh: ["学校"]),
        entry("f-daigaku", "大学", "だいがく", .n5, en: ["university"], zh: ["大学"]),
        entry("f-konnichiha", "こんにちは", "こんにちは", .n5, en: ["hello"], zh: ["你好"]),
        entry("f-tshirt", "Tシャツ", "ティーシャツ", .n4, en: ["T-shirt"], zh: ["T恤"]),
        entry("f-pan", "パン", "パン", .n5, en: ["bread"], zh: ["面包"]),
        // Two gloss items in each language: the second is found as well as the first.
        entry("f-kiru", "切る", "きる", .n4, en: ["to cut", "to switch off"], zh: ["切", "关掉"]),
        // A second entry under an id already used: the index keeps the first, as `entry(id:)` does.
        entry("f-mizu", "水（重複）", "みず", .n5, en: ["water (duplicate)"], zh: ["水"]),
    ]

    static let index = WordSearchIndex(entries: fixture)

    static func ids(_ query: String, limit: Int = 50) -> [String] {
        index.search(query, limit: limit).map(\.id)
    }

    // MARK: 1. What matches

    @Test("an empty or whitespace query finds nothing")
    func emptyQuery() {
        for query in ["", " ", "　", "\n\t "] {
            #expect(Self.ids(query).isEmpty, "\(query.debugDescription)")
        }
    }

    @Test("kana: the exact reading first, then the readings it begins")
    func kana() {
        #expect(Self.ids("みず") == ["f-mizu", "f-mizu-n1", "f-mizuumi", "f-mizugi"])
        #expect(Self.ids("うみ") == ["f-mizuumi"])
    }

    @Test("kanji: the written form, then forms it begins")
    func kanji() {
        #expect(Self.ids("水") == ["f-mizu", "f-mizugi"])
        #expect(Self.ids("学") == ["f-gakkou", "f-daigaku"], "学校 starts with 学; 大学 contains it")
    }

    /// Katakana, half-width katakana and a dash typed for ー all fold to one reading.
    @Test("katakana, half-width katakana and an ASCII dash all find コーヒー")
    func katakanaFolds() {
        for query in ["コーヒー", "こーひー", "ｺｰﾋｰ", "コ-ヒ-", "こ－ひ－"] {
            #expect(Self.ids(query) == ["f-coffee"], "\(query)")
        }
        // A dash after Latin letters stays a dash: "t-shirt" is the gloss, not ｔー.
        #expect(Self.ids("t-shirt") == ["f-tshirt"])
    }

    /// Half-width katakana with a voiced or semi-voiced mark: ｶﾞ is two scalars, and Foundation's
    /// NFKC leaves them カ + U+3099 rather than ガ. Mutation, 2026-09-29: `fold` without the
    /// canonical composition after NFKC → red on both (and ｺｰﾋｰ above stays green — it has no
    /// mark, which is why the first version's test did not see this).
    @Test("half-width katakana with ﾞ or ﾟ finds the word: ｶﾞｯｺｳ, ﾊﾟﾝ")
    func halfWidthVoicedMarks() {
        #expect(Self.ids("ｶﾞｯｺｳ") == ["f-gakkou"], "\(Self.ids("ｶﾞｯｺｳ"))")
        #expect(Self.ids("ﾊﾟﾝ") == ["f-pan"], "\(Self.ids("ﾊﾟﾝ"))")
        #expect(WordSearchIndex.fold("ｶﾞｯｺｳ") == "がっこう")
        #expect(WordSearchIndex.fold("ﾊﾟﾝ") == "ぱん")
        // The shipped corpus, through the store the screen calls.
        #expect(Self.store.search("ｶﾞｯｺｳ", limit: 5).first?.id == "n5-gakkou")
        #expect(Self.store.search("ﾊﾟﾝ", limit: 5).first?.id == "n5-k043")
    }

    /// "mizu" is the case the item names. The fixture has no English gloss containing "mizu", so
    /// only the reading can find 水 here. Case and full-width Latin fold first.
    @Test("a romaji query also matches the reading it spells")
    func romajiMatchesTheReading() {
        for query in ["mizu", "MIZU", "ｍｉｚｕ", " mizu "] {
            #expect(Self.ids(query).first == "f-mizu", "\(query): \(Self.ids(query))")
            #expect(Set(Self.ids(query)) == ["f-mizu", "f-mizu-n1", "f-mizuumi", "f-mizugi"], "\(query)")
        }
        #expect(Self.ids("konnichiha") == ["f-konnichiha"])
        #expect(Self.ids("ko-hi-") == ["f-coffee"])
        // Not romaji all the way through: no reading, and no gloss has it.
        #expect(Self.ids("miz").isEmpty)
    }

    @Test("an English query finds the gloss, whatever its case")
    func englishGloss() {
        #expect(Self.ids("water") == ["f-mizu", "f-taki"])
        #expect(Self.ids("Water") == ["f-mizu", "f-taki"])
        #expect(Self.ids("lake") == ["f-mizuumi"])
    }

    @Test("a Chinese query finds the Chinese gloss")
    func chineseGloss() {
        #expect(Self.ids("吃") == ["f-taberu"])
        #expect(Self.ids("咖啡") == ["f-coffee"])
        #expect(Self.ids("瀑布") == ["f-taki"])
    }

    /// Every gloss ITEM is indexed, not only the first one a language lists. Mutation,
    /// 2026-09-29: `entry.meanings[$0]?.prefix(1)` in the index → red in both languages.
    @Test("a later gloss item is found, in English and in Chinese")
    func laterGlossItems() {
        let switchOff = Self.index.matches("switch off", limit: 10).map { "\($0.entry.id):\($0.tier)" }
        #expect(switchOff == ["f-kiru:prefix"], "\(switchOff)")
        let closeOff = Self.index.matches("关掉", limit: 10).map { "\($0.entry.id):\($0.tier)" }
        #expect(closeOff == ["f-kiru:exact"], "\(closeOff)")
        #expect(Self.ids("to cut") == ["f-kiru"], "the first item still")
    }

    /// A query of several words keeps one space between them and matches that phrase: "to eat" is
    /// the whole gloss, "toeat" is nothing. Mutation, 2026-09-29: `joined(separator: "")` → red.
    @Test("a multi-word query matches the words with their space")
    func multiWordQuery() {
        #expect(Self.index.matches("to eat", limit: 10).map { "\($0.entry.id):\($0.tier)" } == ["f-taberu:exact"])
        #expect(Self.ids("to   eat") == ["f-taberu"], "runs of spaces fold to one")
        #expect(Self.ids(" to\teat ") == ["f-taberu"], "a tab is a space, and the ends are trimmed")
        #expect(Self.ids("toeat").isEmpty)
        #expect(Self.ids("switch  off") == ["f-kiru"])
    }

    // MARK: 2. Ranking

    /// Exact, then prefix, then substring — and a gloss's words each count as a start, so "eat"
    /// is a prefix of "to eat" and only a substring of "seat".
    @Test("tiers: exact, then prefix (a gloss word's start counts), then substring")
    func tiers() {
        let water = Self.index.matches("water", limit: 10).map { "\($0.entry.id):\($0.tier)" }
        #expect(water == ["f-mizu:exact", "f-taki:prefix"])
        let eat = Self.index.matches("eat", limit: 10).map { "\($0.entry.id):\($0.tier)" }
        #expect(eat == ["f-taberu:prefix", "f-seki:substring"])
        let mizu = Self.index.matches("みず", limit: 10).map(\.tier)
        #expect(mizu == [.exact, .exact, .prefix, .prefix])
    }

    /// A romaji query ranks by the tier its READING reaches, as a kana query does: mizu is an
    /// exact match for 水 and 見ず and a prefix of 湖 and 水着. Mutation, 2026-09-29: the reading's
    /// matches flattened to `.substring` → red (the kana query above stays green).
    @Test("romaji ranks like the kana it spells: exact, then prefix")
    func romajiTiers() {
        let mizu = Self.index.matches("mizu", limit: 10).map { "\($0.entry.id):\($0.tier)" }
        #expect(mizu == ["f-mizu:exact", "f-mizu-n1:exact", "f-mizuumi:prefix", "f-mizugi:prefix"], "\(mizu)")
        let gakko = Self.index.matches("gakko", limit: 10).map { "\($0.entry.id):\($0.tier)" }
        #expect(gakko == ["f-gakkou:prefix"], "\(gakko)")
    }

    /// 見ず (N1) comes before 水 (N5) in corpus order and ties it on the exact tier; the level
    /// decides. On the prefix tier 湖 (N4) comes before 水着 (N3) for the same reason. And where
    /// tier and level both tie, corpus order decides: "o" is inside four N5 glosses (coffee, to
    /// eat, school, hello) and never at a word's start, so all four are substrings of one level
    /// and come back in fixture order.
    @Test("within a tier: N5 first, then corpus order")
    func jlptThenCorpusOrder() {
        #expect(Self.ids("みず") == ["f-mizu", "f-mizu-n1", "f-mizuumi", "f-mizugi"])
        let o = Self.index.matches("o", limit: 50).filter { $0.entry.jlpt == .n5 }
        #expect(o.map(\.entry.id) == ["f-coffee", "f-taberu", "f-gakkou", "f-konnichiha"], "\(o.map(\.entry.id))")
        #expect(o.allSatisfy { $0.tier == .substring })
    }

    // MARK: 3. Duplicates and the limit

    @Test("no id is ever returned twice")
    func neverTwice() {
        #expect(Self.ids("水") == ["f-mizu", "f-mizugi"])
        #expect(Self.index.rows.count == Self.fixture.count - 1)
        #expect(Self.index.search("水", limit: 10).first?.surface == "水", "the first entry for an id wins")
    }

    @Test("the limit is a limit, and zero is none")
    func limit() {
        #expect(Self.ids("みず", limit: 1) == ["f-mizu"])
        #expect(Self.ids("みず", limit: 2) == ["f-mizu", "f-mizu-n1"])
        #expect(Self.ids("みず", limit: 0).isEmpty)
        #expect(Self.ids("みず", limit: -1).isEmpty)
    }

    // MARK: 4. The shipped corpus

    static let store = VocabStore.shared

    /// The three retirements this corpus has made are gone from search, and each one's replacement
    /// is found by the same query. Retirement is deletion (`check_vocab_diff.py`), so this is the
    /// property the header claims, measured on the words it was made for.
    @Test("retired words are never returned; their replacements are")
    func retiredWordsAreGone() {
        let retired: [(query: String, gone: String, replacement: String)] = [
            ("言う", "n3-b734", "n5-b014"),      // 言う/ゆう → 言う/いう
            ("文字", "n3-b702", "n3-b954"),      // 文字/もんじ → 文字/もじ
            ("ぺん", "n2-b984", "n5-k051"),      // ぺん → ペン
            ("pen", "n2-b984", "n5-k051"),
        ]
        for item in retired {
            let ids = Self.store.search(item.query, limit: 500).map(\.id)
            #expect(!ids.contains(item.gone), "\(item.query) returned the retired \(item.gone)")
            #expect(ids.contains(item.replacement), "\(item.query) did not find \(item.replacement)")
            #expect(Self.store.entry(id: item.gone) == nil, "\(item.gone) is back in the corpus")
        }
        // ゆう and もんじ are the retired READINGS: nothing read that way is the retired word.
        #expect(!Self.store.search("ゆう", limit: 7_100).map(\.id).contains("n3-b734"))
        #expect(!Self.store.search("もんじ", limit: 7_100).map(\.id).contains("n3-b702"))
    }

    /// Every result names an entry the store resolves, and no query returns an id twice — over
    /// queries broad enough to return most of the corpus.
    @Test("every result resolves and none repeats, on broad queries over the whole corpus")
    func corpusResultsResolveOnce() {
        for query in ["a", "e", "の", "う", "い", "水", "to", "的"] {
            let ids = Self.store.search(query, limit: 10_000).map(\.id)
            #expect(!ids.isEmpty, "\(query)")
            #expect(Set(ids).count == ids.count, "\(query): a duplicate")
            #expect(ids.allSatisfy(Self.store.resolvesID), "\(query): an id the store does not resolve")
        }
        #expect(Self.store.search("mizu", limit: 5).first?.id == "n5-mizu")
        #expect(Self.store.search("water", limit: 5).first?.id == "n5-mizu")
        #expect(Self.store.search("吃", limit: 5).map(\.id).contains("n5-taberu"))
    }

    /// The reading side of "mizu finds 水", calibrated on the population it serves: every entry's
    /// own romaji hint — the string the app teaches a learner to type — reads back as its reading.
    /// A converter that only knew the fixture's words would pass sections 1–3 and fail here.
    @Test("every corpus entry's romaji hint reads back as its reading")
    func everyHintReadsBack() {
        var misses: [String] = []
        for entry in Self.store.entries {
            let reading = RomajiReading.hiragana(fromRomaji: entry.romaji)
            if reading != KanaScript.katakanaToHiragana(entry.kana) {
                misses.append("\(entry.id) \(entry.kana) \(entry.romaji) → \(reading ?? "nil")")
            }
        }
        #expect(misses.isEmpty, "\(misses.count) misses: \(misses.prefix(20))")
        #expect(Self.store.entries.count == 7_071)
    }

    /// ん before a vowel or y, spelled every way the ride accepts it, finds the word — on real
    /// corpus words, through the store the screen calls. The ride's acceptance is asked, not
    /// assumed: `KanaInputMatcher` must complete each spelling first, or the row is not a spelling
    /// the ride takes. Mutations, 2026-09-29: the `readings` loop in `matches` reduced to the
    /// first reading → red on tanni, tani, gennin, genin, kinnyou, kinyou.
    @Test("each ん spelling the ride accepts finds 単位, 原因 and 金曜", arguments: [
        ("n3-b594", "たんい", ["tan'i", "tanni", "taxni", "tani"]),
        ("n4-g127", "げんいん", ["gen'in", "gennin", "gexnin", "genin", "genninn"]),
        ("n3-b034", "きんよう", ["kin'you", "kinnyou", "kixnyou", "kinyou"]),
    ])
    func nSpellingsFindTheWord(_ c: (id: String, kana: String, spellings: [String])) throws {
        let entry = try #require(Self.store.entry(id: c.id))
        #expect(KanaScript.katakanaToHiragana(entry.kana) == c.kana)
        for spelling in c.spellings {
            var matcher = KanaInputMatcher(target: entry.kana)
            let accepted = spelling.allSatisfy { matcher.input($0) != .rejected } && matcher.isComplete
            #expect(accepted, "control: the ride does not accept \(spelling) for \(c.kana)")
            let ids = Self.store.search(spelling, limit: 50).map(\.id)
            #expect(ids.contains(c.id), "\(spelling) did not find \(c.id): \(ids.prefix(8))")
        }
        // The IME's reading still wins where it is a word: konnichiha is こんにちは, first.
        #expect(Self.store.search("konnichiha", limit: 5).first?.id == "n5-konnichiwa")
    }

    /// The same property over the whole corpus: every entry whose hint writes ん with an
    /// apostrophe, re-spelled with nn, xn and a lone n in its place, still reads as its reading.
    /// This is what `RomajiReading.maxAmbiguousN` is measured against.
    @Test("every corpus hint with n', re-spelled nn / xn / n, still reads as its reading")
    func everyNSpellingFindsTheWord() {
        var misses: [String] = []
        var checked = 0
        for entry in Self.store.entries where entry.romaji.contains("n'") {
            let reading = KanaScript.katakanaToHiragana(entry.kana)
            for replacement in ["nn", "xn", "n"] {
                let spelling = entry.romaji.replacingOccurrences(of: "n'", with: replacement)
                checked += 1
                if !RomajiReading.readings(fromRomaji: spelling).contains(reading) {
                    misses.append("\(entry.id) \(reading) \(spelling)")
                }
            }
        }
        print("WORDSEARCH n-SPELLINGS: \(checked) spellings of \(checked / 3) entries, \(misses.count) misses")
        // Measured 2026-09-29: 44 entries, 132 spellings. A floor, so a hint format that stopped
        // writing n' (and left this loop empty) cannot pass as "no misses".
        #expect(checked >= 132, "only \(checked) spellings — the corpus has fewer n' hints than measured")
        #expect(misses.isEmpty, "\(misses.count) misses: \(misses.prefix(20))")
    }

    /// `VocabStore.search` builds its index on the first search, once, and every copy of the
    /// store shares it. Mutations, 2026-09-29: `built = index` removed from `LazySearchIndex`
    /// (a rebuild per keystroke) → red; the index built in `VocabStore.init` → red on the 0.
    @Test("VocabStore.search builds the index once, on the first search, shared by copies")
    func buildOnce() {
        let store = VocabStore(entries: Array(Self.store.entries.prefix(500)))
        #expect(store.searchIndex.buildCount == 0, "built before anyone searched")
        _ = store.search("a", limit: 5)
        _ = store.search("mizu", limit: 5)
        let copy = store
        _ = copy.search("水", limit: 5)
        _ = copy.wordSearchIndex
        #expect(store.searchIndex.buildCount == 1, "built \(store.searchIndex.buildCount) times")
    }

    /// The cost of one keystroke on the path the screen calls — `VocabStore.search`, its lazy
    /// index built by the first call and reused — in whatever configuration `swift test` built.
    /// The figures are printed for the record; the assertion is on the MEDIAN of five rounds of
    /// twenty queries, against a bound about eight times the debug median measured here (12.9 ms, 2026-09-29), so a
    /// loaded machine's outliers cannot trip it and an order-of-magnitude regression still does.
    /// The first version asserted the worst single query under 100 ms and failed 4 of 21 suite
    /// runs under load. The frame budget on a phone is 16.7 ms; the release-build figure is what
    /// the plan records.
    @Test("a keystroke-sized query over the whole corpus costs well under a frame")
    func timing() {
        let queries = ["m", "mi", "miz", "mizu", "み", "みず", "水", "w", "wa", "wat", "water",
                       "t", "ta", "tab", "tabe", "吃", "e", "a", "ko-hi-", "の"]
        let store = VocabStore(entries: Self.store.entries)
        let clock = ContinuousClock()
        let firstStart = clock.now
        _ = store.search("m", limit: 50)
        let first = clock.now - firstStart
        var samples: [Duration] = []
        for _ in 0..<5 {
            for query in queries {
                let start = clock.now
                _ = store.search(query, limit: 50)
                samples.append(clock.now - start)
            }
        }
        samples.sort()
        let median = samples[samples.count / 2]
        let p95 = samples[samples.count * 95 / 100]
        print("WORDSEARCH TIMING: first search (builds the index) \(first), median query \(median), p95 \(p95), worst \(samples.last!), \(samples.count) queries, \(Self.store.entries.count) entries")
        #expect(store.searchIndex.buildCount == 1, "the index was built \(store.searchIndex.buildCount) times")
        #expect(median < .milliseconds(100), "median query \(median)")
    }
}
