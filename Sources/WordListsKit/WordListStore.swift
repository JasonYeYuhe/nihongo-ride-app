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
    public mutating func clear(_ listID: String) -> Result<Void, WordListError> {
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        lists[i].ids.removeAll()
        return .success(())
    }

    /// Adds a word to a list. No-op success if already present; fails if the list
    /// is at the per-list cap (the UI prompts instead of silently dropping).
    @discardableResult
    public mutating func addWord(_ vocabID: String, to listID: String, now: Date = Date()) -> Result<Void, WordListError> {
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        if lists[i].ids.contains(vocabID) { return .success(()) }
        guard lists[i].ids.count < Self.maxWordsPerList else {
            return .failure(.wordCapReached(max: Self.maxWordsPerList))
        }
        lists[i].ids.append(vocabID)
        return .success(())
    }

    @discardableResult
    public mutating func removeWord(_ vocabID: String, from listID: String) -> Result<Void, WordListError> {
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        lists[i].ids.removeAll { $0 == vocabID }
        return .success(())
    }

    /// Toggles a word in a list. Returns the new contained-state (true = now in
    /// the list). Fails only when adding past the per-list cap.
    @discardableResult
    public mutating func toggle(_ vocabID: String, in listID: String, now: Date = Date()) -> Result<Bool, WordListError> {
        guard let i = index(of: listID) else { return .failure(.listNotFound) }
        if lists[i].ids.contains(vocabID) {
            lists[i].ids.removeAll { $0 == vocabID }
            return .success(false)
        }
        guard lists[i].ids.count < Self.maxWordsPerList else {
            return .failure(.wordCapReached(max: Self.maxWordsPerList))
        }
        lists[i].ids.append(vocabID)
        return .success(true)
    }

    /// Drops soft-deleted (non-default) lists whose tombstone is older than
    /// ``tombstoneTTL``.
    public mutating func compactTombstones(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.tombstoneTTL)
        lists.removeAll { $0.deleted && !$0.isDefault && ($0.deletedAt ?? .distantFuture) < cutoff }
    }

    // MARK: Persistence (synchronous, atomic — red line: no Task.detached writes)

    /// Atomically writes the store, then reads it back and decodes it to verify
    /// the write round-trips (§A2 "原子写 + 读回校验"). Throws if the verify fails.
    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
        let back = try Data(contentsOf: url)
        _ = try JSONDecoder().decode(WordListStore.self, from: back)
    }
}
