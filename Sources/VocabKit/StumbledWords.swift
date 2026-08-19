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
    /// Hashable because the results screen identifies chips by the whole value. Keying a
    /// SwiftUI ForEach by the reading alone collides: 35 shipped sentences contain two
    /// spellings of one reading (五 and 語 both ご), and in dictation, where particles are
    /// kept, て beside 手 does it too. Duplicate ForEach ids render unpredictably, which on a
    /// list whose entire job is naming the right word is the worst place to have them.
    public struct Stumble: Hashable, Sendable {
        /// The word as written in the sentence — 潜入, not せんにゅう.
        public let surface: String
        /// Its reading, which is what the learner was actually typing.
        public let reading: String
        /// How many refused keystrokes landed inside it.
        public let refusals: Int
        /// The vocabulary entry this word IS, when the app can say which — and nil when it
        /// honestly cannot.
        ///
        /// This is the whole difference between a chip that can be read and a chip that can be
        /// acted on: saving a word, listing it, or riding it all need a `VocabEntry.id`, and a
        /// token is a surface and a reading. Nil is a normal, common and correct answer — the
        /// て of a te-form and the ます of a polite ending are not words anyone studies, and
        /// naming an entry for them would be worse than naming nothing.
        ///
        /// **Every consumer must branch on this rather than assume it.** A results screen that
        /// draws a star on a chip whose id is nil, or a "ride these" button that counts chips
        /// instead of ids, is the count-vs-run defect this project has now hit fourteen times.
        public let entryID: String?

        public init(surface: String, reading: String, refusals: Int, entryID: String?) {
            self.surface = surface
            self.reading = reading
            self.refusals = refusals
            self.entryID = entryID
        }
    }

    /// Which entry a stumbled token names, or nil when nothing can be said with certainty.
    ///
    /// Two paths, one rule: **the written form and the reading must both agree.**
    ///
    /// The first path is free. `from` has already resolved the event's `entryID` to the entry
    /// whose sentence this is, so when the stumbled token is the very word the sentence was
    /// written to teach, the id is in hand and no index is consulted. That matters beyond
    /// saving a dictionary lookup: it is the one path that stays correct if a future entry
    /// makes the pair index ambiguous, because this id is not inferred from the token at all.
    ///
    /// It still checks the reading. Requiring only the surface would name 生/せい for a token
    /// read なま whenever a sentence teaching the one contains the other — the same
    /// regress-to-the-common-answer failure the pair index exists to avoid, and not worth
    /// making an exception for: over the shipped corpus, dropping the reading check on this
    /// path would resolve 7 more tokens out of 41,222, every one of them a euphonic stem whose
    /// lemma is genuinely ambiguous.
    ///
    /// The second path is the store's pair index, and it needs one more thing than the index
    /// can give it.
    ///
    /// "Written and read exactly like this entry" is what the index guarantees, and v1.24
    /// shipped believing that was the same as "this IS that entry". It is not, and the review
    /// found the gap: an inflected form is written and read exactly like its homographic
    /// lemma. 本を読みます tokenizes as 本 / を / 読み / ます, and 読み matched the N3 noun 読み
    /// "reading" — so the chip for the word the learner was typing (読む) carried a star that
    /// saved a different word. 事件…進展があった gives あっ, and た alone matched the entry
    /// "past tense marker" in 2,695 sentences.
    ///
    /// So the pair path now also asks whether the token is a free word at all:
    ///
    /// * **Not if the entry is a bound morpheme** (`suf`) — た, 向け, the suffix sense of 中.
    /// * **Not if the next token is a verb/adjective inflection** — 読み+ます, あっ+た,
    ///   疲れ+て. See `JapaneseParticles.inflectionalTails`, and note what is deliberately NOT
    ///   in it.
    ///
    /// The taught-word path is exempt from both, because there the id is known rather than
    /// inferred: the sentence was written to teach that entry, so a stem of it still names it.
    ///
    /// - Parameter followedBy: surface of the next content token, or nil at the end of the
    ///   sentence. Required, not defaulted — a caller that cannot supply it is a caller that
    ///   cannot make this judgement, and defaulting to nil would silently restore the bug.
    static func entryID(for token: (surface: String, reading: String),
                        followedBy successor: String?,
                        taughtBy entry: VocabEntry,
                        in vocab: VocabStore) -> String? {
        guard !JapaneseParticles.single.contains(token.surface) else { return nil }
        if token.surface == entry.surface,
           KanaScript.katakanaToHiragana(token.reading)
             == KanaScript.katakanaToHiragana(entry.kana) {
            return entry.id
        }
        if let successor, JapaneseParticles.inflectionalTails.contains(successor) { return nil }
        guard let named = vocab.entry(surface: token.surface, reading: token.reading),
              Set(named.partsOfSpeech).isDisjoint(with: JapaneseParticles.boundPartsOfSpeech)
        else { return nil }
        return named.id
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
    public static func from(_ trace: MistakeTrace,
                            vocab: VocabStore = .shared,
                            minimumRefusals: Int = 2,
                            includesParticles: Bool = true) -> [Stumble] {
        var counts: [String: (surface: String, reading: String, id: String?, n: Int)] = [:]
        for event in trace.events {
            guard let id = event.entryID, let entry = vocab.entry(id: id),
                  // The event's target has to BE the sentence: in a word run `targetKana` is
                  // the word's own reading, and indexing exTokens with it would name a word
                  // at random. This is the check that keeps the two explanations apart.
                  entry.exampleKana == event.targetKana,
                  let located = entry.exampleTokenInContext(atReadingIndex: event.kanaIndex)
            else { continue }
            let token = located.token
            if !includesParticles, JapaneseParticles.single.contains(token.surface) { continue }
            let key = token.surface + "\u{1F}" + token.reading
            counts[key, default: (token.surface, token.reading,
                                  entryID(for: token, followedBy: located.next,
                                          taughtBy: entry, in: vocab), 0)].n += 1
        }
        return counts.values
            .filter { $0.n >= minimumRefusals }
            .map { Stumble(surface: $0.surface, reading: $0.reading,
                           refusals: $0.n, entryID: $0.id) }
            .sorted { ($0.refusals, $1.reading) > ($1.refusals, $0.reading) }
    }

    /// The ids a "ride these words" run would actually contain, for the chips in `stumbles`.
    ///
    /// **The one function both the number and the run must call.** Every instance of this
    /// project's recurring defect — fourteen of them — is a count and a run computed by
    /// different predicates that looked right in isolation, so the button's label and the
    /// button's action are not allowed to derive their answer separately here.
    ///
    /// - Parameters:
    ///   - stumbles: the chips as displayed. Pass the DISPLAYED slice, not the full list: a
    ///     screen showing six words and riding nine is the same broken promise as showing six
    ///     and riding four, and "what you see is what you ride" is the contract that is
    ///     actually checkable from a screenshot.
    ///   - resolves: the run builder's own predicate. `GameSession.makeWeak(ids:)` drops ids
    ///     that no longer name an entry, so this must be the store's `resolvesID` and not a
    ///     hand-written copy of it — the withdrawn-entry leak that inflated four counts for
    ///     three releases was exactly a hand-written copy going missing.
    ///
    /// Duplicates are impossible by construction (chips are keyed by surface+reading and the
    /// pair index is injective), but the order is preserved so the ride follows the screen.
    public static func rideableIDs(in stumbles: [Stumble],
                                   resolves: (String) -> Bool) -> [String] {
        var seen = Set<String>()
        return stumbles.compactMap(\.entryID)
            .filter { resolves($0) && seen.insert($0).inserted }
    }
}
