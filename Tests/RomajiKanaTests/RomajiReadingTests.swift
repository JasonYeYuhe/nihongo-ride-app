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

    @Test("case does not matter")
    func caseInsensitive() {
        #expect(RomajiReading.hiragana(fromRomaji: "MIZU") == "みず")
        #expect(RomajiReading.hiragana(fromRomaji: "Konnichiha") == "こんにちは")
    }

    /// Nil, never a half-reading: "みz" is not a word anyone meant, and English that is not romaji
    /// must reach the gloss search alone.
    @Test("anything that is not romaji all the way through has no reading", arguments: [
        "", "miz", "water", "mi zu", "mizu1", "xyz", "'", "q", "mb", "水", "みず", "a,b", "z.",
    ])
    func notRomaji(_ text: String) {
        #expect(RomajiReading.hiragana(fromRomaji: text) == nil, "\(text) → \(String(describing: RomajiReading.hiragana(fromRomaji: text)))")
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
    }
}
