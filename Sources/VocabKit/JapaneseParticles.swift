import Foundation

/// The single-kana grammatical particles, in one place because two different rules need
/// them and one rule written twice drifts.
///
/// This project has already paid for that three times over — a Swift test and a Python gate
/// disagreeing about punctuation, about -ずる stems, about POS tags — so the set that decides
/// whether a chip is *shown* (`StumbledWords`, where dictation keeps particles and the
/// sentence screen drops them) and the set that decides whether a chip can be *resolved to a
/// word* (`VocabStore.entry(surface:reading:)`, where it never can, in either mode) are
/// deliberately the same value rather than two literals that agree today.
public enum JapaneseParticles {

    /// Matched on the SURFACE, never on the reading. A content word that merely reads like a
    /// particle — 歯 for は, 戸 for と, 手 for て — is written in kanji in the sentence and so
    /// never matches, while a real particle is written as the bare kana by definition.
    public static let single: Set<String> = ["を", "は", "へ", "が", "に", "で", "と",
                                             "も", "の", "や", "ね", "よ", "か"]

    /// Tails that only ever attach to a verb or adjective stem — never the start of a word.
    ///
    /// Their job here is to tell a free word from a bound stem, which is the one thing a
    /// token cannot say about itself. Sudachi's `SplitMode.C` splits 読みます into 読み + ます,
    /// and 読み is written and read exactly like the N3 noun 読み "reading"; the pair index
    /// matches it with full confidence and the results screen offers to save the wrong word.
    /// The successor is the evidence that settles it.
    ///
    /// **だ, です, で and ん are deliberately absent.** They follow NOUNS perfectly well, and
    /// an earlier draft that included them blocked 公園, 大学, 授業, 好き, 予定 — measured, and
    /// exactly the words the feature exists to offer. で is worse than useless here because it
    /// is also the commonest particle. The list is the closed set of verb/adjective inflection
    /// only, and it is measured: it costs 12.8% of resolutions and what it removes is 2,695
    /// past-tense た plus the 連用形 stems that homograph with nouns — 教え, 調べ, 疲れ, 読み,
    /// 合わせ, 遅れ, 切れ, 始まり, 帰り, 作り. (v1.24.)
    public static let inflectionalTails: Set<String> = [
        "ます", "まし", "ませ", "ましょ", "た", "て", "ない", "なく", "なかっ", "ず",
        "れ", "られ", "せ", "させ", "たい", "たかっ", "よう", "ば", "ください"
    ]

    /// Part-of-speech tags marking an entry that is not a free-standing word.
    ///
    /// `suf` is the one that matters: the corpus has an entry for た, "past tense marker",
    /// and every ta-form in 2,695 sentences tokenizes to it. A learner who stumbles on a past
    /// tense ending should not be offered a vocabulary card asking them to type "ta".
    public static let boundPartsOfSpeech: Set<String> = ["suf"]
}
