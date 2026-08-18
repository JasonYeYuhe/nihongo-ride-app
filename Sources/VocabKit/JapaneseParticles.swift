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
}
