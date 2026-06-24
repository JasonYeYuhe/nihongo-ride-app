import Testing
import Foundation
@testable import SyncKit
import WordListsKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func t(_ secs: Double) -> Date { t0.addingTimeInterval(secs) }

/// Convenience builder for a list with explicit fields.
private func list(
    _ id: String, name: String, ids: [String], nameAt: Date,
    deleted: Bool = false, deletedAt: Date? = nil, isDefault: Bool = false
) -> WordList {
    WordList(id: id, name: name, ids: ids, nameUpdatedAt: nameAt,
             deleted: deleted, deletedAt: deletedAt, isDefault: isDefault)
}

private func def(ids: [String], name: String = "★", nameAt: Date = t(0)) -> WordList {
    WordList(id: WordList.defaultID, name: name, ids: ids, nameUpdatedAt: nameAt, isDefault: true)
}

@Suite("SyncMerge — word lists")
struct SyncMergeWordListsTests {

    @Test("disjoint lists union together (a new list on either device survives)")
    func unionOfLists() {
        let a = WordListStore(lists: [def(ids: []), list("A", name: "A", ids: ["a"], nameAt: t(1))])
        let b = WordListStore(lists: [def(ids: []), list("B", name: "B", ids: ["b"], nameAt: t(1))])
        let merged = SyncMerge.wordLists(a, b)
        #expect(Set(merged.lists.map(\.id)) == [WordList.defaultID, "A", "B"])
    }

    @Test("ids = per-id union — concurrent adds are NEVER lost (★ add-wins regression guard)")
    func idsUnionAddWins() {
        // Both edited the default list offline: local added b, remote added c.
        let a = WordListStore(lists: [def(ids: ["a", "b"])])
        let b = WordListStore(lists: [def(ids: ["a", "c"])])
        let merged = SyncMerge.wordLists(a, b)
        #expect(merged.defaultList?.ids == ["a", "b", "c"])           // local order first, nothing dropped
        // Commutative as a set.
        #expect(Set(SyncMerge.wordLists(b, a).defaultList!.ids) == ["a", "b", "c"])
    }

    @Test("name = scalar LWW on nameUpdatedAt (both directions)")
    func nameLWW() {
        let a = WordListStore(lists: [list("L", name: "Old", ids: [], nameAt: t(10))])
        let b = WordListStore(lists: [list("L", name: "New", ids: [], nameAt: t(20))])
        #expect(SyncMerge.wordLists(a, b).list(id: "L")?.name == "New")
        #expect(SyncMerge.wordLists(b, a).list(id: "L")?.name == "New")   // order-independent
        #expect(SyncMerge.wordLists(a, b).list(id: "L")?.nameUpdatedAt == t(20))
    }

    @Test("deleted = once-true-wins (a whole-list deletion propagates; later deletedAt kept)")
    func deletePropagates() {
        let alive = WordListStore(lists: [list("L", name: "L", ids: ["x"], nameAt: t(0))])
        let killed = WordListStore(lists: [list("L", name: "L", ids: ["x"], nameAt: t(0), deleted: true, deletedAt: t(5))])
        #expect(SyncMerge.wordLists(alive, killed).list(id: "L")?.deleted == true)
        #expect(SyncMerge.wordLists(killed, alive).list(id: "L")?.deleted == true)
        // deletedAt = later of the two so the tombstone outlives compaction races.
        let killedEarly = WordListStore(lists: [list("L", name: "L", ids: [], nameAt: t(0), deleted: true, deletedAt: t(3))])
        let killedLate  = WordListStore(lists: [list("L", name: "L", ids: [], nameAt: t(0), deleted: true, deletedAt: t(9))])
        #expect(SyncMerge.wordLists(killedEarly, killedLate).list(id: "L")?.deletedAt == t(9))
    }

    @Test("default list converges to ONE record via the constant id (never splits)")
    func defaultDoesNotSplit() {
        // Two devices that each independently created their default list + added words.
        let a = WordListStore(lists: [def(ids: ["a"], name: "★", nameAt: t(1))])
        let b = WordListStore(lists: [def(ids: ["b"], name: "Favs", nameAt: t(2))])
        let merged = SyncMerge.wordLists(a, b)
        let defaults = merged.lists.filter { $0.id == WordList.defaultID }
        #expect(defaults.count == 1)                          // single default, not two
        #expect(merged.defaultList?.ids == ["a", "b"])        // ids union
        #expect(merged.defaultList?.name == "Favs")           // newer name wins
        #expect(merged.defaultList?.isDefault == true)
    }

    @Test("KNOWN MVP constraint: per-word removal does NOT propagate across devices (union re-adds)")
    func perWordRemovalDoesNotPropagate() {
        // Device A removed "x" from the default list; device B still has it.
        let a = WordListStore(lists: [def(ids: ["y"])])         // removed x locally
        let b = WordListStore(lists: [def(ids: ["x", "y"])])    // peer still has x
        let merged = SyncMerge.wordLists(a, b)
        // Union re-adds x — this is the documented MVP behavior (no per-word tombstone).
        #expect(merged.defaultList?.ids.contains("x") == true)
    }

    @Test("name LWW tie-break is deterministic and commutative on equal timestamps")
    func nameTieCommutative() {
        let a = WordListStore(lists: [list("L", name: "Apple", ids: [], nameAt: t(10))])
        let b = WordListStore(lists: [list("L", name: "Banana", ids: [], nameAt: t(10))])
        let ab = SyncMerge.wordLists(a, b).list(id: "L")?.name
        let ba = SyncMerge.wordLists(b, a).list(id: "L")?.name
        #expect(ab == ba)            // commutative even on exact-timestamp tie
        #expect(ab == "Banana")      // deterministic max() tie-break
    }

    @Test("whole-list deletion propagates while BOTH sides still hold the list (why compaction stays post-sync)")
    func deletionPropagatesBeforeCompaction() {
        // Supported flow: A tombstoned L, B still has L alive; first merge carries the
        // deletion via once-true-wins because both sides still hold id L.
        let aDeleted = WordListStore(lists: [def(ids: []), list("L", name: "L", ids: ["x"], nameAt: t(0), deleted: true, deletedAt: t(5))])
        let bAlive = WordListStore(lists: [def(ids: []), list("L", name: "L", ids: ["x"], nameAt: t(0))])
        #expect(SyncMerge.wordLists(bAlive, aDeleted).list(id: "L")?.deleted == true)
        // If A had COMPACTED L away before this merge, the union would re-add B's alive
        // L — which is exactly why compaction is deferred to post-sync (guarded by the
        // WordListsKit loadDoesNotCompact test).
    }

    @Test("merge is idempotent and does not oscillate over repeated fetch/send rounds")
    func idempotentNoOscillation() {
        let local = WordListStore(lists: [
            def(ids: ["a", "b"], name: "★", nameAt: t(10)),
            list("L", name: "Local", ids: ["p"], nameAt: t(1)),
        ])
        let remote = WordListStore(lists: [
            def(ids: ["a", "c"], name: "Favs", nameAt: t(20)),
            list("M", name: "Remote", ids: ["q"], nameAt: t(1), deleted: true, deletedAt: t(2)),
        ])
        let once = SyncMerge.wordLists(local, remote)
        let twice = SyncMerge.wordLists(local, once)            // re-merging local into the result
        let thrice = SyncMerge.wordLists(once, remote)
        #expect(once == twice)                                  // stable
        #expect(once == thrice)                                 // converged from either side
    }
}
