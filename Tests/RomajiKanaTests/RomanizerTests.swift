import Testing
@testable import RomajiKana

@Suite("H. KanaRomanizer hints")
struct RomanizerTests {
    @Test("Hepburn-style romaji hint", arguments: [
        ("にほんご", "nihongo"),
        ("がっこう", "gakkou"),
        ("しんぶん", "shinbun"),
        ("とうきょう", "toukyou"),
        ("でんしゃ", "densha"),
        ("きって", "kitte"),
        ("れんあい", "ren'ai"),       // ん before a vowel → apostrophe
        ("きんようび", "kin'youbi"),  // ん before y → apostrophe
        ("せんせい", "sensei"),
        ("し", "shi"),
        ("つ", "tsu"),
        ("ちゃ", "cha"),
        ("みんな", "minna"),
    ])
    func hint(_ c: (kana: String, expected: String)) {
        #expect(KanaRomanizer.romaji(for: c.kana) == c.expected,
                "romaji(for: ‘\(c.kana)’) should be ‘\(c.expected)’")
    }

    /// Property: a hint must always be a sequence the matcher accepts for that word.
    /// This ties the romanizer and the matcher together — the displayed hint is
    /// guaranteed to be typeable.
    @Test("every generated hint is itself a valid way to type the word", arguments: [
        "にほんご", "がっこう", "しんぶん", "とうきょう", "でんしゃ", "きって",
        "れんあい", "きんようび", "せんせい", "みんな", "ざっし", "まっちゃ",
        "しんかんせん", "おおきい", "ねえ", "こっち",
    ])
    func hintIsTypable(_ word: String) {
        let hint = KanaRomanizer.romaji(for: word)
        #expect(typesOut(hint, as: word), "hint ‘\(hint)’ should type ‘\(word)’")
    }
}
