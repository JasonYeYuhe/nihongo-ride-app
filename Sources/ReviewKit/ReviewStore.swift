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
