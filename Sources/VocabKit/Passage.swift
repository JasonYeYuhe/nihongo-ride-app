import Foundation

/// A sentence-length practice passage. The `kana` field is the typing target
/// (kana-only; engine-typeable). Sourced from Tatoeba (CC BY 2.0 FR) — the
/// kana sentence and English are from Tatoeba; Chinese translation, topic and
/// level are added by us. See THIRD_PARTY_LICENSES.md.
public struct Passage: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    /// The Japanese text to type — pure kana (hiragana + optional katakana).
    public let kana: String
    /// Topic tag (English single word: "daily", "work", ...).
    public let topic: String
    /// Rough difficulty.
    public let level: Level
    /// Translations keyed by language code.
    public let meanings: [String: String]

    public enum Level: String, Codable, Sendable, CaseIterable { case easy, med, hard }

    public func meaning(for language: String, fallback: String = "en") -> String {
        meanings[language] ?? meanings[fallback] ?? meanings.values.first ?? ""
    }
}

/// In-memory passage repository, loaded from a bundled JSON.
public struct PassageStore: Sendable {
    public let passages: [Passage]
    public static let shared = PassageStore.loadBundled()

    public init(passages: [Passage]) { self.passages = passages }
    public var isEmpty: Bool { passages.isEmpty }

    public func ordered(level: Passage.Level? = nil) -> [Passage] {
        let pool = level.map { lvl in passages.filter { $0.level == lvl } } ?? passages
        return pool.sorted { ($0.level.rawValue, $0.kana.count) < ($1.level.rawValue, $1.kana.count) }
    }

    static func loadBundled() -> PassageStore {
        guard let url = Bundle.module.url(forResource: "passages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let passages = try? JSONDecoder().decode([Passage].self, from: data)
        else {
            assertionFailure("VocabKit: passages.json missing or invalid")
            return PassageStore(passages: [])
        }
        return PassageStore(passages: passages)
    }
}
