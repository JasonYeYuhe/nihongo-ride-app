import Foundation

/// The collection of a user's word lists, with CRUD, soft-caps, corruption-aware
/// migration, and tombstone compaction. Pure value type with synchronous, atomic
/// Codable persistence (mirroring `SavedWordsStore` / `ReviewStore`). UI + the
/// CloudKit wiring live in the app layer; the field-level merge lives in
/// `SyncMerge.wordLists`.
///
/// Time is injected (`now:`) into every mutation that stamps a timestamp so the
/// logic stays deterministically testable.
public struct WordListStore: Codable, Sendable, Equatable {

    /// Max number of *active* (non-deleted) lists, default included.
    public static let maxLists = 50
    /// Max words per list.
    public static let maxWordsPerList = 500
    /// Soft-deleted lists older than this are dropped locally (and not revived on
    /// merge). Prevents unbounded tombstone growth.
    public static let tombstoneTTL: TimeInterval = 30 * 24 * 60 * 60

    /// All lists, including soft-deleted ones (kept until tombstone compaction).
    /// Order: default first (inserted at index 0), then creation order.
    public private(set) var lists: [WordList]

    public init(lists: [WordList] = []) {
        self.lists = lists
    }

    // MARK: Codable — element-level tolerant decode

    private enum CodingKeys: String, CodingKey { case lists }

    /// Decodes a value that can fail without taking the whole array down with it.
    private struct FailableWordList: Decodable {
        let value: WordList?
        init(from decoder: Decoder) throws { value = try? WordList(from: decoder) }
    }

    /// Element-tolerant decode: a single malformed list entry (missing `id`, wrong
    /// type, not an object) is *skipped*, not fatal — so one bad entry can't strand
    /// every named list by routing the whole file to the corrupt-rebuild path. The
    /// `lists` key being absent / not an array is still a genuine-corruption throw.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.lists = try c.decode([FailableWordList].self, forKey: .lists).compactMap(\.value)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lists, forKey: .lists)
    }

    // MARK: Accessors

    /// Active (non-deleted) lists, default first.
    public var activeLists: [WordList] { lists.filter { !$0.deleted } }

    private var activeCount: Int { lists.reduce(0) { $0 + ($1.deleted ? 0 : 1) } }

    public func list(id: String) -> WordList? { lists.first { $0.id == id } }

    public var defaultList: WordList? { lists.first { $0.id == WordList.defaultID } }

    /// Whether the default ("★") list contains `vocabID` — drives the ★ glyph.
    public func defaultContains(_ vocabID: String) -> Bool {
        defaultList.map { !$0.deleted && $0.ids.contains(vocabID) } ?? false
    }

    /// Whether *any* active list contains `vocabID`.
    public func containsAnywhere(_ vocabID: String) -> Bool {
        lists.contains { !$0.deleted && $0.ids.contains(vocabID) }
    }

    /// Ids of active lists that contain `vocabID` — drives the "add to lists"
    /// multi-select checkmarks.
    public func listIDs(containing vocabID: String) -> [String] {
        lists.filter { !$0.deleted && $0.ids.contains(vocabID) }.map(\.id)
    }

    private func index(of listID: String) -> Int? {
        lists.firstIndex { $0.id == listID }
    }

    // MARK: Mutations

    /// Ensures the default "★" list exists (inserted at the front if missing).
    /// Idempotent.
    public mutating func ensureDefault(name: String, now: Date = Date()) {
        guard !lists.contains(where: { $0.id == WordList.defaultID }) else { return }
        lists.insert(
            WordList(id: WordList.defaultID, name: name, ids: [], nameUpdatedAt: now, isDefault: true),
            at: 0
        )
    }

    @discardableResult
    public mutating func createList(name: String, now: Date = Date()) -> Result<WordList, WordListError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidName) }
        guard activeCount < Self.maxLists else { return .failure(.listCapReached(max: Self.maxLists)) }
        let list = WordList(id: UUID().uuidString, name: trimmed, ids: [], nameUpdatedAt: now)
        lists.append(list)
        return .success(list)
    }

    @discardableResult
    public mutating func rename(_ listID: String, to name: String, now: Date = Date()) -> Result<Void, WordListError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidName) }
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        lists[i].name = trimmed
        lists[i].nameUpdatedAt = now
        return .success(())
    }

    /// Soft-deletes a list (tombstone). The default list cannot be deleted.
    @discardableResult
    public mutating func softDelete(_ listID: String, now: Date = Date()) -> Result<Void, WordListError> {
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        guard !lists[i].isDefault else { return .failure(.cannotDeleteDefault) }
        lists[i].deleted = true
        lists[i].deletedAt = now
        return .success(())
    }

    /// Empties a list's words (allowed on the default list — that's how the old
    /// "clear favorites" maps).
    @discardableResult
    public mutating func clear(_ listID: String, now: Date = Date()) -> Result<Void, WordListError> {
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        // Clearing is N removals: each id needs its own tombstone, or a peer's union
        // would refill the list on the next fetch (v1.10 §A).
        for id in lists[i].ids { lists[i].wordMeta[id, default: WordMeta()].r = now }
        lists[i].ids.removeAll()
        return .success(())
    }

    /// Seeds the default list's ids WITHOUT stamping any `wordMeta` — migration only.
    ///
    /// The ordinary `addWord` stamps `a = now`, which is right for a real user action and
    /// wrong for legacy data: `saved-words.json` is a bare, timestamp-less set, so
    /// claiming "added just now" for it converts pre-removal residue into a re-add that
    /// beats a peer's live tombstone (v1.10 §A). Unstamped ids stay *uncontested* — kept
    /// unless a peer holds a tombstone, in which case the tombstone rightly wins.
    ///
    /// It does NOT apply the per-list cap. v1.4's saved-words deck had no cap, so truncating
    /// here silently deleted a user's favourites past the 500th — and `enqueueAllLocal` then
    /// pushed the truncated deck over the cloud copy, so the loss propagated. A migrated
    /// default list is therefore GRANDFATHERED: it may exceed the cap, and `addWord` keeps
    /// refusing new additions until the count falls back under it (see `addWord`).
    ///
    /// Spilling the overflow into extra lists was the other candidate and is worse. The ★
    /// glyph asks only whether the DEFAULT list holds the word, so a spilled favourite would
    /// render unstarred and tapping ★ would try to re-add it to a list that is already full.
    /// Only the default list has a constant cross-device id; auto-created lists get UUIDs, so
    /// two upgrading devices would each mint their own "★ 2" and sync would union them. And
    /// the v1.4 cloud mirror carries default-list ids only, so spilled words would vanish from
    /// a peer still on v1.4. (v1.16 §C.)
    mutating func seedDefaultIDs(_ ids: [String]) {
        guard let i = index(of: WordList.defaultID) else { return }
        lists[i].ids = WordList.deduped(ids)
        lists[i].wordMeta = [:]
    }

    /// Adds a word to a list. No-op success if already present; fails if the list
    /// is at the per-list cap (the UI prompts instead of silently dropping).
    @discardableResult
    public mutating func addWord(_ vocabID: String, to listID: String, now: Date = Date()) -> Result<Void, WordListError> {
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        if lists[i].ids.contains(vocabID) { return .success(()) }
        // A grandfathered migration can leave the default list over the cap (see
        // seedDefaultIDs). The cap still refuses NEW additions — `>=` rather than `==` — so an
        // over-cap list drains toward the limit through removals and never grows past it.
        guard lists[i].ids.count < Self.maxWordsPerList else {
            return .failure(.wordCapReached(max: Self.maxWordsPerList))
        }
        lists[i].ids.append(vocabID)
        lists[i].wordMeta[vocabID, default: WordMeta()].a = now
        return .success(())
    }

    @discardableResult
    public mutating func removeWord(_ vocabID: String, from listID: String,
                                    now: Date = Date()) -> Result<Void, WordListError> {
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        // Only tombstone a word that was actually here: stamping `r` on a word we
        // simply haven't fetched yet would suppress a peer's legitimate add.
        guard lists[i].ids.contains(vocabID) else { return .success(()) }
        lists[i].ids.removeAll { $0 == vocabID }
        lists[i].wordMeta[vocabID, default: WordMeta()].r = now
        return .success(())
    }

    /// Toggles a word in a list. Returns the new contained-state (true = now in
    /// the list). Fails only when adding past the per-list cap.
    @discardableResult
    public mutating func toggle(_ vocabID: String, in listID: String, now: Date = Date()) -> Result<Bool, WordListError> {
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        if lists[i].ids.contains(vocabID) {
            lists[i].ids.removeAll { $0 == vocabID }
            lists[i].wordMeta[vocabID, default: WordMeta()].r = now
            return .success(false)
        }
        guard lists[i].ids.count < Self.maxWordsPerList else {
            return .failure(.wordCapReached(max: Self.maxWordsPerList))
        }
        lists[i].ids.append(vocabID)
        lists[i].wordMeta[vocabID, default: WordMeta()].a = now
        return .success(true)
    }

    /// Drops soft-deleted (non-default) lists whose tombstone is older than
    /// ``tombstoneTTL``. A tombstone with no `deletedAt` (degenerate state only
    /// reachable via a hand-edit / forward-write) is treated as immediately
    /// compactable so it can't become an immortal hidden list.
    ///
    /// ⚠️ Must run ONLY *after* a successful cloud merge — never on the load path
    /// (see ``loadOrMigrate(wordListsURL:legacySavedWordsURL:defaultName:now:)``).
    /// Compacting before a deletion has propagated lets a peer that still holds the
    /// list resurrect it on the next fetch (the merge unions a remote-only list back
    /// in). Deferring compaction to post-sync keeps the tombstone alive long enough
    /// to spread.
    public mutating func compactTombstones(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.tombstoneTTL)
        lists.removeAll { $0.deleted && !$0.isDefault && ($0.deletedAt ?? .distantPast) < cutoff }
        // Per-WORD meta is NOT on a TTL — only empty entries are swept. The whole-list
        // tombstone above can use one because every version back to v1.5 understands
        // `deleted`, so "every peer has had the TTL to see it" is actually true there.
        // No such luck one level down: v1.9 cannot parse wordMeta at all. See
        // WordList.compactWordMeta.
        for i in lists.indices {
            lists[i].compactWordMeta()
        }
    }

    // MARK: Persistence (synchronous, atomic — red line: no Task.detached writes)

    /// Verifies the encoded bytes round-trip back to a decodable store *before*
    /// touching the target, then writes atomically (§A2 "原子写 + 读回校验"). Verifying
    /// in memory first means a bad encode throws without ever replacing the good
    /// on-disk file; the atomic write then protects against torn writes.
    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        _ = try JSONDecoder().decode(WordListStore.self, from: data)   // round-trip verify pre-write
        try data.write(to: url, options: .atomic)
    }
}
