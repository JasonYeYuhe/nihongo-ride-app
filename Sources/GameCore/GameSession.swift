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

        public init(
            languageCode: String = "en",
            showRomajiHint: Bool = true,
            newWordCount: Int = 12,
            reviewWordCount: Int = 8,
            secondsPerKanaBaseline: Double = 0.8
        ) {
            self.languageCode = languageCode
            self.showRomajiHint = showRomajiHint
            self.newWordCount = newWordCount
            self.reviewWordCount = reviewWordCount
            self.secondsPerKanaBaseline = secondsPerKanaBaseline
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
        let newWords = vocab.ordered()
            .filter { !seen.contains($0.id) }
            .prefix(config.newWordCount)
        var words = dueWords + Array(newWords)
        words.shuffle()
        return GameSession(words: words, review: review, config: config, now: now)
    }

    // MARK: Derived state for the UI

    public var currentKana: String? { current?.kana }
    public var currentSurface: String? { current?.surface }
    public var currentRomaji: String? { current?.romaji }
    public var currentGloss: String? { current?.gloss(for: config.languageCode) }
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

    /// Reveals the romaji answer for the current word (counts as a hint when scored).
    public func revealHint() {
        currentRevealed = true
        showRomajiHint = true
    }

    /// Gives up on the current word, recording it as not completed, and advances.
    public func skip() {
        if let entry = current {
            review.record(
                entryID: entry.id,
                outcome: TypingOutcome(completed: false, mistakes: currentMistakes),
                on: now()
            )
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
        combo += 1
        maxCombo = max(maxCombo, combo)

        let ratio = durationRatio(for: entry)
        let outcome = TypingOutcome(
            completed: true,
            mistakes: currentMistakes,
            usedHint: currentRevealed,
            durationRatio: ratio
        )
        review.record(entryID: entry.id, outcome: outcome, on: now())

        score += wordScore(entry: entry, mistakes: currentMistakes, combo: combo)
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
