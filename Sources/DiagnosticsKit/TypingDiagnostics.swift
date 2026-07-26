import Foundation
import RomajiKana

/// Turns a run's refused keystrokes into named patterns.
///
/// Pure and deterministic: same trace in, same diagnoses out, no clock, no model, no state.
/// Everything it needs is in the event — what was typed, what was refused, what would have
/// been accepted, and where in the word it happened.
///
/// This is the part of the "Coach" that carries the value, and it is the part a language model
/// is worst at: asked to classify four unambiguous cases from a summary, the on-device model
/// got two right and advised practising kanji calligraphy for a romaji problem. The app owns
/// the romaji tables and every keystroke, so it can simply be correct.
public enum TypingDiagnostics {

    /// Kana that are written differently from how they sound in modern Japanese, with the
    /// romaji a learner types when they go by ear.
    ///
    /// This is the highest-value entry in the taxonomy and it is not a "mistake" in the sense
    /// of carelessness — it is a rule nobody has told them yet.
    static let phoneticTraps: [Character: Set<Character>] = [
        "は": ["w"],   // konnichiwa → こんにちは refuses at the w
        "へ": ["e"],
        "を": ["o"],
    ]

    /// Classifies one refused keystroke.
    ///
    /// Order matters: the specific traps are tested before the structural ones, because a
    /// refused `w` on は is a particle-spelling problem and nothing else, whereas a refused
    /// consonant could be several things.
    public static func classify(_ event: MistakeEvent) -> TypingPattern {
        let rejected = Character(event.rejected.lowercased())

        if let kana = event.kanaAtMistake {
            // は/へ/を typed as they sound.
            if let sounded = phoneticTraps[kana], sounded.contains(rejected) {
                return .particleSpelling
            }
            // A small ゃゅょ approached as two kana. What the engine actually does, which is
            // not what I first assumed: for きゃく it ACCEPTS `ki` (committing き), leaving the
            // learner standing on ゃ, where the only remaining spellings are the explicit
            // small-kana ones — expected is exactly ["l", "x"]. So the refusal is the `y` of
            // the `ya` they were about to type, not the `i` of `ki`. I guessed `i`; the test
            // that drives a real matcher caught it.
            if isSmallYaKana(kana), rejected == "y" {
                return .smallYa
            }
            // っ skipped: the learner is standing on the sokuon and typed the consonant that
            // begins the NEXT kana instead of doubling it. The engine expects that same
            // consonant, so this is only a mistake in the sense that they typed one where two
            // were needed — which the expected set cannot distinguish. What identifies it is
            // that the sokuon is where they are and the key they pressed is a vowel.
            if kana == "っ", isVowel(rejected) {
                return .sokuon
            }
            // Hepburn m before b/p: standing on ん, next kana starts with b or p, typed m.
            if kana == "ん", rejected == "m" {
                return .hepburnM
            }
        }
        return .unknown
    }

    /// Groups a whole run's refusals into diagnoses, most recurrent first.
    ///
    /// `unknown` is returned like any other pattern rather than dropped: a coach that silently
    /// discards what it cannot explain will confidently report "your only problem is sokuon"
    /// to somebody whose real problem it has no name for.
    public static func diagnose(_ trace: MistakeTrace) -> [Diagnosis] {
        var byPattern: [TypingPattern: [MistakeEvent]] = [:]
        for event in trace.events {
            byPattern[classify(event), default: []].append(event)
        }
        return byPattern.compactMap { pattern, events -> Diagnosis? in
            guard let example = events.first else { return nil }
            let words = Set(events.map(\.targetKana))
            return Diagnosis(pattern: pattern, occurrences: events.count,
                             distinctWords: words.count, example: example)
        }
        .sorted {
            // Distinct words first (that is what makes a pattern real), then raw count, then
            // the pattern name so the order never depends on dictionary iteration.
            ($0.distinctWords, $0.occurrences, $1.pattern.rawValue)
                > ($1.distinctWords, $1.occurrences, $0.pattern.rawValue)
        }
    }

    /// The single thing worth saying after a run, if anything is.
    ///
    /// Recurring patterns only, and never `unknown` — "you made some mistakes we cannot
    /// explain" helps nobody.
    public static func headline(_ trace: MistakeTrace) -> Diagnosis? {
        diagnose(trace).first { $0.isRecurring && $0.pattern != .unknown }
    }

    // MARK: -

    private static let smallYaKana: Set<Character> = ["ゃ", "ゅ", "ょ", "ャ", "ュ", "ョ"]
    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]

    static func isSmallYaKana(_ c: Character) -> Bool { smallYaKana.contains(c) }
    static func isVowel(_ c: Character) -> Bool { vowels.contains(c) }
}
