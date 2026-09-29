import Testing
@testable import RomajiKana

/// v1.35 §B6 — blind romaji → hiragana, for the Word Lists search box.
///
/// The corpus-wide property (every entry's own romaji hint reads back as its reading) lives in
/// `VocabKitTests.WordSearchTests`, where the corpus is; this file pins the rules one by one.
@Suite("B6: RomajiReading, romaji to hiragana without a target")
struct RomajiReadingTests {

    @Test("romaji a learner types reads as the hiragana it spells", arguments: [
        ("mizu", "みず"),
        ("gakkou", "がっこう"),          // sokuon from the table's pending rule
        ("matcha", "まっちゃ"),
        ("kanji", "かんじ"),
        ("kannji", "かんじ"),            // nn before a consonant: the table's ん
        ("hon", "ほん"),                 // a final n
        ("kin'youbi", "きんようび"),      // n' before y
        ("ko-hi-", "こーひー"),           // - is the long-vowel mark
        ("shi", "し"), ("si", "し"),      // both spellings the engine accepts
        ("tsu", "つ"), ("tu", "つ"),
        ("thi", "てぃ"),
        ("vu", "ゔ"),
        ("a", "あ"),
    ])
    func reads(_ c: (romaji: String, kana: String)) {
        #expect(RomajiReading.hiragana(fromRomaji: c.romaji) == c.kana, "\(c.romaji)")
    }

    /// The one rule that is not the table's. Mutation, 2026-09-29: deleting the `nn` + vowel
    /// branch turns this red — こんいちは, おんあ, さんえん — with `caseInsensitive` (Konnichiha),
    /// and nothing in `reads` above; in VocabKit it also reddens the corpus-wide hint round trip.
    @Test("nn before a vowel or y is ん and then the n-row, not ん and a bare vowel", arguments: [
        ("konnichiha", "こんにちは"),
        ("onna", "おんな"),
        ("sannen", "さんねん"),
        ("minna", "みんな"),
        ("konnyaku", "こんにゃく"),
    ])
    func doubleN(_ c: (romaji: String, kana: String)) {
        #expect(RomajiReading.hiragana(fromRomaji: c.romaji) == c.kana, "\(c.romaji)")
    }

    /// The ride accepts `n'`, `nn`, `xn` and a lone `n` for ん before a vowel or `y` — it knows
    /// the word. Search does not, so each spelling must yield the ん reading among its readings,
    /// and the IME's reading stays first. Mutations, 2026-09-29: dropping the `nn` → ん + bare
    /// vowel branch → red on tanni, gennin, kinnyou; dropping the lone-`n` branch → red on tani,
    /// genin, kinyou; setting `maxAmbiguousN` to 0 → red on both.
    @Test("every ん spelling the ride accepts yields the ん reading", arguments: [
        ("tan'i", "たんい"), ("tanni", "たんい"), ("taxni", "たんい"), ("tani", "たんい"),
        ("gen'in", "げんいん"), ("gennin", "げんいん"), ("gexnin", "げんいん"), ("genin", "げんいん"),
        ("kin'you", "きんよう"), ("kinnyou", "きんよう"), ("kixnyou", "きんよう"), ("kinyou", "きんよう"),
    ])
    func everyNSpelling(_ c: (romaji: String, kana: String)) {
        #expect(RomajiReading.readings(fromRomaji: c.romaji).contains(c.kana),
                "\(c.romaji) → \(RomajiReading.readings(fromRomaji: c.romaji))")
    }

    /// The first reading is the IME's, so the corpus-wide hint round trip and konnichiha keep
    /// their answers; the others follow, with no repeats.
    @Test("the IME's reading comes first, then the other ん readings")
    func imeReadingFirst() {
        #expect(RomajiReading.readings(fromRomaji: "konnichiha") == ["こんにちは", "こんいちは"])
        #expect(RomajiReading.hiragana(fromRomaji: "konnichiha") == "こんにちは")
        #expect(RomajiReading.readings(fromRomaji: "tanni") == ["たんに", "たんい"])
        #expect(RomajiReading.readings(fromRomaji: "tani") == ["たに", "たんい"])
        #expect(RomajiReading.readings(fromRomaji: "tan'i") == ["たんい"], "the apostrophe is not ambiguous")
        #expect(RomajiReading.readings(fromRomaji: "taxni") == ["たんい"], "neither is xn")
        #expect(RomajiReading.readings(fromRomaji: "mizu") == ["みず"])
        #expect(RomajiReading.readings(fromRomaji: "kannji") == ["かんじ"], "nn before a consonant is the table's ん")
        let many = RomajiReading.readings(fromRomaji: "nanininuneno")
        #expect(many.count == Set(many).count, "a reading repeated: \(many)")
    }

    /// The branching is bounded: a long run of ambiguous n's ending in a letter that reads as
    /// nothing answers promptly and empty, and a run that reads gives at most 2^maxAmbiguousN.
    @Test("ambiguous n's branch at most maxAmbiguousN times")
    func branchesAreBounded() {
        let clock = ContinuousClock()
        let start = clock.now
        #expect(RomajiReading.readings(fromRomaji: String(repeating: "na", count: 40) + "q").isEmpty)
        let spent = clock.now - start
        print("ROMAJIREADING 40 ambiguous n's + q: \(spent)")
        #expect(spent < .seconds(1), "\(spent) — the branching is not bounded")
        let readings = RomajiReading.readings(fromRomaji: String(repeating: "na", count: 10))
        #expect(readings.count == 1 << RomajiReading.maxAmbiguousN)
        #expect(readings.first == String(repeating: "な", count: 10))
    }

    @Test("case does not matter")
    func caseInsensitive() {
        #expect(RomajiReading.hiragana(fromRomaji: "MIZU") == "みず")
        #expect(RomajiReading.hiragana(fromRomaji: "Konnichiha") == "こんにちは")
    }

    /// Nil, never a half-reading: "みz" is not a word anyone meant, and English that is not romaji
    /// must reach the gloss search alone.
    @Test("anything that is not romaji all the way through has no reading", arguments: [
        "", "miz", "water", "mi zu", "mizu1", "xyz", "'", "q", "mb", "水", "みず", "a,b", "z.", "zh", "www",
    ])
    func notRomaji(_ text: String) {
        #expect(RomajiReading.hiragana(fromRomaji: text) == nil, "\(text) → \(String(describing: RomajiReading.hiragana(fromRomaji: text)))")
        #expect(RomajiReading.readings(fromRomaji: text).isEmpty, "\(text) → \(RomajiReading.readings(fromRomaji: text))")
    }

    /// Control for `notRomaji`: the Mozc table DOES map `,` to 、 and `z.` to …, so the two
    /// rows above are refused by the letters-only rule, not by the table lacking them. Without
    /// that rule a query of "," would read as 、 and match nothing, silently.
    @Test("control: the table itself has symbol keys the letters-only rule is there to refuse")
    func tableHasSymbolKeys() {
        let table = RomajiKanaTable.shared
        #expect(table.producerByRomaji[","]?.output == "、")
        #expect(table.producerByRomaji["z."] != nil)
        #expect(table.producerByRomaji["nn"]?.output == "ん" && table.producerByRomaji["n"]?.output == "ん")
        // The ん keys the ride accepts, which `everyNSpelling` spells; and the pending the header
        // names as the longest — `tch` leaves two letters, `www` leaves two and outputs a letter.
        #expect(table.producerByRomaji["n'"]?.output == "ん" && table.producerByRomaji["xn"]?.output == "ん")
        #expect(table.producerByRomaji["tch"]?.pending == "ch" && table.producerByRomaji["www"]?.pending == "ww")
        #expect(table.producerByRomaji["zh"]?.output == "←" && table.producerByRomaji["www"]?.output == "w")
        #expect(table.producerByRomaji.values.map(\.pending.count).max() == 2)
    }
}
