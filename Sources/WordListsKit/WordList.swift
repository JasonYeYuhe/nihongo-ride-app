import Foundation

/// Per-word add/remove timestamps — the payload of the LWW-element-set that makes
/// a per-word removal propagate across devices (v1.10 §A).
///
/// Field names are one letter on purpose: this dictionary is serialized into a
/// SINGLE CloudKit STRING field per list, so every byte is paid for once per word
/// per sync. `a` = addedAt, `r` = removedAt.
public struct WordMeta: Codable, Sendable, Equatable {
    /// When the word was last explicitly added. Written on EVERY add — not only a
    /// contested one. Writing it only when a tombstone is already known locally
    /// (the original plan) silently eats a genuine re-add made in the window before
    /// the tombstone arrives: the re-adding device sees no conflict, writes no `a`,
    /// and the merge then reads `a == nil` and honours the older removal.
    public var a: Date?
    /// When the word was last explicitly removed (the tombstone).
    public var r: Date?

    public init(a: Date? = nil, r: Date? = nil) {
        self.a = a
        self.r = r
    }
}

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
    /// Per-word add/remove timestamps (v1.10 §A). Empty for every list written by
    /// v1.9 and earlier, and empty is *exactly* the pre-v1.10 semantics — see
    /// ``isPresent(_:inIDs:)``. Compacted by `WordListStore.compactWordMeta`.
    public var wordMeta: [String: WordMeta]

    public init(
        id: String,
        name: String,
        ids: [String] = [],
        nameUpdatedAt: Date,
        deleted: Bool = false,
        deletedAt: Date? = nil,
        isDefault: Bool = false,
        wordMeta: [String: WordMeta] = [:]
    ) {
        self.id = id
        self.name = name
        self.ids = WordList.deduped(ids)
        self.nameUpdatedAt = nameUpdatedAt
        self.deleted = deleted
        self.deletedAt = deletedAt
        self.isDefault = isDefault || id == WordList.defaultID
        self.wordMeta = wordMeta
    }

    /// The LWW-element-set decision: is `id` a member of this list?
    ///
    /// This is the ONE place the rule lives — `SyncMerge.wordLists` and
    /// `AppModel.foldLegacyDeck` both defer to it, so a word can never be judged
    /// present by one and absent by the other.
    ///
    /// - No tombstone (`r == nil`) → membership is just presence in `ids`, i.e.
    ///   **verbatim the pre-v1.10 add-wins union**. This is what makes a decoded
    ///   old file (no `wordMeta` at all) behave exactly as it did before.
    /// - Tombstoned → present only if the word was added back *after* the removal.
    ///   `a == nil` therefore loses to any tombstone, which is the whole point: a
    ///   word sitting in a peer's `ids` with no recorded add-time is pre-removal
    ///   residue, not a re-add, and must not resurrect.
    public func isPresent(_ id: String, inIDs: Bool) -> Bool {
        Self.isPresent(id, inIDs: inIDs, meta: wordMeta[id])
    }

    public static func isPresent(_ id: String, inIDs: Bool, meta: WordMeta?) -> Bool {
        guard let removedAt = meta?.r else { return inIDs }
        return (meta?.a ?? .distantPast) > removedAt
    }

    /// De-dups while preserving first-seen order (matches `SavedWordsStore`).
    static func deduped(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

extension WordList {
    private enum CodingKeys: String, CodingKey {
        case id, name, ids, nameUpdatedAt, deleted, deletedAt, isDefault, wordMeta
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
            isDefault: (try? c.decode(Bool.self, forKey: .isDefault)) ?? (id == WordList.defaultID),
            // Absent in every pre-v1.10 file → [:] → every id uncontested → identical
            // behavior to before. The backward-decode red line is satisfied HERE.
            wordMeta: (try? c.decode([String: WordMeta].self, forKey: .wordMeta)) ?? [:]
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
        // Omitted when empty, so a fleet that never removes a word keeps writing
        // byte-identical files (and a v1.9 downgrade keeps reading them).
        if !wordMeta.isEmpty { try c.encode(wordMeta, forKey: .wordMeta) }
    }

    /// Drops meta entries that carry no information at all. Deliberately NOT a
    /// time-based GC — see below.
    ///
    /// v1.10 first shipped a 30-day TTL here, mirroring the whole-list tombstone, and
    /// it was wrong twice over. Both failures trace to one false premise, which the TTL
    /// doc stated outright: *"every peer has had the full TTL to receive it."*
    ///
    /// 1. A v1.9 peer can NEVER receive it. It decodes no `wordMeta` and unions `ids`,
    ///    so it keeps re-asserting a removed word forever. Dropping the tombstone at day
    ///    30 handed the word straight back — and re-removing it only restarted the same
    ///    30-day loop, so the user could never permanently remove it. That makes the
    ///    v1.10 headline false in exactly the mixed fleet it was written for.
    /// 2. Retention keyed off `r` alone (`if let r = m.r { return r >= cutoff }`) never
    ///    looked at `a`, so `{a: yesterday, r: 40 days ago}` was dropped whole — a
    ///    one-day-old, load-bearing re-add discarded. Any peer still holding the old
    ///    tombstone then won the next merge and deleted the word, because `isPresent`
    ///    reads `a == nil` as losing to every `r`. Compaction did not commute with
    ///    merge: compact-then-merge gave `[]`, merge-then-compact gave `[w]`.
    ///
    /// The unifying point: a time-based GC assumes propagation is timely AND symmetric,
    /// and neither holds — a peer can be offline past any TTL, or (v1.9) structurally
    /// unable to learn the fact at all. Only the peer's own acknowledgement could make
    /// dropping safe, and this merge has no version vectors to carry one.
    ///
    /// Not GC'ing costs little, because the meta is bounded by the VOCAB, not by time:
    /// keys are vocab ids ever added to this list, so the ceiling is the whole deck
    /// (7074 words ≈ 350KB of JSON, against CKRecord's ~1MB). A realistic list sits
    /// under 500 entries (~25KB) — the per-list word cap. Repeated fill/clear cycles do
    /// not accumulate: the same word reuses its own entry.
    mutating func compactWordMeta() {
        wordMeta = wordMeta.filter { $0.value.a != nil || $0.value.r != nil }
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
