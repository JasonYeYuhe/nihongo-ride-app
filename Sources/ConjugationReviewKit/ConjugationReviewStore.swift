import Foundation

/// Holds conjugation SM-2 cards keyed by `sourceID#form`, answers "what's due", and
/// records drill outcomes. A **separate store from the flat `ReviewKit.ReviewStore`**
/// with its own file (`conjugation-review.json`) and its own CKRecord type — a
/// conjugation lapse must NEVER flow into the vocab journey due-queue (red line §1,
/// PLAN-V1.8). Value type with `Codable` persistence.
public struct ConjugationReviewStore: Codable, Sendable, Equatable {
    public private(set) var cards: [String: ConjugationSRSCard]

    public init(cards: [String: ConjugationSRSCard] = [:]) {
        self.cards = cards
    }

    public var count: Int { cards.count }

    public func card(for promptID: String) -> ConjugationSRSCard? { cards[promptID] }

    /// Cards due **by the end of `date`'s calendar day**, soonest-first, capped at `limit`.
    ///
    /// Day granularity, mirroring `ReviewKit.ReviewStore.dueCards` — read that doc for why.
    /// The same split existed here: `dueForecast` (Stats, the widget) bucketed by calendar
    /// day while this compared instants, so the menu's "Review N due" button could sit
    /// hidden at 0 while Stats said cards were due today. (v1.12 §B.)
    public func dueCards(on date: Date = Date(), limit: Int = 100,
                         calendar: Calendar = .current) -> [ConjugationSRSCard] {
        let cutoff = Self.dueCutoff(for: date, calendar: calendar)
        return cards.values
            .filter { $0.dueDate < cutoff }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(limit)
            .map { $0 }
    }

    public func dueCount(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        let cutoff = Self.dueCutoff(for: date, calendar: calendar)
        return cards.values.lazy.filter { $0.dueDate < cutoff }.count
    }

    /// Midnight ending `date`'s day (see `ReviewStore.dueCutoff`).
    static func dueCutoff(for date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    /// Cards reviewed at least once (the pool weak-form weighting can rank).
    public var reviewedCount: Int {
        cards.values.lazy.filter { $0.totalReviews > 0 }.count
    }

    public func leeches() -> [ConjugationSRSCard] {
        cards.values.filter(\.isLeech).sorted { $0.lapses > $1.lapses }
    }

    /// The user's weakest *reviewed* (verb, form) cards, worst-first, capped at `limit`.
    /// Ranking mirrors `ReviewStore.weakestCards`: leeches first, then lower ease, more
    /// lapses, higher mistake-rate; id breaks ties for determinism. Only cards with
    /// `totalReviews > 0`. **Pure read — never mutates the store** (weak-form weighting
    /// only ranks; SRS is written solely via ``record(promptID:outcome:on:)``).
    public func weakestFormCards(limit: Int = 100) -> [ConjugationSRSCard] {
        cards.values
            .filter { $0.totalReviews > 0 }
            .sorted { a, b in
                if a.isLeech != b.isLeech { return a.isLeech }
                if a.easeFactor != b.easeFactor { return a.easeFactor < b.easeFactor }
                if a.lapses != b.lapses { return a.lapses > b.lapses }
                let ra = Double(a.totalMistakes) / Double(max(1, a.totalReviews))
                let rb = Double(b.totalMistakes) / Double(max(1, b.totalReviews))
                if ra != rb { return ra > rb }
                return a.id < b.id
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Records a drill outcome for prompt `promptID` (`sourceID#form`), creating the card
    /// if new. Returns the SM-2 quality grade applied.
    @discardableResult
    public mutating func record(promptID: String, outcome: ConjugationOutcome, on date: Date = Date()) -> Int {
        var card = cards[promptID] ?? ConjugationSRSCard(id: promptID, createdAt: date)
        let quality = ConjugationSRSCard.quality(from: outcome)
        card.review(quality: quality, on: date)
        card.totalMistakes += outcome.mistakes
        cards[promptID] = card
        return quality
    }

    // MARK: Persistence

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) -> ConjugationReviewStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(ConjugationReviewStore.self, from: data)
        else {
            return ConjugationReviewStore()
        }
        return store
    }

    /// Absolute-calendar-day due histogram for the home-screen widget (v1.11). Parallel to
    /// `ReviewStore.dueByDay` but hand-copied here to keep this module zero-dependency
    /// (Option A parallel types). `result[0]` absorbs everything overdue; cards `horizon`+
    /// days out are omitted. See `ReviewStore.dueByDay` for the full rationale (why a
    /// histogram, not a relative forecast). DST-safe via `dateComponents([.day])`.
    public func dueByDay(asOf date: Date = Date(), horizon: Int, calendar: Calendar = .current) -> [Int] {
        precondition(horizon > 0, "horizon must be positive")
        let start = calendar.startOfDay(for: date)
        var hist = [Int](repeating: 0, count: horizon)
        for card in cards.values {
            let cardDay = calendar.startOfDay(for: card.dueDate)
            guard let off = calendar.dateComponents([.day], from: start, to: cardDay).day else { continue }
            let bucket = max(0, off)
            if bucket < horizon { hist[bucket] += 1 }
        }
        return hist
    }

    /// Near-term due buckets for the Stats screen's conjugation section (v1.9 §B). Parallel to
    /// `ReviewKit.DueForecast` but defined here to keep ConjugationReviewKit zero-dependency.
    /// Disjoint: `today` includes anything overdue, `tomorrow` = next day, `thisWeek` = the 5 days
    /// after that.
    public func dueForecast(asOf date: Date = Date(), calendar: Calendar = .current) -> Forecast {
        let start = calendar.startOfDay(for: date)
        guard let endToday = calendar.date(byAdding: .day, value: 1, to: start),
              let endTomorrow = calendar.date(byAdding: .day, value: 2, to: start),
              let endWeek = calendar.date(byAdding: .day, value: 7, to: start)
        else { return Forecast() }
        var f = Forecast()
        for card in cards.values {
            if card.dueDate < endToday { f.today += 1 }
            else if card.dueDate < endTomorrow { f.tomorrow += 1 }
            else if card.dueDate < endWeek { f.thisWeek += 1 }
        }
        return f
    }

    /// Near-term due counts (today / tomorrow / this week).
    public struct Forecast: Sendable, Equatable {
        public var today: Int
        public var tomorrow: Int
        public var thisWeek: Int
        public init(today: Int = 0, tomorrow: Int = 0, thisWeek: Int = 0) {
            self.today = today; self.tomorrow = tomorrow; self.thisWeek = thisWeek
        }
    }
}
