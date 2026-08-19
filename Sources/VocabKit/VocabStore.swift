import Foundation
import RomajiKana

/// In-memory vocabulary repository, loaded from a bundled word pack.
public struct VocabStore: Sendable {
    public let entries: [VocabEntry]
    /// Id lookup index. `entry(id:)` used to be a linear scan of 7,072 entries, which was
    /// fine while its callers were one-shot; it is not fine now that pool counts are read
    /// per menu render and per id in a saved list. First-wins on a duplicate id, matching
    /// the `entries.first` it replaces (the shipped corpus has none).
    private let byID: [String: VocabEntry]

    /// A written form and a reading that must BOTH match, keyed together on purpose.
    private struct WrittenAndRead: Hashable {
        let surface: String
        /// Katakana folded to hiragana — see `entry(surface:reading:)`.
        let reading: String
    }

    /// Written form + reading → the one entry that is written *and* read that way.
    ///
    /// The index is a pair because neither half alone is safe, and both unsafe versions were
    /// measured against the shipped corpus before this one was written:
    ///
    /// * **By surface alone**, 1,362 of the corpus's tokens hit an entry whose reading
    ///   disagrees with the token's — that is 100% of the surface-only hits, which is a
    ///   tautology rather than a coincidence: a token whose reading agreed would already have
    ///   matched the pair. It names 二 for ふた, 来 for き, 時 for じ, 箱 for ばこ. Resolving an
    ///   ambiguity by regressing to the common answer is this project's oldest failure and has
    ///   already cost it two releases.
    /// * **By reading alone** it is worse, and worse in the direction that looks safest. A
    ///   kana-only token has no written form that could contradict a reading match, so it
    ///   reads like the safe case; in Japanese a kana-only token is usually a function
    ///   morpheme, and the reading index always finds some rare noun spelled that way.
    ///   Measured over the shipped sentences: て→手 2,130 times, し→死 1,202, ます→増す 655,
    ///   な→名 563, から→空 297. Offering to save 死 because the learner stumbled on the し of
    ///   します is the ない/無い trap with three orders of magnitude more instances.
    ///
    /// Requiring both halves to agree resolves 58.4% of the corpus's content tokens before the
    /// free-word checks in `StumbledWords.entryID` narrow it to 50.7% (72.2% of tokens
    /// containing kanji), and leaves a residue that is almost entirely function morphemes,
    /// which is the correct answer for them.
    ///
    /// **It does not make the answer right, and an earlier version of this comment said it
    /// did.** "Can only name an entry written AND read exactly the way the token is" is true
    /// and is a weaker property than "names the word the learner stumbled on": an inflected
    /// form is written and read exactly like its homographic lemma. 読み matched the noun
    /// 読み "reading" in 本を読みます, and た matched "past tense marker" in 2,695 sentences.
    /// This index cannot tell them apart, because nothing about a token in isolation can —
    /// see `StumbledWords.entryID`, which asks the surrounding sentence.
    ///
    /// Keys claimed by more than one entry are DROPPED rather than won by the first: an
    /// ambiguous key has no right answer, and this whole index exists because guessing one is
    /// the failure mode. The shipped corpus has no such key, and that is enforced here rather
    /// than asserted in this sentence, so a future entry that creates one costs a chip its
    /// star instead of pointing it at the wrong word.
    private let bySurfaceAndReading: [WrittenAndRead: VocabEntry]

    /// Every conjugable verb in the store, keyed the same way.
    ///
    /// Exists so `isInflectedFormOfAVerb` can be DERIVED from the corpus instead of listed by
    /// hand — see there for why that distinction cost a release candidate.
    private let verbs: Set<WrittenAndRead>

    /// The shared store, loaded once from the bundled N5 starter pack.
    public static let shared = VocabStore.loadBundled()

    public init(entries: [VocabEntry]) {
        self.entries = entries
        self.byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var pairs: [WrittenAndRead: VocabEntry] = [:]
        var ambiguous: Set<WrittenAndRead> = []
        for entry in entries {
            let key = WrittenAndRead(surface: entry.surface,
                                     reading: KanaScript.katakanaToHiragana(entry.kana))
            if pairs.updateValue(entry, forKey: key) != nil { ambiguous.insert(key) }
        }
        for key in ambiguous { pairs.removeValue(forKey: key) }
        self.bySurfaceAndReading = pairs
        self.verbs = Set(entries.lazy
            .filter { $0.partsOfSpeech.contains { $0 == "v" || $0.hasPrefix("v") } }
            .map { WrittenAndRead(surface: $0.surface,
                                  reading: KanaScript.katakanaToHiragana($0.kana)) })
    }

    /// The い-row kana a godan 連用形 ends in, and the う-row kana its dictionary form ends in.
    private static let renyoToDictionary: [Character: Character] = [
        "い": "う", "き": "く", "ぎ": "ぐ", "し": "す", "ち": "つ",
        "に": "ぬ", "ひ": "ふ", "び": "ぶ", "み": "む", "り": "る",
    ]

    /// Whether this written form and reading could equally be the 連用形 of a verb this store
    /// contains — 休み is the noun "rest" and the stem of 休む, and nothing about the token says
    /// which.
    ///
    /// **This replaces a hand-written list, and the reason is worth keeping.** v1.24 first fixed
    /// the 読み/読む class by listing the auxiliaries a stem can be followed by. The list was
    /// written from linguistic intuition and then validated by measuring what it BLOCKED — which
    /// looked convincing (12.8% of resolutions) and was not evidence, because nobody measured
    /// whether its members occur. Two of them never appear in the corpus at all (`ましょ`,
    /// `させ`: Sudachi emits the long forms `ましょう`, `させる`), and the forms that do occur
    /// were missing — so 少し疲れたのでここで休みましょう still offered the noun 休み for a
    /// learner typing 休む, on beginner-level content, in the release that claimed to have fixed
    /// exactly that. Found by the completeness pass of the pre-submission review.
    ///
    /// Derived, there is no list to be wrong: a token is ambiguous if replacing its final い-row
    /// kana with the う-row one, or appending る, names a verb this store holds. Measured over
    /// the shipped corpus it blocks 353 tokens, all of them genuine noun/連用形 homographs —
    /// 休み, 読み, 疲れ, 教え, 調べ, 願い, 帰り, 終わり, 遊び, 助け, 考え, 合わせ.
    ///
    /// It can only see verbs the corpus contains, which is a coverage limit and not a wrong
    /// answer: 楽しむ is absent, so 楽しみ is not caught this way.
    public func isInflectedFormOfAVerb(surface: String, reading: String) -> Bool {
        let folded = KanaScript.katakanaToHiragana(reading)
        guard let lastSurface = surface.last, let lastReading = folded.last else { return false }
        if let dictionarySurface = Self.renyoToDictionary[lastSurface],
           let dictionaryReading = Self.renyoToDictionary[lastReading],
           verbs.contains(WrittenAndRead(surface: String(surface.dropLast()) + String(dictionarySurface),
                                         reading: String(folded.dropLast()) + String(dictionaryReading))) {
            return true
        }
        return verbs.contains(WrittenAndRead(surface: surface + "る", reading: folded + "る"))
    }

    /// The entry written `surface` and read `reading`, when exactly one entry is both.
    ///
    /// This is the reverse of `entry(id:)` — the lookup that turns a word the learner was
    /// refused on back into something they can save, list or ride. See
    /// ``bySurfaceAndReading`` for why it insists on both halves.
    ///
    /// Readings are compared with katakana folded to hiragana, using the same `KanaScript`
    /// the typing matcher folds with rather than a second copy of the rule: `exTokens` writes
    /// a loanword's reading in hiragana while the entry stores katakana, so チーム and ちーむ
    /// are one word and 33 shipped sentences say so.
    ///
    /// **A grammatical particle never resolves**, whatever the corpus happens to contain.
    /// The shipped corpus has exactly one entry whose surface is a bare particle — `n3-b612`,
    /// で/で, the conjunction "and, then" — so a learner who misheard the で of 電車で would
    /// otherwise be handed a card for a different word wearing the same kana. Blocked on the
    /// token, not on the lookup: the same shape as keeping the auxiliary ない away from the
    /// i-adjective 無い.
    public func entry(surface: String, reading: String) -> VocabEntry? {
        guard !JapaneseParticles.single.contains(surface) else { return nil }
        return bySurfaceAndReading[WrittenAndRead(surface: surface,
                                                  reading: KanaScript.katakanaToHiragana(reading))]
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func entry(id: String) -> VocabEntry? {
        byID[id]
    }

    /// Whether an id still names a word in this store — the predicate every due count and every
    /// run builder has to agree on.
    ///
    /// It exists as one value because it was written out by hand in fifteen places, and twice
    /// somebody wrote a count without it: a card whose word has been withdrawn can never be
    /// reviewed away, so it inflates whatever it appears in, forever. v1.22 found four such
    /// sites, v1.23 found two more. The `resolves:` parameters take a closure precisely so the
    /// review modules can stay ignorant of VocabKit; this is the one closure they should be
    /// handed. (v1.23 §B.)
    /// `@Sendable` because it crosses actor boundaries: the reminder scheduler is handed this
    /// predicate from the main actor and runs it on a Task. It captures only the id index,
    /// which is a dictionary of value types, so the guarantee is real rather than asserted.
    public var resolvesID: @Sendable (String) -> Bool {
        { [byID] id in byID[id] != nil }
    }

    public func entries(level: JLPTLevel) -> [VocabEntry] {
        entries.filter { $0.jlpt == level }
    }

    /// Entries (optionally filtered by level) sorted easiest-first.
    public func ordered(level: JLPTLevel? = nil) -> [VocabEntry] {
        let pool = level.map(entries(level:)) ?? entries
        return pool.sorted { $0.difficulty < $1.difficulty }
    }

    // MARK: Loading

    /// Bundled word-pack files, one per JLPT level (easiest first).
    static let levelFiles = ["n5", "n4", "n3", "n2", "n1"]

    static func loadBundled() -> VocabStore {
        let decoder = JSONDecoder()
        var all: [VocabEntry] = []
        for name in levelFiles {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                assertionFailure("VocabKit: \(name).json is missing")
                continue
            }
            do {
                all.append(contentsOf: try decoder.decode([VocabEntry].self, from: data))
            } catch {
                assertionFailure("VocabKit: failed to decode \(name).json: \(error)")
            }
        }
        return VocabStore(entries: all)
    }
}
