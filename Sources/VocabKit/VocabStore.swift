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

    /// Bundled word-pack files, one per JLPT level (easiest first).
    static let levelFiles = ["n5", "n4", "n3", "n2", "n1"]

    static func loadBundled() -> VocabStore {
        let decoder = JSONDecoder()
        var all: [VocabEntry] = []
        for name in levelFiles {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                assertionFailure("VocabKit: \(name).json is missing")
                continue
            }
            do {
                all.append(contentsOf: try decoder.decode([VocabEntry].self, from: data))
            } catch {
                assertionFailure("VocabKit: failed to decode \(name).json: \(error)")
            }
        }
        return VocabStore(entries: all)
    }
}
