import Foundation

/// Holds SM-2 cards keyed by vocabulary id, answers "what's due", and records
/// review outcomes. Value type with `Codable` persistence.
public struct ReviewStore: Codable, Sendable {
    public private(set) var cards: [String: SRSCard]

    public init(cards: [String: SRSCard] = [:]) {
        self.cards = cards
    }

    public var count: Int { cards.count }

    public func card(for id: String) -> SRSCard? { cards[id] }

    /// Cards due on or before `date`, soonest-first, capped at `limit`.
    public func dueCards(on date: Date = Date(), limit: Int = 100) -> [SRSCard] {
        cards.values
            .filter { $0.dueDate <= date }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(limit)
            .map { $0 }
    }

    public func dueCount(on date: Date = Date()) -> Int {
        cards.values.lazy.filter { $0.dueDate <= date }.count
    }

    public func leeches() -> [SRSCard] {
        cards.values.filter(\.isLeech).sorted { $0.lapses > $1.lapses }
    }

    /// Cards reviewed at least once — the pool the weak-words cram draws from
    /// (fresh, never-reviewed cards aren't "weak"). Cheap count for menu gating.
    public var reviewedCount: Int {
        cards.values.lazy.filter { $0.totalReviews > 0 }.count
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

    public static func load(from url: URL) -> ReviewStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(ReviewStore.self, from: data)
        else {
            return ReviewStore()
        }
        return store
    }
}
