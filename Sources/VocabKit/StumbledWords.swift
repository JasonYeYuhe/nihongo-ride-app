import Foundation
import RomajiKana

/// Which WORDS a learner stumbled on during a sentence or dictation run.
///
/// The app has two ways of explaining a mistake and until now only one of them worked on
/// sentences. `DiagnosticsKit` classifies a refused keystroke by its typing MECHANICS — the
/// topic particle は written `wa`, a missed sokuon, a small ゃ — and the coach drills the
/// rule. That is the right answer when the learner knows the word and mistyped it.
///
/// It is the wrong answer, and `DiagnosticsKit` honestly returns `.unknown`, when the
/// learner simply did not know or did not hear the word. In a word run that hardly matters:
/// the card IS the word, so the results screen can list it. In a sentence run the target is
/// twenty kana of prose, so the app could say "four mistakes" and nothing about where — and
/// in dictation, where the sentence is heard rather than seen, "where" is the entire
/// diagnosis. A learner who could not make out 潜入 needs to be told 潜入, not told that 43%
/// of their refusals were unclassifiable.
///
/// The data has been sufficient since v1.18 and nothing read it: a `MistakeEvent` carries
/// the position in the sentence's reading, and `exTokens` readings concatenate to that
/// reading exactly.
public enum StumbledWords {

    /// One word the learner was refused on, and how often.
    public struct Stumble: Equatable, Sendable {
        /// The word as written in the sentence — 潜入, not せんにゅう.
        public let surface: String
        /// Its reading, which is what the learner was actually typing.
        public let reading: String
        /// How many refused keystrokes landed inside it.
        public let refusals: Int
    }

    /// The words `trace`'s refusals landed in, most-refused first.
    ///
    /// - Parameters:
    ///   - trace: the run's refused keystrokes. Only events carrying an `entryID` that
    ///     resolves to a SENTENCE are considered — a word run's mistakes already name their
    ///     own word, and passages have no id at all.
    ///   - vocab: the store to resolve ids against.
    ///   - minimumRefusals: words refused fewer times than this are dropped. One slip inside
    ///     a word is a typo; the point of this list is the words that actually stopped the
    ///     learner, and a list of every word they ever fumbled is a list nobody reads.
    ///   - includesParticles: whether a single-kana particle can be named. The sentence screen
    ///     passes `false` and dictation `true`, because the same を means two different things.
    ///     On screen the learner can SEE it, so a refusal there is the wa/ha spelling trap —
    ///     which the coach already explains with a rule one line above, making this list a
    ///     duplicate that relabels a spelling slip as a word they do not know. In dictation
    ///     nothing is on screen, so hearing の and typing に is a listening result, and one of
    ///     the more useful things this list can report.
    ///
    /// Ties break on the reading so the order is stable — a results screen that reshuffles
    /// between two identical runs looks broken.
    /// Single-kana grammatical particles, which are a stumble in one mode and noise in the
    /// other. Matched on the SURFACE, so a content word that merely reads like one — 歯 for は,
    /// 戸 for と — is written in kanji in the sentence and never matches.
    private static let particles: Set<String> = ["を", "は", "へ", "が", "に", "で", "と",
                                                 "も", "の", "や", "ね", "よ", "か"]

    public static func from(_ trace: MistakeTrace,
                            vocab: VocabStore = .shared,
                            minimumRefusals: Int = 2,
                            includesParticles: Bool = true) -> [Stumble] {
        var counts: [String: (surface: String, reading: String, n: Int)] = [:]
        for event in trace.events {
            guard let id = event.entryID, let entry = vocab.entry(id: id),
                  // The event's target has to BE the sentence: in a word run `targetKana` is
                  // the word's own reading, and indexing exTokens with it would name a word
                  // at random. This is the check that keeps the two explanations apart.
                  entry.exampleKana == event.targetKana,
                  let token = entry.exampleToken(atReadingIndex: event.kanaIndex)
            else { continue }
            if !includesParticles, Self.particles.contains(token.surface) { continue }
            let key = token.surface + "\u{1F}" + token.reading
            counts[key, default: (token.surface, token.reading, 0)].n += 1
        }
        return counts.values
            .filter { $0.n >= minimumRefusals }
            .map { Stumble(surface: $0.surface, reading: $0.reading, refusals: $0.n) }
            .sorted { ($0.refusals, $1.reading) > ($1.refusals, $0.reading) }
    }
}
