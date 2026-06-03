import Foundation

/// In-memory vocabulary repository, loaded from a bundled word pack.
public struct VocabStore: Sendable {
    public let entries: [VocabEntry]

    /// The shared store, loaded once from the bundled N5 starter pack.
    public static let shared = VocabStore.loadBundled()

    public init(entries: [VocabEntry]) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func entry(id: String) -> VocabEntry? {
        entries.first { $0.id == id }
    }

    public func entries(level: JLPTLevel) -> [VocabEntry] {
        entries.filter { $0.jlpt == level }
    }

    /// Entries (optionally filtered by level) sorted easiest-first.
    public func ordered(level: JLPTLevel? = nil) -> [VocabEntry] {
        let pool = level.map(entries(level:)) ?? entries
        return pool.sorted { $0.difficulty < $1.difficulty }
    }

    // MARK: Loading

    static func loadBundled() -> VocabStore {
        guard let url = Bundle.module.url(forResource: "n5_starter", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            assertionFailure("VocabKit: n5_starter.json is missing")
            return VocabStore(entries: [])
        }
        do {
            let entries = try JSONDecoder().decode([VocabEntry].self, from: data)
            return VocabStore(entries: entries)
        } catch {
            assertionFailure("VocabKit: failed to decode n5_starter.json: \(error)")
            return VocabStore(entries: [])
        }
    }
}
