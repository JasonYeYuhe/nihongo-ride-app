import Testing
@testable import RomajiKana

@Suite("I. Katakana targets")
struct KatakanaTests {
    @Test("katakana words are typeable (normalized to hiragana; ー via '-')", arguments: [
        ("terebi", "テレビ"),
        ("ra-men", "ラーメン"),
        ("ko-hi-", "コーヒー"),
        ("ko-ra", "コーラ"),
        ("pasokon", "パソコン"),
        ("naifu", "ナイフ"),
        ("ge-mu", "ゲーム"),
        ("nyu-su", "ニュース"),     // youon + ー
    ])
    func accepts(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target), "‘\(c.input)’ should type ‘\(c.target)’")
    }

    @Test("foreign-sound digraphs in loanwords", arguments: [
        ("famikon", "ファミコン"),
        ("chekku", "チェック"),
        ("jetto", "ジェット"),
        ("pa-thi-", "パーティー"),
        ("dhizuni-", "ディズニー"),
    ])
    func foreignDigraphs(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target), "‘\(c.input)’ should type ‘\(c.target)’")
    }

    @Test("romanizer hint for katakana (ー → '-')", arguments: [
        ("テレビ", "terebi"),
        ("ラーメン", "ra-men"),
        ("コーヒー", "ko-hi-"),
        ("ニュース", "nyu-su"),
    ])
    func hints(_ c: (kana: String, romaji: String)) {
        #expect(KanaRomanizer.romaji(for: c.kana) == c.romaji)
    }

    // Regression (Codex review): small katakana ヵ/ヶ must stay katakana so the
    // table's xka/xke producers apply — not be normalized to producer-less ゕ/ゖ.
    @Test("small katakana ヵ / ヶ remain typeable", arguments: [
        ("xka", "ヵ"), ("xke", "ヶ"), ("lka", "ヵ"), ("lke", "ヶ"),
    ])
    func smallKatakana(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target), "‘\(c.input)’ should type ‘\(c.target)’")
    }
}
