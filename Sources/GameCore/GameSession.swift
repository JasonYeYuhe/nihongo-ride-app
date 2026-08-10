import Foundation
import Observation
import RomajiKana
import VocabKit
import ReviewKit

/// Drives one play-through of the typing game: a queue of words (new + due
/// review), the current word's matcher, scoring/combo, the bike-journey
/// distance, and recording each outcome into the SRS store.
///
/// UI-independent — it imports `Observation` (so SwiftUI can observe it) but not
/// SwiftUI. The game mode (bike journey vs. conveyor belt) lives entirely in the
/// view layer; this type only knows "type the word, advance, score".
/// Which game mode a run uses. The engine/loop are identical; modes differ only
/// in word supply and how the run ends (route distance vs. a countdown).
public enum GameMode: String, Sendable, CaseIterable {
    case journey       // ride a route; ends when the word queue is done
    case timeAttack    // sprint; ends when the timer (UI-driven) runs out
    case practice      // calm, distraction-free passage typing
    case conjugation   // verb-conjugation drill (driven by ConjugationSession, no SRS)
    case sentence      // type a whole example sentence (v1.18); no SRS — see RunCompletion
}

/// What a finished run persists and where it lands — the single source of truth for
/// `AppModel.finishGame`'s side-effect gating, extracted as a pure value so the
/// cram/practice red lines are unit-testable (PLAN-V1.7 §D test seam).
public struct RunCompletion: Equatable, Sendable {
    /// Persist SRS progress — real rides only (never practice or a weak-words cram).
    public var persistsSRS: Bool
    /// Append to the ride journal + lifetime odometer — everything except a cram.
    public var logsRide: Bool
    /// Report score / achievements to Game Center — real rides only.
    public var reportsGameCenter: Bool
    /// Show the results screen (true) vs go straight back to the menu (practice).
    public var showsResults: Bool

    /// Decides a run's completion from its mode + whether it records SRS:
    /// - a **weak-words cram** (`recordsSRS == false`) advances nothing — no SRS,
    ///   journal, odometer, or Game Center — but still shows its review-these results;
    /// - **practice** records no SRS but still logs a ride, and returns to the menu;
    /// - **sentence** records no SRS either, and the reason is worth stating: a sentence run
    ///   counts mistakes across the WHOLE sentence, so a typo in an unrelated clause would
    ///   land on the review card of the one word the sentence teaches. That card is
    ///   calibrated for typing a word; grading it on a whole sentence records an
    ///   incomparable signal into the same scheduler. Sentence mode still logs a ride and
    ///   still shows results — it is a real run, just not a review of anything.
    /// - every real ride persists everything and shows results.
    public init(mode: GameMode, recordsSRS: Bool) {
        let isCram = !recordsSRS
        let isPractice = mode == .practice
        let isSentence = mode == .sentence
        persistsSRS = !isPractice && !isSentence && !isCram
        logsRide = !isCram
        reportsGameCenter = !isPractice && !isCram
        showsResults = !isPractice
    }
}

@Observable
public final class GameSession {
    public struct Config: Sendable {
        /// Meaning display language code (e.g. "en", "zh").
        public var languageCode: String
        public var assistance: AssistanceMode
        /// How many new words to introduce per run.
        public var newWordCount: Int
        /// How many due review words to mix in.
        public var reviewWordCount: Int
        /// Baseline seconds per kana, used to derive the speed grade.
        public var secondsPerKanaBaseline: Double
        /// JLPT level to draw new words from; `nil` mixes all levels.
        public var level: JLPTLevel?
        public var mode: GameMode
        /// Countdown for time-attack, in seconds (UI-driven); `nil` for journey.
        public var timeLimit: TimeInterval?
        /// Whether typing outcomes are written to the SRS store during the run.
        /// `true` for real rides; **`false` for the weak-words cram** — early-reviewing
        /// not-yet-due cards would corrupt the SM-2 schedule, so a cram must never
        /// write SRS (PLAN-V1.7 §B red line). Default `true` preserves all real runs.
        public var recordsSRS: Bool

        public init(
            languageCode: String = "en",
            assistance: AssistanceMode = .always,
            newWordCount: Int = 12,
            reviewWordCount: Int = 8,
            secondsPerKanaBaseline: Double = 0.8,
            level: JLPTLevel? = nil,
            mode: GameMode = .journey,
            timeLimit: TimeInterval? = nil,
            recordsSRS: Bool = true
        ) {
            self.languageCode = languageCode
            self.assistance = assistance
            self.newWordCount = newWordCount
            self.reviewWordCount = reviewWordCount
            self.secondsPerKanaBaseline = secondsPerKanaBaseline
            self.level = level
            self.mode = mode
            self.timeLimit = timeLimit
            self.recordsSRS = recordsSRS
        }
    }

    // MARK: Public state (observed by the UI)

    public private(set) var current: VocabEntry?
    /// Refused keystrokes for this run, with the context needed to explain them back.
    /// In memory only; never persisted, never synced. (v1.15.)
    public private(set) var mistakes = MistakeTrace()
    public private(set) var index = 0
    public private(set) var score = 0
    public private(set) var combo = 0
    public private(set) var maxCombo = 0
    public private(set) var wordsCompleted = 0
    public private(set) var totalKeystrokes = 0
    public private(set) var correctKeystrokes = 0
    /// Bike-journey progress in (game) meters; advances on each completed word.
    public private(set) var distanceMeters = 0.0
    /// Words that lapsed this run (skipped, hinted, or many typos) — worth reviewing.
    public private(set) var lapsedEntries: [VocabEntry] = []
    public private(set) var isFinished = false
    /// The assistance policy for this run (v1.16 §A — one policy, not two hint systems).
    public var assistance: AssistanceMode { config.assistance }
    /// Whether the romaji answer is visible RIGHT NOW: study mode, or this word was revealed.
    /// Replaces the old mutable `showRomajiHint`, which `revealHint()` flipped session-wide —
    /// one reveal turned hints on for every later word in the run.
    public var romajiVisible: Bool { assistance == .always || currentRevealed }
    /// A reveal control is being offered because the learner is genuinely stuck (distinct
    /// refusals at the same matcher state, threshold `struggleOfferThreshold`). Never in
    /// Time Attack — the timer runs regardless, so any reading costs competitive time.
    public private(set) var assistanceOffered = false
    /// Whether the current word has been revealed (charged as a hint on completion).
    public var isRevealed: Bool { currentRevealed }

    static let struggleOfferThreshold = 3
    private var struggle = StruggleDetector()

    // MARK: Config / dependencies

    public let config: Config
    public private(set) var review: ReviewStore

    private let queue: [VocabEntry]
    private let now: () -> Date
    private var matcher: KanaInputMatcher?
    private var currentMistakes = 0
    private var currentRevealed = false
    private var wordStartedAt: Date

    // MARK: Init

    /// Designated initializer with an explicit word list (used by tests for determinism).
    public init(
        words: [VocabEntry],
        review: ReviewStore = ReviewStore(),
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) {
        self.queue = words
        self.review = review
        self.config = config
        self.now = now
        self.wordStartedAt = now()
        loadCurrent()
    }

    /// Builds a passage-driven session: every queue item is a full sentence
    /// (the passage's kana) — used by Practice "long-text" mode. Uses passages
    /// at or below `level`; difficulty rises as you progress through the run.
    /// - Parameter matching: when given, selects passages by CONTENT across every level
    ///   instead of by level. The coach's particle drill needs the sentences that actually
    ///   contain は/へ/を, and those are spread over all three lengths. (v1.15 §J.)
    public static func makePractice(
        passages: PassageStore = .shared,
        level: Passage.Level = .hard,
        matching: ((Passage) -> Bool)? = nil,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var pool = matching.map { passages.passages.filter($0) }
            ?? passages.passages.filter { $0.level == level }
        if pool.isEmpty { pool = passages.passages }   // safety net
        pool.shuffle()
        let words = pool.prefix(max(8, config.newWordCount)).map { passage -> VocabEntry in
            VocabEntry(
                id: "passage-\(passage.id)",
                surface: passage.kana,
                kana: passage.kana,
                partsOfSpeech: ["passage"],
                jlpt: .n5,
                meanings: passage.meanings.mapValues { [$0] }
            )
        }
        var practiceConfig = config
        practiceConfig.mode = .practice
        return GameSession(words: Array(words), config: practiceConfig, now: now)
    }

    /// Builds a sentence-typing run: the target is a whole example sentence's reading.
    ///
    /// Mechanically this is the same trick as `makePractice` — a synthetic `VocabEntry` whose
    /// `kana` is what gets typed — but the surface stays the KANJI sentence, because that is
    /// what the learner reads while typing, and the id stays the real entry's so the results
    /// screen can say which word each sentence was teaching.
    ///
    /// Only entries with `isTypeableSentence` are eligible. Fourteen shipped sentences have
    /// no reading on purpose (digits read one digit at a time), and offering one as a target
    /// would mark a learner wrong for typing what the sentence actually says.
    public static func makeSentence(
        vocab: VocabStore = .shared,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var pool = vocab.ordered(level: config.level).filter { $0.isTypeableSentence }
        // Level-scoped first; if that level has no typeable sentence yet, fall back to the
        // whole corpus rather than starting an empty run.
        if pool.isEmpty { pool = vocab.ordered().filter { $0.isTypeableSentence } }
        pool.shuffle()
        return sentenceSession(from: Array(pool.prefix(max(5, config.newWordCount))),
                               config: config, now: now)
    }

    /// The entries from `ids` that can actually carry a sentence run, in the given order and
    /// de-duplicated. Ids that no longer resolve are dropped, and so are entries with no
    /// typeable sentence — a saved list is a list of WORDS, and 5% of the corpus has no
    /// sentence to type.
    ///
    /// Exposed so the menu can show the real number before the run starts rather than
    /// after: "this list has 20 words and 6 of them have a sentence" is a different fact
    /// from "this list has 20 words", and the learner is entitled to the first one.
    public static func sentenceEntries(ids: [String], vocab: VocabStore = .shared) -> [VocabEntry] {
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted, let entry = vocab.entry(id: id),
                  entry.isTypeableSentence else { return nil }
            return entry
        }
    }

    /// Builds a sentence run from a chosen set of vocab ids — a saved word list, or the
    /// due-review stack (PLAN-V1.21 §B).
    ///
    /// **It never falls back to the level or corpus pool.** `makeSentence` does, because
    /// "this level has no sentences yet" was a content gap with a sensible substitute. Here
    /// the ids ARE the request: padding a three-sentence list up to five with unrelated
    /// corpus sentences would answer a question the learner did not ask, and they would have
    /// no way to tell which two were not theirs. A short run is the honest outcome, and an
    /// empty one leaves `isFinished` true at construction so the caller's build-then-guard
    /// keeps them on the menu (the v1.15 empty-pool lesson).
    ///
    /// Like `makeSentence` it is handed no `ReviewStore`: a sentence run counts mistakes
    /// across a whole sentence, so it must not be able to reach the real SM-2 schedule even
    /// if `RunCompletion`'s gate were ever loosened.
    public static func makeSentence(
        ids: [String],
        vocab: VocabStore = .shared,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var pool = sentenceEntries(ids: ids, vocab: vocab)
        pool.shuffle()
        return sentenceSession(from: Array(pool.prefix(max(5, config.newWordCount))),
                               config: config, now: now)
    }

    /// Builds a sentence run from the words whose SRS review is due (PLAN-V1.21 §B), so the
    /// run doubles as review reading even though — like every sentence run — it writes no SRS.
    ///
    /// The due query filters on "has a typeable sentence" rather than filtering afterwards,
    /// for the same reason `make` filters on "still resolves": asking for `limit` cards and
    /// then dropping most of them returns a run shorter than the badge promised.
    public static func makeSentence(
        due review: ReviewStore,
        on date: Date = Date(),
        vocab: VocabStore = .shared,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        let ids = review.dueCards(
            on: date,
            limit: max(5, config.newWordCount),
            resolves: { vocab.entry(id: $0)?.isTypeableSentence == true }
        ).map(\.id)
        return makeSentence(ids: ids, vocab: vocab, config: config, now: now)
    }

    /// How many due cards could carry a sentence right now — the menu's honest count.
    public static func dueSentenceCount(
        review: ReviewStore,
        on date: Date = Date(),
        vocab: VocabStore = .shared
    ) -> Int {
        review.dueCount(on: date, resolves: { vocab.entry(id: $0)?.isTypeableSentence == true })
    }

    /// Wraps chosen entries as sentence-typing cards. The surface stays the KANJI sentence
    /// (that is what the learner reads while typing) and the id stays the real entry's, so
    /// the results screen can still say which word each sentence was teaching.
    private static func sentenceSession(
        from entries: [VocabEntry],
        config: Config,
        now: @escaping () -> Date
    ) -> GameSession {
        let words = entries.map { entry in
            VocabEntry(
                id: entry.id,
                surface: entry.exampleJP ?? entry.surface,
                kana: entry.exampleKana ?? entry.kana,
                partsOfSpeech: ["sentence"],
                jlpt: entry.jlpt,
                meanings: entry.meanings,
                exampleJP: entry.exampleJP,
                exampleEN: entry.exampleEN,
                exampleZH: entry.exampleZH,
                exampleKana: entry.exampleKana,
                exampleTokens: entry.exampleTokens
            )
        }
        var sentenceConfig = config
        sentenceConfig.mode = .sentence
        return GameSession(words: words, config: sentenceConfig, now: now)
    }

    /// Builds a session by mixing due review words with new words from the store.
    public static func make(
        config: Config = .init(),
        vocab: VocabStore = .shared,
        review: ReviewStore = ReviewStore(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        // Ask for cards that still resolve, rather than asking for all of them and dropping
        // the rest — otherwise a run silently returns fewer words than the badge promised.
        let dueWords = review.dueCards(on: now(), limit: config.reviewWordCount,
                                       resolves: { vocab.entry(id: $0) != nil })
            .compactMap { vocab.entry(id: $0.id) }
        let seen = Set(review.cards.keys)
        let newWords = vocab.ordered(level: config.level)
            .filter { !seen.contains($0.id) }
            .prefix(config.newWordCount)
        var words = dueWords + Array(newWords)
        words.shuffle()
        return GameSession(words: words, review: review, config: config, now: now)
    }

    /// Builds a journey-mode run from a saved-words deck (the user's curated
    /// vocab ids). Ids that no longer resolve are skipped; the deck is shuffled.
    /// Outcomes count toward SRS like a normal run.
    public static func makeSaved(
        ids: [String],
        vocab: VocabStore = .shared,
        review: ReviewStore = ReviewStore(),
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var words = ids.compactMap { vocab.entry(id: $0) }
        words.shuffle()
        var savedConfig = config
        savedConfig.mode = .journey
        return GameSession(words: words, review: review, config: savedConfig, now: now)
    }

    /// Builds a **weak-words cram** from the user's hardest reviewed words: the same
    /// journey loop, but it records NO SRS (`recordsSRS = false`) — a cram must not
    /// touch the SM-2 schedule (PLAN-V1.7 §B). Ids that no longer resolve are skipped.
    /// No `ReviewStore` is passed in: nothing is recorded, so the run can't reach the
    /// real store at all (the red line is structural at the session level).
    public static func makeWeak(
        ids: [String],
        vocab: VocabStore = .shared,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var words = ids.compactMap { vocab.entry(id: $0) }
        words.shuffle()
        var weakConfig = config
        weakConfig.mode = .journey
        weakConfig.recordsSRS = false
        return GameSession(words: words, config: weakConfig, now: now)
    }

    // MARK: Derived state for the UI

    public var currentKana: String? { current?.kana }
    public var currentSurface: String? { current?.surface }
    public var currentRomaji: String? { current?.romaji }
    public var currentGloss: String? { current?.gloss(for: config.languageCode) }
    public var mode: GameMode { config.mode }
    /// The full ordered word list of this run (for passage rendering in Practice).
    public var wordList: [VocabEntry] { queue }
    public var currentLevelLabel: String { current?.jlpt.label ?? "" }
    public var currentExampleJP: String? { current?.exampleJP }
    /// Surface/reading pairs for furigana over the example sentence.
    public var currentExampleTokens: [[String]]? { current?.exampleTokens }
    public var currentExampleTranslation: String? { current?.exampleTranslation(for: config.languageCode) }
    public var typedRomaji: String { matcher?.typedRomaji ?? "" }
    public var expectedNextCharacters: Set<Character> { matcher?.expectedNextCharacters ?? [] }
    public var completedKanaCount: Int { matcher?.completedKanaCount ?? 0 }
    public var wordCount: Int { queue.count }
    public var accuracy: Double {
        totalKeystrokes == 0 ? 1 : Double(correctKeystrokes) / Double(totalKeystrokes)
    }
    public var progress: Double {
        queue.isEmpty ? 1 : Double(wordsCompleted) / Double(queue.count)
    }

    // MARK: Input

    /// Feeds one keystroke to the current word.
    @discardableResult
    public func input(_ character: Character) -> InputResult {
        guard !isFinished, var matcher else { return .rejected }
        totalKeystrokes += 1
        let result = matcher.input(character)
        self.matcher = matcher
        switch result {
        case .rejected:
            currentMistakes += 1
            combo = 0
            if config.assistance == .afterStruggle, config.mode != .timeAttack, !currentRevealed,
               let m = self.matcher {
                let state = StruggleDetector.StateKey(
                    wordIndex: index, kanaIndex: m.completedKanaCount, acceptedRomaji: m.typedRomaji)
                let attempts = struggle.record(Character(character.lowercased()),
                                               at: state, time: now())
                if attempts >= Self.struggleOfferThreshold { assistanceOffered = true }
            }
            // Record WHAT was refused, not just that something was (v1.15). Everything here
            // was already on hand at this instant and was being thrown away, which is why the
            // app could count a learner's mistakes but never explain one. In memory, this run
            // only — see MistakeTrace on why a keystroke log goes no further than that.
            if let kana = current?.kana {
                mistakes.record(MistakeEvent(
                    targetKana: kana,
                    entryID: current?.id,
                    acceptedRomaji: matcher.typedRomaji,
                    rejected: Character(character.lowercased()),
                    expectedNext: matcher.expectedNextCharacters,
                    kanaIndex: matcher.completedKanaCount,
                    order: mistakes.count + mistakes.dropped))
            }
        case .accepted:
            correctKeystrokes += 1
            struggle.reset()
            assistanceOffered = false
        case .completed:
            correctKeystrokes += 1
            completeCurrentWord()
        }
        return result
    }

    /// Reveals the romaji answer for the current word. Counts as a hint: it
    /// breaks the combo and the word will score minimally / count as an SRS lapse.
    public func revealHint() {
        currentRevealed = true
        assistanceOffered = false
        struggle.reset()
        combo = 0
    }

    /// A pause or backgrounding makes the struggle signal stale: the learner had time to
    /// think, so the count starts over. (v1.16 §A.)
    public func resetStruggle() {
        struggle.reset()
        assistanceOffered = false
    }

    /// Gives up on the current word, recording it as not completed, and advances.
    public func skip() {
        if let entry = current {
            // Gate ONLY the SRS write on recordsSRS (a cram must not touch SM-2);
            // lapsedEntries still collects so the review-these feedback works.
            if config.recordsSRS {
                review.record(
                    entryID: entry.id,
                    outcome: TypingOutcome(completed: false, mistakes: currentMistakes),
                    on: now()
                )
            }
            lapsedEntries.append(entry)
        }
        combo = 0
        advance()
    }

    // MARK: Internals

    private func loadCurrent() {
        if index < queue.count {
            current = queue[index]
            matcher = KanaInputMatcher(target: queue[index].kana)
            wordStartedAt = now()
        } else {
            current = nil
            matcher = nil
            isFinished = true
        }
    }

    private func completeCurrentWord() {
        guard let entry = current else { return }
        wordsCompleted += 1
        // A revealed word doesn't build the combo (and scores minimally).
        if currentRevealed {
            combo = 0
        } else {
            combo += 1
            maxCombo = max(maxCombo, combo)
        }

        let ratio = durationRatio(for: entry)
        let outcome = TypingOutcome(
            completed: true,
            mistakes: currentMistakes,
            usedHint: currentRevealed,
            durationRatio: ratio
        )
        if config.recordsSRS {
            review.record(entryID: entry.id, outcome: outcome, on: now())
        }
        if SRSCard.quality(from: outcome) < 3 { lapsedEntries.append(entry) }

        score += currentRevealed ? 10 : wordScore(entry: entry, mistakes: currentMistakes, combo: combo)
        distanceMeters += Double(entry.kana.count) * 10

        advance()
    }

    private func advance() {
        index += 1
        currentMistakes = 0
        currentRevealed = false
        struggle.reset()
        assistanceOffered = false
        loadCurrent()
    }

    private func durationRatio(for entry: VocabEntry) -> Double {
        let elapsed = now().timeIntervalSince(wordStartedAt)
        let baseline = Double(max(1, entry.kana.count)) * config.secondsPerKanaBaseline
        return baseline > 0 ? elapsed / baseline : 1
    }

    private func wordScore(entry: VocabEntry, mistakes: Int, combo: Int) -> Int {
        let base = 100 + entry.kana.count * 5
        let penalty = mistakes * 15
        let comboMultiplier = 1.0 + Double(min(combo, 10)) * 0.1   // up to 2× at a 10-combo
        return max(10, Int(Double(max(0, base - penalty)) * comboMultiplier))
    }
}
