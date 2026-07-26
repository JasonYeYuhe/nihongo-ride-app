import Foundation

/// What happened when the player typed a word — the raw signal we turn into an
/// SM-2 quality grade. All fields have lenient defaults.
public struct TypingOutcome: Sendable, Hashable {
    /// Whether the word was finished.
    public var completed: Bool
    /// Number of rejected keystrokes (typos).
    public var mistakes: Int
    /// Whether the romaji answer was revealed / the player effectively gave up to a hint.
    public var usedHint: Bool
    /// Actual time ÷ the player's rolling baseline for this length (1.0 = on par).
    public var durationRatio: Double

    public init(completed: Bool, mistakes: Int = 0, usedHint: Bool = false, durationRatio: Double = 1.0) {
        self.completed = completed
        self.mistakes = mistakes
        self.usedHint = usedHint
        self.durationRatio = durationRatio
    }
}

/// A spaced-repetition card using a simplified SM-2 scheduler.
///
/// Parameters and update rules follow the original SuperMemo SM-2 (see
/// `docs/RESEARCH.md` §5): EF starts at 2.5 with a 1.3 floor; intervals are
/// 1 day, 6 days, then `round(interval × EF)`; a lapse (q < 3) restarts
/// repetitions at 1 day and — per the *original* SM-2 — leaves EF unchanged.
public struct SRSCard: Codable, Hashable, Sendable, Identifiable {
    /// Matches `VocabEntry.id`.
    public let id: String
    public var easeFactor: Double
    /// Current interval in days.
    public var interval: Int
    public var repetitions: Int
    public var dueDate: Date
    public var lapses: Int
    public var lastReviewed: Date?
    public var totalReviews: Int
    public var totalMistakes: Int

    // Tolerant decoder. The synthesized one throws for the WHOLE array if a single card is
    // missing a single key, and `ReviewStore.load` then returned an empty store — nine
    // hundred cards gone because one lost a field, made permanent by the next write and
    // unrecoverable from iCloud (the change token means those records are never re-sent).
    // Only `id` is required, because a card without one cannot be filed anywhere; every
    // other field falls back to what a fresh card would have. (v1.15 §B.)
    private enum CodingKeys: String, CodingKey {
        case id, easeFactor, interval, repetitions, dueDate, lapses
        case lastReviewed, totalReviews, totalMistakes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        easeFactor = try c.decodeIfPresent(Double.self, forKey: .easeFactor) ?? Self.initialEaseFactor
        interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? 0
        repetitions = try c.decodeIfPresent(Int.self, forKey: .repetitions) ?? 0
        // A card with no due date is due now: it re-enters the rotation rather than
        // disappearing into the far future.
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate) ?? Date()
        lapses = try c.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        lastReviewed = try c.decodeIfPresent(Date.self, forKey: .lastReviewed)
        totalReviews = try c.decodeIfPresent(Int.self, forKey: .totalReviews) ?? 0
        totalMistakes = try c.decodeIfPresent(Int.self, forKey: .totalMistakes) ?? 0
    }

    public static let minimumEaseFactor = 1.3
    public static let initialEaseFactor = 2.5
    /// Lapses at/above this count flag the card as a "leech" worth extra attention.
    public static let leechThreshold = 8

    /// A fresh card is due immediately (it's new and should be introduced).
    public init(id: String, createdAt: Date = Date()) {
        self.id = id
        easeFactor = Self.initialEaseFactor
        interval = 0
        repetitions = 0
        dueDate = createdAt
        lapses = 0
        lastReviewed = nil
        totalReviews = 0
        totalMistakes = 0
    }

    public var isLeech: Bool { lapses >= Self.leechThreshold }

    public var isDue: Bool { dueDate <= Date() }

    /// Applies one review with SM-2 quality `quality` (0…5).
    public mutating func review(quality: Int, on date: Date = Date()) {
        let q = max(0, min(5, quality))
        totalReviews += 1
        lastReviewed = date

        if q >= 3 {
            switch repetitions {
            case 0: interval = 1
            case 1: interval = 6
            default: interval = Int((Double(interval) * easeFactor).rounded())
            }
            repetitions += 1
            // EF is updated only on success (original SM-2 leaves it untouched on a lapse).
            easeFactor = max(
                Self.minimumEaseFactor,
                easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
            )
        } else {
            repetitions = 0
            interval = 1
            lapses += 1
        }

        dueDate = Calendar.current.date(byAdding: .day, value: interval, to: date) ?? date
    }

    /// Maps a typing outcome to an SM-2 quality grade (0…5).
    public static func quality(from outcome: TypingOutcome) -> Int {
        guard outcome.completed else {
            return outcome.mistakes > 0 ? 1 : 0      // attempted-but-failed vs. blank/skip
        }
        if outcome.usedHint { return 2 }             // revealed the answer
        if outcome.mistakes > 2 { return 2 }         // many typos → treat as a lapse
        if outcome.mistakes > 0 { return 3 }         // finished, but with a typo or two
        return outcome.durationRatio <= 1.5 ? 5 : 4  // clean: fast vs. hesitant
    }
}
