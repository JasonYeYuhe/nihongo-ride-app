import Foundation

/// What happened when the player typed a conjugated form — the raw signal turned
/// into an SM-2 quality grade. A **parallel copy** of `ReviewKit.TypingOutcome`:
/// ConjugationReviewKit is a deliberate zero-dependency sibling of ReviewKit
/// (PLAN-V1.8 §3, Option A) so the conjugation SRS keeps a clean module boundary
/// and can never be confused with the flat vocab review store. All fields default
/// leniently.
public struct ConjugationOutcome: Sendable, Hashable {
    /// Whether the form was typed to completion.
    public var completed: Bool
    /// Number of rejected keystrokes (typos).
    public var mistakes: Int
    /// Whether the answer was revealed / the player effectively gave up to a hint.
    public var usedHint: Bool
    /// Actual time ÷ the player's rolling baseline (1.0 = on par). Unused by the v1.8
    /// drill (no per-prompt timing yet) but carried for parity with SRSCard grading.
    public var durationRatio: Double

    public init(completed: Bool, mistakes: Int = 0, usedHint: Bool = false, durationRatio: Double = 1.0) {
        self.completed = completed
        self.mistakes = mistakes
        self.usedHint = usedHint
        self.durationRatio = durationRatio
    }
}

/// A spaced-repetition card for ONE (verb, form) pair — keyed `sourceID#form`, the
/// same id as `GameCore.ConjugationPrompt` (form-level, so 食べる's て-form and past
/// form track independently). A **parallel type** to `ReviewKit.SRSCard` (same fields,
/// same simplified SM-2 rules copied verbatim — PLAN-V1.8 §3 Option A) rather than a
/// shared generic: it buys a clean module boundary so a conjugation lapse can NEVER
/// leak into the flat vocab journey due-queue (red line §1). If a third SRS type ever
/// appears, factor out an `SRSLike` protocol then (v1.9), not now.
///
/// Scheduler rules follow the original SuperMemo SM-2 (see `docs/RESEARCH.md` §5): EF
/// starts 2.5 with a 1.3 floor; intervals are 1 day, 6 days, then `round(interval × EF)`;
/// a lapse (q < 3) restarts repetitions at 1 day and leaves EF unchanged.
public struct ConjugationSRSCard: Codable, Hashable, Sendable, Identifiable {
    /// `sourceID#form` — matches `ConjugationPrompt.id`.
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
    // other field falls back to what a fresh card would have. (v1.15 §B — see ReviewKit.SRSCard for the full story.)
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

    /// The source vocab entry id — everything before the last `#` in ``id``.
    /// (Vocab ids never contain `#`; the form raw value is the suffix.)
    public var sourceID: String {
        guard let hash = id.lastIndex(of: "#") else { return id }
        return String(id[id.startIndex..<hash])
    }
    /// The conjugation form's raw-value token — the suffix after the last `#`.
    public var formToken: String {
        guard let hash = id.lastIndex(of: "#") else { return "" }
        return String(id[id.index(after: hash)...])
    }

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

    /// Maps a conjugation outcome to an SM-2 quality grade (0…5).
    ///
    /// **The last line is a constant in production, and this comment used to claim otherwise.**
    /// It said "Same rubric as `SRSCard.quality(from:)` (kept in sync intentionally)", which is
    /// true of the TEXT and false of the BEHAVIOUR: `ConjugationSession` builds its
    /// `TypingOutcome` without a `durationRatio` (`ConjugationSession.swift:252` and `:281`), so
    /// the value defaults to 1.0 and `outcome.durationRatio <= 1.5` is always true. **Every
    /// clean conjugation answer is graded 5**, however long the learner laboured over it.
    ///
    /// Measured rather than read: a probe drove a real session with an injected clock advancing
    /// 30 seconds per keystroke — 240 seconds to type たべます — and the reported ratio was 1.0.
    /// The negative control is what makes that worth believing: the identical slow typing driven
    /// through `GameSession`, which DOES compute a ratio, graded 4. The instrument can see
    /// timing; the timing is not supplied here.
    ///
    /// The consequence is a schedule that drifts from the one this comment claimed parity with:
    /// q=5 adds 0.10 to the ease factor and q=4 adds nothing, so a form the learner struggled
    /// with is treated as instant recall and leaves the rotation faster than a vocabulary card.
    ///
    /// **Deliberately NOT fixed in v1.26.** Wiring a prompt clock needs a baseline, and the only
    /// one available (`secondsPerKanaBaseline`, 0.8 s/kana) was chosen for copying a word the
    /// learner can SEE, while a conjugation prompt is recall plus production. There is also no
    /// correct clock to copy — `GameSession.durationRatio` is raw wall time and does not go
    /// through `RunClock` either. The grade is durable and syncs to CloudKit, so a wrong
    /// threshold would rewrite schedules on every device the learner owns. It is its own
    /// release: a paused prompt clock, a baseline chosen against data, and the live-WPM readout
    /// routed through `RunClock`. `NoPromptTimingTests` holds the finding until then.
    public static func quality(from outcome: ConjugationOutcome) -> Int {
        guard outcome.completed else {
            return outcome.mistakes > 0 ? 1 : 0      // attempted-but-failed vs. blank/skip
        }
        if outcome.usedHint { return 2 }             // revealed the answer
        if outcome.mistakes > 2 { return 2 }         // many typos → treat as a lapse
        if outcome.mistakes > 0 { return 3 }         // finished, but with a typo or two
        return outcome.durationRatio <= 1.5 ? 5 : 4  // clean: fast vs. hesitant
    }
}
