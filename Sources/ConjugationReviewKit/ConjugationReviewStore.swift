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

    /// Cards due on or before `date`, soonest-first, capped at `limit`.
    public func dueCards(on date: Date = Date(), limit: Int = 100) -> [ConjugationSRSCard] {
        cards.values
            .filter { $0.dueDate <= date }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(limit)
            .map { $0 }
    }

    public func dueCount(on date: Date = Date()) -> Int {
        cards.values.lazy.filter { $0.dueDate <= date }.count
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
}
