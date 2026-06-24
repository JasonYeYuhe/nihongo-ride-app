import Testing
import Foundation
@testable import WordListsKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func t(_ secs: Double) -> Date { t0.addingTimeInterval(secs) }

/// A fresh temp file URL (not created on disk).
private func tmp(_ ext: String = "json") -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wl-\(UUID().uuidString).\(ext)")
}

// `Result<Void, _>` isn't Equatable (Void isn't), so use small matchers.
private func ok<T>(_ r: Result<T, WordListError>) -> Bool {
    if case .success = r { return true } else { return false }
}
private func errOf<T>(_ r: Result<T, WordListError>) -> WordListError? {
    if case .failure(let e) = r { return e } else { return nil }
}

// MARK: - CRUD / invariants

@Suite("WordListStore — CRUD & invariants")
struct WordListStoreCRUDTests {

    @Test("ensureDefault is idempotent and uses the constant id")
    func ensureDefault() {
        var s = WordListStore()
        s.ensureDefault(name: "★ Favorites", now: t(0))
        s.ensureDefault(name: "ignored", now: t(10))
        #expect(s.lists.count == 1)
        #expect(s.defaultList?.id == WordList.defaultID)
        #expect(s.defaultList?.isDefault == true)
        #expect(s.defaultList?.name == "★ Favorites")   // second call did not overwrite
    }

    @Test("createList trims, appends after default, rejects empty")
    func createList() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        let r = s.createList(name: "  Verbs  ", now: t(1))
        guard case .success(let made) = r else { Issue.record("expected success"); return }
        #expect(made.name == "Verbs")
        #expect(!made.isDefault)
        #expect(s.activeLists.map(\.id) == [WordList.defaultID, made.id])   // default first
        #expect(errOf(s.createList(name: "   ", now: t(2))) == .invalidName)
    }

    @Test("addWord dedups, preserves order, no-op success on duplicate")
    func addWord() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        #expect(ok(s.addWord("a", to: WordList.defaultID)))
        #expect(ok(s.addWord("b", to: WordList.defaultID)))
        #expect(ok(s.addWord("a", to: WordList.defaultID)))   // dup → no-op success
        #expect(s.defaultList?.ids == ["a", "b"])
        #expect(errOf(s.addWord("x", to: "nope")) == .listNotFound)
    }

    @Test("toggle flips membership and returns new state")
    func toggle() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        #expect(s.toggle("w", in: WordList.defaultID) == .success(true))
        #expect(s.defaultContains("w"))
        #expect(s.toggle("w", in: WordList.defaultID) == .success(false))
        #expect(!s.defaultContains("w"))
    }

    @Test("removeWord / clear")
    func removeAndClear() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        _ = s.addWord("a", to: WordList.defaultID); _ = s.addWord("b", to: WordList.defaultID)
        _ = s.removeWord("a", from: WordList.defaultID)
        #expect(s.defaultList?.ids == ["b"])
        _ = s.clear(WordList.defaultID)
        #expect(s.defaultList?.ids.isEmpty == true)
    }

    @Test("rename bumps nameUpdatedAt; default cannot be deleted but can be cleared")
    func renameAndDefaultRules() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        let made = try! s.createList(name: "Old", now: t(1)).get()
        #expect(ok(s.rename(made.id, to: "New", now: t(5))))
        #expect(s.list(id: made.id)?.name == "New")
        #expect(s.list(id: made.id)?.nameUpdatedAt == t(5))
        #expect(errOf(s.softDelete(WordList.defaultID)) == .cannotDeleteDefault)
        #expect(ok(s.softDelete(made.id, now: t(6))))
        #expect(s.list(id: made.id)?.deleted == true)
        #expect(ok(s.clear(WordList.defaultID)))   // default clearable
    }

    @Test("containsAnywhere / defaultContains / listIDs(containing:)")
    func membershipQueries() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        let a = try! s.createList(name: "A", now: t(1)).get()
        _ = s.addWord("w", to: a.id)
        #expect(s.containsAnywhere("w"))
        #expect(!s.defaultContains("w"))
        #expect(s.listIDs(containing: "w") == [a.id])
        // a deleted list does not count
        _ = s.softDelete(a.id, now: t(2))
        #expect(!s.containsAnywhere("w"))
        #expect(s.listIDs(containing: "w").isEmpty)
    }
}

// MARK: - Caps

@Suite("WordListStore — soft caps")
struct WordListStoreCapTests {

    @Test("list cap: default + 49 is the limit; deleted lists don't count toward it")
    func listCap() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))   // 1 active
        for i in 0..<(WordListStore.maxLists - 1) {
            #expect(ok(s.createList(name: "L\(i)", now: t(Double(i)))))
        }
        #expect(s.activeLists.count == WordListStore.maxLists)
        #expect(errOf(s.createList(name: "overflow", now: t(99))) == .listCapReached(max: WordListStore.maxLists))
        // Free a slot by deleting one → create succeeds again.
        let victim = s.activeLists.last!.id
        _ = s.softDelete(victim, now: t(100))
        #expect(ok(s.createList(name: "ok", now: t(101))))
    }

    @Test("word cap: addWord and toggle both fail past the per-list limit, not silently")
    func wordCap() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        for i in 0..<WordListStore.maxWordsPerList {
            #expect(ok(s.addWord("w\(i)", to: WordList.defaultID)))
        }
        #expect(s.defaultList?.ids.count == WordListStore.maxWordsPerList)
        #expect(errOf(s.addWord("over", to: WordList.defaultID)) == .wordCapReached(max: WordListStore.maxWordsPerList))
        #expect(s.toggle("over2", in: WordList.defaultID) == .failure(.wordCapReached(max: WordListStore.maxWordsPerList)))
        // Toggling OFF an existing word is still allowed at the cap.
        #expect(s.toggle("w0", in: WordList.defaultID) == .success(false))
    }
}

// MARK: - Tombstones

@Suite("WordListStore — tombstones")
struct WordListStoreTombstoneTests {

    @Test("deleted lists are hidden from activeLists but retained until compaction")
    func tombstoneHidden() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        let a = try! s.createList(name: "A", now: t(1)).get()
        _ = s.softDelete(a.id, now: t(2))
        #expect(s.activeLists.map(\.id) == [WordList.defaultID])
        #expect(s.lists.count == 2)   // still retained for tombstone propagation
    }

    @Test("compaction drops tombstones older than the TTL, keeps recent ones and the default")
    func compaction() {
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        let old = try! s.createList(name: "old", now: t(1)).get()
        let recent = try! s.createList(name: "recent", now: t(1)).get()
        let now = t(100 * 24 * 60 * 60)                              // 100 days in
        _ = s.softDelete(old.id, now: now.addingTimeInterval(-WordListStore.tombstoneTTL - 1))  // > 30d old
        _ = s.softDelete(recent.id, now: now.addingTimeInterval(-60))                            // 1 min old
        s.compactTombstones(now: now)
        let ids = Set(s.lists.map(\.id))
        #expect(!ids.contains(old.id))                 // dropped
        #expect(ids.contains(recent.id))               // kept (still propagating)
        #expect(ids.contains(WordList.defaultID))      // default never dropped
    }

    @Test("compaction drops a deleted list with NO deletedAt (no immortal tombstones)")
    func compactNilDeletedAt() throws {
        // Hand-edited / forward-written shape: deleted:true with deletedAt absent.
        let json = #"{"lists":[{"id":"default","name":"★","isDefault":true},{"id":"z","name":"Zombie","deleted":true}]}"#
        var store = try #require(try? JSONDecoder().decode(WordListStore.self, from: Data(json.utf8)))
        #expect(store.list(id: "z")?.deleted == true)
        #expect(store.list(id: "z")?.deletedAt == nil)
        store.compactTombstones(now: t(0))
        #expect(store.list(id: "z") == nil)            // dropped despite nil deletedAt
        #expect(store.defaultList != nil)              // default kept
    }
}

// MARK: - Persistence & migration

@Suite("WordListStore — persistence & migration")
struct WordListStoreMigrationTests {

    @Test("save → load round-trips (with read-back verify)")
    func roundTrip() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        let a = try s.createList(name: "Verbs", now: t(1)).get()
        _ = s.addWord("v1", to: a.id)
        try s.save(to: url)
        let loaded = try #require(try? JSONDecoder().decode(WordListStore.self, from: Data(contentsOf: url)))
        #expect(loaded == s)
    }

    @Test("migration from legacy saved-words.json folds ids into the default list")
    func migrateFromSaved() throws {
        let wl = tmp(); let saved = tmp()
        defer { try? FileManager.default.removeItem(at: wl); try? FileManager.default.removeItem(at: saved) }
        try Data(#"{"ids":["s1","s2","s1"]}"#.utf8).write(to: saved)   // note duplicate
        let (store, outcome) = WordListStore.loadOrMigrate(
            wordListsURL: wl, legacySavedWordsURL: saved, defaultName: "★", now: t(0))
        #expect(outcome == .migratedFromSavedWords)
        #expect(store.defaultList?.ids == ["s1", "s2"])               // deduped
        #expect(FileManager.default.fileExists(atPath: wl.path))      // wrote word-lists.json
        #expect(FileManager.default.fileExists(atPath: saved.path))   // legacy file PRESERVED (rollback)
    }

    @Test("fresh install (neither file) yields an empty default list")
    func freshInstall() {
        let wl = tmp(); let saved = tmp()
        defer { try? FileManager.default.removeItem(at: wl) }
        let (store, outcome) = WordListStore.loadOrMigrate(
            wordListsURL: wl, legacySavedWordsURL: saved, defaultName: "★", now: t(0))
        #expect(outcome == .freshInstall)
        #expect(store.defaultList?.ids.isEmpty == true)
        #expect(store.activeLists.count == 1)
    }

    @Test("migration is idempotent: a valid word-lists.json is loaded, not re-migrated")
    func idempotent() throws {
        let wl = tmp(); let saved = tmp()
        defer { try? FileManager.default.removeItem(at: wl); try? FileManager.default.removeItem(at: saved) }
        try Data(#"{"ids":["s1"]}"#.utf8).write(to: saved)
        let first = WordListStore.loadOrMigrate(wordListsURL: wl, legacySavedWordsURL: saved, defaultName: "★", now: t(0))
        #expect(first.outcome == .migratedFromSavedWords)
        // Mutate saved-words afterwards; a second run must IGNORE it (already migrated).
        try Data(#"{"ids":["s1","s2","s3"]}"#.utf8).write(to: saved)
        let second = WordListStore.loadOrMigrate(wordListsURL: wl, legacySavedWordsURL: saved, defaultName: "★", now: t(10))
        #expect(second.outcome == .loadedExisting)
        #expect(second.store.defaultList?.ids == ["s1"])   // not re-folded from the now-bigger saved file
    }

    @Test("corrupt word-lists.json is quarantined to .corrupt and rebuilt from saved-words (no silent data loss)")
    func corruptRecovery() throws {
        let wl = tmp(); let saved = tmp()
        let corruptBackup = wl.appendingPathExtension("corrupt")
        defer {
            for u in [wl, saved, corruptBackup] { try? FileManager.default.removeItem(at: u) }
        }
        try Data("{ this is not valid json ".utf8).write(to: wl)
        try Data(#"{"ids":["keep1","keep2"]}"#.utf8).write(to: saved)
        let (store, outcome) = WordListStore.loadOrMigrate(
            wordListsURL: wl, legacySavedWordsURL: saved, defaultName: "★", now: t(0))
        #expect(outcome == .recoveredFromCorrupt)
        #expect(store.defaultList?.ids == ["keep1", "keep2"])                       // rebuilt
        #expect(FileManager.default.fileExists(atPath: corruptBackup.path))         // bad bytes quarantined
        // The freshly-written word-lists.json is now valid & loads on the next run.
        let again = WordListStore.loadOrMigrate(wordListsURL: wl, legacySavedWordsURL: saved, defaultName: "★", now: t(1))
        #expect(again.outcome == .loadedExisting)
    }

    @Test("tolerant decode: a list entry missing optional fields still loads")
    func tolerantDecode() throws {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        // Only id + name present; ids/nameUpdatedAt/deleted/isDefault omitted.
        try Data(#"{"lists":[{"id":"default","name":"★"},{"id":"x","name":"Partial"}]}"#.utf8).write(to: url)
        let store = try #require(try? JSONDecoder().decode(WordListStore.self, from: Data(contentsOf: url)))
        #expect(store.lists.count == 2)
        #expect(store.defaultList?.isDefault == true)                 // inferred from constant id
        #expect(store.list(id: "x")?.deleted == false)               // defaulted
    }

    @Test("element-tolerant decode: a malformed/non-object entry is skipped, the rest survive")
    func elementTolerantDecode() throws {
        // entry 1 missing `id`, entry 2 a non-object, entry 3 valid → only the valid one loads.
        let json = #"{"lists":[{"name":"NoId"},"garbage",{"id":"keep","name":"Keep","ids":["a"]}]}"#
        let store = try #require(try? JSONDecoder().decode(WordListStore.self, from: Data(json.utf8)))
        #expect(store.lists.map(\.id) == ["keep"])
    }

    @Test("loadOrMigrate keeps surviving named lists when ONE entry is malformed (not corrupt-rebuild)")
    func loadOrMigratePartial() throws {
        let wl = tmp(); let saved = tmp()
        let corruptBackup = wl.appendingPathExtension("corrupt")
        defer { for u in [wl, saved, corruptBackup] { try? FileManager.default.removeItem(at: u) } }
        try Data(#"{"lists":[{"id":"default","name":"★","ids":["d1"]},{"badentry":1},{"id":"keep","name":"Keep","ids":["k1"]}]}"#.utf8).write(to: wl)
        let (store, outcome) = WordListStore.loadOrMigrate(
            wordListsURL: wl, legacySavedWordsURL: saved, defaultName: "★", now: t(0))
        #expect(outcome == .loadedExisting)                          // NOT recoveredFromCorrupt
        #expect(store.list(id: "keep")?.ids == ["k1"])              // named list survived
        #expect(store.defaultList?.ids == ["d1"])
        #expect(!FileManager.default.fileExists(atPath: corruptBackup.path))   // nothing quarantined
    }

    @Test("loadOrMigrate does NOT compact tombstones on load (compaction is post-sync only)")
    func loadDoesNotCompact() throws {
        let wl = tmp(); let saved = tmp()
        defer { try? FileManager.default.removeItem(at: wl); try? FileManager.default.removeItem(at: saved) }
        var s = WordListStore(); s.ensureDefault(name: "★", now: t(0))
        let gone = try s.createList(name: "Gone", now: t(0)).get()
        _ = s.softDelete(gone.id, now: t(0))               // deletedAt = t(0)
        try s.save(to: wl)
        // Load far past the 30-day TTL; the tombstone must SURVIVE the load
        // (compacting here would let a peer revive the deletion on first fetch).
        let now = t(100 * 24 * 60 * 60)
        let (store, outcome) = WordListStore.loadOrMigrate(
            wordListsURL: wl, legacySavedWordsURL: saved, defaultName: "★", now: now)
        #expect(outcome == .loadedExisting)
        #expect(store.list(id: gone.id)?.deleted == true)  // tombstone retained, not compacted at load
    }

    @Test("an existing-but-unreadable word-lists.json is left untouched (unreadableDeferred), not clobbered")
    func unreadableDeferred() throws {
        // A directory at the path makes Data(contentsOf:) throw while fileExists is true.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wl-unread-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let saved = tmp()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: saved) }
        let (store, outcome) = WordListStore.loadOrMigrate(
            wordListsURL: dir, legacySavedWordsURL: saved, defaultName: "★", now: t(0))
        #expect(outcome == .unreadableDeferred)
        #expect(store.activeLists.count == 1)              // in-memory default for this session
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathExtension("corrupt").path))
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue)
    }
}
