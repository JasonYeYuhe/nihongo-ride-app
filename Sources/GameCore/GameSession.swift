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
    /// - every real ride persists everything and shows results.
    public init(mode: GameMode, recordsSRS: Bool) {
        let isCram = !recordsSRS
        let isPractice = mode == .practice
        persistsSRS = !isPractice && !isCram
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
        public var showRomajiHint: Bool
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
            showRomajiHint: Bool = true,
            newWordCount: Int = 12,
            reviewWordCount: Int = 8,
            secondsPerKanaBaseline: Double = 0.8,
            level: JLPTLevel? = nil,
            mode: GameMode = .journey,
            timeLimit: TimeInterval? = nil,
            recordsSRS: Bool = true
        ) {
            self.languageCode = languageCode
            self.showRomajiHint = showRomajiHint
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
    /// Whether to show the romaji hint (toggleable mid-run).
    public var showRomajiHint: Bool

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
        self.showRomajiHint = config.showRomajiHint
        self.wordStartedAt = now()
        loadCurrent()
    }

    /// Builds a passage-driven session: every queue item is a full sentence
    /// (the passage's kana) — used by Practice "long-text" mode. Uses passages
    /// at or below `level`; difficulty rises as you progress through the run.
    public static func makePractice(
        passages: PassageStore = .shared,
        level: Passage.Level = .hard,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var pool = passages.passages.filter { $0.level == level }
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

    /// Builds a session by mixing due review words with new words from the store.
    public static func make(
        config: Config = .init(),
        vocab: VocabStore = .shared,
        review: ReviewStore = ReviewStore(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        let dueWords = review.dueCards(on: now(), limit: config.reviewWordCount)
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
        case .accepted:
            correctKeystrokes += 1
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
        showRomajiHint = true
        combo = 0
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
