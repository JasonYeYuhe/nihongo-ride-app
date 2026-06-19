import Foundation

/// A user-curated deck of saved ("starred") vocabulary, kept as an ordered,
/// de-duplicated list of vocab ids (matching `VocabEntry.id`). Lets the learner
/// drill the words they care about on demand, independent of the SRS due queue.
///
/// Pure value type with Codable persistence, mirroring `ReviewStore` /
/// `OdometerLog`. UI + GameSession wiring live in the app layer; this is the
/// fully-testable core.
public struct SavedWordsStore: Codable, Sendable, Equatable {
    /// Vocab ids in save order (oldest first), unique.
    public private(set) var ids: [String]

    public init(ids: [String] = []) {
        // De-dup defensively while preserving first-seen order.
        var seen = Set<String>()
        self.ids = ids.filter { seen.insert($0).inserted }
    }

    public var count: Int { ids.count }
    public var isEmpty: Bool { ids.isEmpty }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Adds `id` if absent (appended at the end); no-op if already saved.
    public mutating func add(_ id: String) {
        if !ids.contains(id) { ids.append(id) }
    }

    public mutating func remove(_ id: String) {
        ids.removeAll { $0 == id }
    }

    /// Toggles `id`'s saved state. Returns the new state (true = now saved).
    @discardableResult
    public mutating func toggle(_ id: String) -> Bool {
        if let i = ids.firstIndex(of: id) {
            ids.remove(at: i)
            return false
        }
        ids.append(id)
        return true
    }

    // MARK: Persistence (mirrors ReviewStore / RideJournal / OdometerLog)

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) -> SavedWordsStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(SavedWordsStore.self, from: data)
        else { return SavedWordsStore() }
        // Re-run init's de-dup in case the file was hand-edited.
        return SavedWordsStore(ids: store.ids)
    }
}
