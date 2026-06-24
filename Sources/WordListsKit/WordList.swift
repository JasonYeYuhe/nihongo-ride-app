import Foundation

/// A single named, user-curated word list — an ordered, de-duplicated set of
/// vocab ids (matching `VocabEntry.id`). v1.5 generalizes the v1.4 single
/// "saved/starred" deck into *N* named lists; the old favorites deck survives as
/// **the one `isDefault` list with the constant id `"default"`** so its ★ add-wins
/// behavior and cross-device identity are preserved (see ``WordList/defaultID``).
///
/// Pure value type. CRUD + cap + migration + tombstone logic live in
/// ``WordListStore``; the field-level iCloud merge lives in `SyncMerge.wordLists`.
public struct WordList: Identifiable, Codable, Sendable, Equatable {
    /// The constant id of the default "★ favorites" list. Using a *constant* id
    /// (not a random UUID) is what keeps the default list a single record across
    /// devices — two devices each minting their own UUID would converge into two
    /// permanent default lists.
    public static let defaultID = "default"

    /// Stable identifier. The default list uses ``defaultID``; others use a UUID.
    public let id: String
    /// User-facing name. Merged by scalar LWW on ``nameUpdatedAt``.
    public var name: String
    /// Vocab ids in insertion order, unique. Merged by per-id **union** (add-wins,
    /// clock-skew-free) — never by whole-list LWW, which would lose concurrently
    /// added words.
    public var ids: [String]
    /// When ``name`` last changed. *Only* used to resolve name conflicts; it does
    /// **not** decide `ids` (those union).
    public var nameUpdatedAt: Date
    /// Soft-delete tombstone. A deleted list is hidden locally and its deletion
    /// propagates (once-true-wins) instead of being silently dropped.
    public var deleted: Bool
    /// When the list was soft-deleted, for tombstone compaction (~30-day TTL).
    public var deletedAt: Date?
    /// The default "★ favorites" list: cannot be deleted, can be cleared.
    public let isDefault: Bool

    public init(
        id: String,
        name: String,
        ids: [String] = [],
        nameUpdatedAt: Date,
        deleted: Bool = false,
        deletedAt: Date? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.ids = WordList.deduped(ids)
        self.nameUpdatedAt = nameUpdatedAt
        self.deleted = deleted
        self.deletedAt = deletedAt
        self.isDefault = isDefault || id == WordList.defaultID
    }

    /// De-dups while preserving first-seen order (matches `SavedWordsStore`).
    static func deduped(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

extension WordList {
    private enum CodingKeys: String, CodingKey {
        case id, name, ids, nameUpdatedAt, deleted, deletedAt, isDefault
    }

    /// Tolerant decode: only `id` is required. Every other field falls back to a
    /// sane default so a forward-/partially-written entry still loads instead of
    /// failing the whole file (which would strand the user's named lists). The
    /// genuinely-corrupt whole-file case is handled separately in
    /// ``WordListStore/loadOrMigrate(wordListsURL:legacySavedWordsURL:defaultName:now:)``.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        self.init(
            id: id,
            name: (try? c.decode(String.self, forKey: .name)) ?? "",
            ids: (try? c.decode([String].self, forKey: .ids)) ?? [],
            nameUpdatedAt: (try? c.decode(Date.self, forKey: .nameUpdatedAt)) ?? Date(timeIntervalSince1970: 0),
            deleted: (try? c.decode(Bool.self, forKey: .deleted)) ?? false,
            deletedAt: try? c.decode(Date.self, forKey: .deletedAt),
            isDefault: (try? c.decode(Bool.self, forKey: .isDefault)) ?? (id == WordList.defaultID)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(ids, forKey: .ids)
        try c.encode(nameUpdatedAt, forKey: .nameUpdatedAt)
        try c.encode(deleted, forKey: .deleted)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(isDefault, forKey: .isDefault)
    }
}

/// Why a ``WordListStore`` mutation was rejected. Surfaced to the UI as a prompt
/// (e.g. "list is full") — never swallowed as a silent no-op.
public enum WordListError: Error, Equatable, Sendable {
    case listNotFound
    case invalidName
    case listCapReached(max: Int)
    case wordCapReached(max: Int)
    case cannotDeleteDefault
}
