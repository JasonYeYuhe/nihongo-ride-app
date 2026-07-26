import Foundation
import RomajiKana

/// A named reason a learner's keystroke was refused, and what to tell them about it.
///
/// Membership is decided by one rule: **the engine must actually reject it.** Two earlier
/// drafts of this list failed that rule — kunrei-shiki (`si`/`ti`/`tu`) and lenient single-`n`
/// (`renai` → れんあい) are both ACCEPTED input, and diagnosing them would have told learners
/// they were wrong when they were not. Both were written from intuition; the matcher's test
/// contract is the spec, and `Tests/RomajiKanaTests/MistakeTaxonomyTests.swift` now pins the
/// accepted half as well as the rejected half so it cannot happen a third time.
public enum TypingPattern: String, CaseIterable, Sendable {
    /// は / へ / を typed the way they SOUND (`wa`, `e`, `o`) rather than the way they are
    /// written. こんにちは is the first passage in the corpus and 152 of 233 contain は.
    case particleSpelling
    /// A doubled consonant was typed single: `ite` for いって.
    case sokuon
    /// A small ゃゅょ typed as a full-size one: `kiyaku` for きゃく.
    case smallYa
    /// Hepburn's `m` before b/p: `shimbun` for しんぶん. Real IMEs refuse it too.
    case hepburnM
    /// The key is not on any path to this word, and nothing above explains it.
    case unknown

    /// A stable label for the UI to localize. Deliberately not user-facing text — the strings
    /// live with the views, and this type stays free of presentation.
    public var id: String { rawValue }
}

/// One diagnosed pattern with the evidence behind it.
public struct Diagnosis: Equatable, Sendable {
    public let pattern: TypingPattern
    /// How many refused keystrokes matched.
    public let occurrences: Int
    /// How many DISTINCT words it happened on. The important number: one `ite` for いって is
    /// as consistent with a slipped finger as with a misunderstanding, and telling somebody
    /// they have a sokuon problem on that basis is worse than saying nothing.
    public let distinctWords: Int
    /// The clearest single instance, for the character-level replay.
    public let example: MistakeEvent

    public init(pattern: TypingPattern, occurrences: Int, distinctWords: Int, example: MistakeEvent) {
        self.pattern = pattern
        self.occurrences = occurrences
        self.distinctWords = distinctWords
        self.example = example
    }

    /// Whether this is worth telling the learner about as a PATTERN.
    ///
    /// Two distinct words, minimum. A run has ten to twenty words, so this stays reachable
    /// while refusing to promote a single slip into a diagnosis.
    public var isRecurring: Bool { distinctWords >= 2 }
}
