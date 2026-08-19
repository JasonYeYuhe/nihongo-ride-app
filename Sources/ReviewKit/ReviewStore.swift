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
    /// - Parameter resolves: whether a card's entry still exists in the vocabulary. Cards
    ///   whose entry has gone are skipped.
    ///
    ///   This parameter exists because the count and the run disagreed. `GameSession.make`
    ///   builds its review queue with `compactMap { vocab.entry(id:) }`, silently dropping
    ///   ids that no longer resolve, while this store counted every stored card. Retire or
    ///   rename one vocabulary entry and the app sends a push saying "12 words are due",
    ///   badges 12, and then hands the learner a run with 11 — the status lying about the
    ///   work, which is the failure this project has fixed twice before elsewhere.
    ///
    ///   ReviewKit cannot ask VocabKit directly (it depends only on PersistKit), so the
    ///   caller injects the check. The default keeps every existing call site behaving
    ///   exactly as before.
    public func dueCards(on date: Date = Date(), limit: Int = 100,
                         calendar: Calendar = .current,
                         resolves: (String) -> Bool) -> [SRSCard] {
        let cutoff = Self.dueCutoff(for: date, calendar: calendar)
        return cards.values
            .filter { $0.dueDate < cutoff && resolves($0.id) }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(limit)
            .map { $0 }
    }

    /// - Parameter resolves: see ``dueCards(on:limit:calendar:resolves:)``. The badge and the
    ///   daily reminder are built from this number, so it must not promise cards a run cannot
    ///   produce.
    public func dueCount(on date: Date = Date(), calendar: Calendar = .current,
                         resolves: (String) -> Bool) -> Int {
        let cutoff = Self.dueCutoff(for: date, calendar: calendar)
        // Not `.lazy` — the closure is non-escaping, so the filter must run now.
        return cards.values.filter { $0.dueDate < cutoff && resolves($0.id) }.count
    }

    /// Midnight ending `date`'s day. Falls back to `date` itself if the calendar can't
    /// produce it (DST-degenerate input), which restores the old instant behaviour rather
    /// than counting nothing.
    static func dueCutoff(for date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    /// - Parameter resolves: required for the same reason as everywhere else — a withdrawn
    ///   entry's card can never be reviewed away, so it is a leech forever. Nothing in the app
    ///   reads this yet; it takes the argument so that whatever reads it next cannot forget.
    public func leeches(resolves: (String) -> Bool) -> [SRSCard] {
        cards.values.filter { $0.isLeech && resolves($0.id) }
            .sorted { $0.lapses > $1.lapses }
    }

    /// Cards reviewed at least once — the pool the weak-words cram draws from
    /// (fresh, never-reviewed cards aren't "weak"). Cheap count for menu gating.
    /// - Parameter resolves: the same injected "does this card's entry still exist" check
    ///   `dueCards`/`dueCount` take, and it is here for the reason it is there. This count
    ///   gates the weak-words cram in the menu while the cram itself drops ids that no
    ///   longer resolve — so a learner with a withdrawn word among their reviewed ones was
    ///   offered a cram of N and handed N-1. It is the same defect v1.22 fixed in the badge,
    ///   the widget, the reminder and the forecast, in the one counting path that was not
    ///   part of that sweep. (Found reviewing that sweep.)
    public func reviewedCount(resolves: (String) -> Bool) -> Int {
        cards.values.filter { $0.totalReviews > 0 && resolves($0.id) }.count
    }

    /// Ids of cards reviewed at least once, sorted for a deterministic drill order.
    /// The pool a coaching drill draws from: words the learner already knows, so the drill
    /// isolates the typing problem instead of testing vocabulary at the same time. (v1.15.)
    /// - Parameter resolves: the drill builds its prompts from these ids, so a withdrawn entry
    ///   here is an id the drill will drop — the count/run split again, one step earlier. The
    ///   only caller happens to filter afterwards; requiring the argument means the next one
    ///   does not have to happen to.
    public func reviewedIDs(resolves: (String) -> Bool) -> [String] {
        cards.values.filter { $0.totalReviews > 0 && resolves($0.id) }.map(\.id).sorted()
    }

    /// The user's weakest *reviewed* cards, worst-first, capped at `limit`. Ranking:
    /// leeches first, then lower ease, more lapses, higher mistake-rate; id breaks
    /// ties for a deterministic order. Only cards with `totalReviews > 0` (a fresh
    /// card has no track record to call it "weak").
    ///
    /// **Pure read — never mutates the store.** The weak-words feature is a *cram*:
    /// it must NEVER write SRS (early-reviewing not-yet-due cards would corrupt the
    /// SM-2 interval/ease schedule). This function only ranks; it schedules nothing.
    /// - Parameter resolves: whether a card's word still exists. Applied BEFORE `limit`,
    ///   which is the whole point: withdrawn entries sort to the very front (a card whose word
    ///   is gone can never be reviewed away, so it is a permanent leech), so capping first and
    ///   filtering after hands back a run shorter than the menu promised. (v1.23 §B.)
    public func weakestCards(limit: Int = 100,
                             resolves: (String) -> Bool) -> [SRSCard] {
        cards.values
            .filter { $0.totalReviews > 0 && resolves($0.id) }
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
