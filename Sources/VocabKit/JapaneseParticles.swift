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
    /// A SECOND line, behind `VocabStore.isInflectedFormOfAVerb`, which is derived and does the
    /// bulk of the work. This list covers what derivation cannot see: euphonic stems whose
    /// dictionary form is not reachable by the 連用形 rule (あっ for ある), adjective stems
    /// (よく for 良い), and verbs the corpus happens not to contain (楽しみ, since 楽しむ is
    /// absent). Measured residue without it: 66 tokens, of which about 39 are genuinely wrong.
    ///
    /// **Every member of this list is asserted to occur in the shipped corpus.** The first
    /// version was written from intuition and contained two forms that appear zero times —
    /// `ましょ` and `させ`, because Sudachi emits `ましょう` and `させる` — while the forms that
    /// do occur were missing. It measured what it blocked, which looked like validation and was
    /// not, and 休みましょう went on offering the noun 休み to a learner typing 休む. The test
    /// `everyInflectionalTailOccurs` is what makes this list evidence rather than a guess.
    ///
    /// **だ, です, で and ん are deliberately absent.** They follow NOUNS perfectly well, and an
    /// early draft that included them blocked 公園, 大学, 授業, 好き, 予定 — measured, and
    /// exactly the words the feature exists to offer.
    public static let inflectionalTails: Set<String> = [
        "ます", "まし", "ませ", "ましょう", "た", "て", "ない", "なく", "なかっ", "ず",
        "れ", "られ", "られる", "せ", "たい", "たかっ", "よう", "ば", "ください",
        "ながら", "やすい", "にくい", "すぎ", "そう", "始め", "終え", "終わっ", "切っ",
    ]

    /// Part-of-speech tags marking an entry that is not a free-standing word.
    ///
    /// `suf` is the one that matters: the corpus has an entry for た, "past tense marker",
    /// and every ta-form in 2,695 sentences tokenizes to it. A learner who stumbles on a past
    /// tense ending should not be offered a vocabulary card asking them to type "ta".
    public static let boundPartsOfSpeech: Set<String> = ["suf"]
}
