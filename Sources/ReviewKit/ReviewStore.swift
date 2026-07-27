import Foundation
import PersistKit

/// Holds SM-2 cards keyed by vocabulary id, answers "what's due", and records
/// review outcomes. Value type with `Codable` persistence.
public struct ReviewStore: Codable, Sendable {
    public private(set) var cards: [String: SRSCard]

    public init(cards: [String: SRSCard] = [:]) {
        self.cards = cards
    }

    // Element-lossy decode: one unreadable card costs that card, not the store. Paired with
    // SRSCard's tolerant decoder, which is what makes a card readable in the first place.
    // (v1.15 §B.)
    private enum CodingKeys: String, CodingKey { case cards }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        (cards, skippedOnLoad) = try LossyLoad.lossyDictionary(SRSCard.self, from: c, forKey: .cards)
    }

    /// How many cards the last decode had to drop. Zero for a store built in memory.
    /// Reported by the loader, not acted on — the surviving cards are still correct.
    public private(set) var skippedOnLoad: Int = 0

    public var count: Int { cards.count }

    public func card(for id: String) -> SRSCard? { cards[id] }

    /// Cards due **by the end of `date`'s calendar day**, soonest-first, capped at `limit`.
    ///
    /// Day granularity, not instant, and the distinction is the whole point. `SRSCard.review`
    /// sets `dueDate = reviewInstant + N days`, so a card inherits the clock time it was
    /// reviewed at — practise at 21:00 and tomorrow's card comes due at 21:00. An instant
    /// comparison therefore reports 0 for most of the day while `dueByDay`/`dueForecast`
    /// (which bucket by calendar day) report the real number, and those are what feed the
    /// widget, the Ride Log, and the daily notification. The user got told "12 words due",
    /// opened the app, and read "Due for review: 0" — with the ride pulling nothing.
    ///
    /// Day granularity is the half that can actually be kept: a widget cannot re-render each
    /// minute, so an instant-based promise is structurally unkeepable, and day-granular
    /// scheduling is the SRS norm anyway. `DueReminderPlanner` had already hand-rolled this by
    /// passing an end-of-day instant — that workaround still lands on the same answer here.
    /// (v1.12 §B.)
    public func dueCards(on date: Date = Date(), limit: Int = 100,
                         calendar: Calendar = .current) -> [SRSCard] {
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

    /// Midnight ending `date`'s day. Falls back to `date` itself if the calendar can't
    /// produce it (DST-degenerate input), which restores the old instant behaviour rather
    /// than counting nothing.
    static func dueCutoff(for date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    public func leeches() -> [SRSCard] {
        cards.values.filter(\.isLeech).sorted { $0.lapses > $1.lapses }
    }

    /// Cards reviewed at least once — the pool the weak-words cram draws from
    /// (fresh, never-reviewed cards aren't "weak"). Cheap count for menu gating.
    public var reviewedCount: Int {
        cards.values.lazy.filter { $0.totalReviews > 0 }.count
    }

    /// Ids of cards reviewed at least once, sorted for a deterministic drill order.
    /// The pool a coaching drill draws from: words the learner already knows, so the drill
    /// isolates the typing problem instead of testing vocabulary at the same time. (v1.15.)
    public var reviewedIDs: [String] {
        cards.values.lazy.filter { $0.totalReviews > 0 }.map(\.id).sorted()
    }

    /// The user's weakest *reviewed* cards, worst-first, capped at `limit`. Ranking:
    /// leeches first, then lower ease, more lapses, higher mistake-rate; id breaks
    /// ties for a deterministic order. Only cards with `totalReviews > 0` (a fresh
    /// card has no track record to call it "weak").
    ///
    /// **Pure read — never mutates the store.** The weak-words feature is a *cram*:
    /// it must NEVER write SRS (early-reviewing not-yet-due cards would corrupt the
    /// SM-2 interval/ease schedule). This function only ranks; it schedules nothing.
    public func weakestCards(limit: Int = 100) -> [SRSCard] {
        cards.values
            .filter { $0.totalReviews > 0 }
            .sorted { a, b in
                if a.isLeech != b.isLeech { return a.isLeech }                       // leeches first
                if a.easeFactor != b.easeFactor { return a.easeFactor < b.easeFactor } // weaker ease first
                if a.lapses != b.lapses { return a.lapses > b.lapses }               // more lapses first
                let ra = Double(a.totalMistakes) / Double(max(1, a.totalReviews))
                let rb = Double(b.totalMistakes) / Double(max(1, b.totalReviews))
                if ra != rb { return ra > rb }                                       // higher mistake-rate first
                return a.id < b.id                                                   // deterministic tie-break
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Records a typing outcome for `entryID`, creating the card if it's new.
    /// Returns the SM-2 quality grade that was applied.
    @discardableResult
    public mutating func record(entryID: String, outcome: TypingOutcome, on date: Date = Date()) -> Int {
        var card = cards[entryID] ?? SRSCard(id: entryID, createdAt: date)
        let quality = SRSCard.quality(from: outcome)
        card.review(quality: quality, on: date)
        card.totalMistakes += outcome.mistakes
        cards[entryID] = card
        return quality
    }

    // MARK: Persistence

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Loads, reporting what happened. A caller that will WRITE this store back must check
    /// `outcome` — `.unreadable` means the file may be perfectly good and must not be
    /// overwritten. (v1.15 §B.)
    public static func loadReporting(from url: URL) -> (store: ReviewStore, outcome: LossyLoad.Outcome) {
        let (decoded, outcome) = LossyLoad.load(ReviewStore.self, from: url)
        let store = decoded ?? ReviewStore()
        if store.skippedOnLoad > 0 {
            return (store, .loadedWithSkips(skipped: store.skippedOnLoad))
        }
        return (store, outcome)
    }

    public static func load(from url: URL) -> ReviewStore { loadReporting(from: url).store }
}
