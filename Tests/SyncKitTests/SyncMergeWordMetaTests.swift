import Testing
import Foundation
@testable import SyncKit
import WordListsKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func t(_ secs: Double) -> Date { t0.addingTimeInterval(secs) }

/// A default list with explicit per-word meta.
private func def(_ ids: [String], _ meta: [String: WordMeta] = [:]) -> WordListStore {
    WordListStore(lists: [WordList(id: WordList.defaultID, name: "★", ids: ids,
                                   nameUpdatedAt: t(0), isDefault: true, wordMeta: meta)])
}

private func merged(_ a: WordListStore, _ b: WordListStore) -> WordList {
    SyncMerge.wordLists(a, b).lists.first { $0.id == WordList.defaultID }!
}

/// The LWW-element-set that makes a per-word removal propagate (v1.10 §A).
///
/// The headline claim under test is narrow and deliberate: a word REMOVED on one
/// device stays removed after merging with a peer that still lists it. Everything
/// else here defends the ways that claim has historically been won and then lost —
/// by resurrecting the word, by eating a legitimate re-add, or by converging to a
/// different answer depending on who merged whom.
@Suite("SyncMerge — per-word LWW-element-set")
struct SyncMergeWordMetaTests {

    // MARK: The headline

    @Test("a removal survives a peer that still lists the word (the whole point)")
    func removalBeatsStalePeer() {
        // A removed "w" at t10. B never saw that and still has it in ids.
        let a = def(["x"], ["w": WordMeta(a: t(1), r: t(10))])
        let b = def(["w", "x"])
        #expect(merged(a, b).ids == ["x"])
        #expect(merged(b, a).ids == ["x"])   // and not by luck of direction
    }

    @Test("a re-add after the removal wins (the tombstone is not permanent)")
    func readdBeatsTombstone() {
        let a = def([], ["w": WordMeta(a: t(1), r: t(10))])
        let b = def(["w"], ["w": WordMeta(a: t(20), r: t(10))])
        #expect(merged(a, b).ids == ["w"])
        #expect(merged(b, a).ids == ["w"])
    }

    @Test("a re-add made BEFORE the tombstone arrived is not eaten")
    func concurrentReaddSurvives() {
        // The case that killed the plan's contested-only `a`: B re-adds at t20 while
        // still ignorant of A's t10 removal, so B records no conflict — only `a`.
        let a = def([], ["w": WordMeta(r: t(10))])
        let b = def(["w"], ["w": WordMeta(a: t(20))])
        #expect(merged(a, b).ids == ["w"])
        #expect(merged(b, a).ids == ["w"])
    }

    @Test("a removal after a re-add still removes")
    func removeAfterReadd() {
        let a = def([], ["w": WordMeta(a: t(20), r: t(30))])
        let b = def(["w"], ["w": WordMeta(a: t(20))])
        #expect(merged(a, b).ids.isEmpty)
        #expect(merged(b, a).ids.isEmpty)
    }

    // MARK: Backward compatibility — the red line

    @Test("no meta anywhere merges EXACTLY as pre-v1.10 add-wins union")
    func noMetaIsUnchangedUnion() {
        let a = def(["a", "b"])
        let b = def(["b", "c"])
        let m = merged(a, b)
        #expect(m.ids == ["a", "b", "c"])   // local order first, remote-only appended
        #expect(m.wordMeta.isEmpty)
    }

    @Test("a v1.9 peer (meta-less, still listing the word) cannot resurrect it")
    func v19PeerCannotResurrect() {
        // v1.9 decodes no wordMeta and unions ids, so its record comes back carrying
        // "w" forever. It may keep its own copy; it must not undo our removal.
        let us = def(["x"], ["w": WordMeta(a: t(1), r: t(10))])
        let v19 = def(["w", "x"])
        #expect(merged(us, v19).ids == ["x"])
        // ...and repeated fetches don't wear it down.
        var acc = merged(us, v19)
        for _ in 0..<5 { acc = SyncMerge.wordLists(def(acc.ids, acc.wordMeta), v19).lists[0] }
        #expect(acc.ids == ["x"])
    }

    @Test("an old file decodes with zero data loss and no meta")
    func oldFileDecodes() throws {
        let old = """
        {"id":"default","name":"★","ids":["a","b"],"isDefault":true,
         "nameUpdatedAt":\(t(5).timeIntervalSinceReferenceDate),"deleted":false}
        """
        let l = try JSONDecoder().decode(WordList.self, from: Data(old.utf8))
        #expect(l.ids == ["a", "b"], "old files must load their words verbatim")
        #expect(l.wordMeta.isEmpty)
        #expect(l.isPresent("a", inIDs: true))
    }

    @Test("an empty meta is omitted from the encoding (old readers, small records)")
    func emptyMetaOmitted() throws {
        let l = WordList(id: "L", name: "n", ids: ["a"], nameUpdatedAt: t(0))
        let json = String(data: try JSONEncoder().encode(l), encoding: .utf8)!
        #expect(!json.contains("wordMeta"))
    }

    // MARK: CRDT laws — the stated obligation

    @Test("commutative: merge order cannot change the outcome")
    func commutative() {
        let a = def(["x", "w"], ["w": WordMeta(a: t(20)), "y": WordMeta(a: t(2), r: t(9))])
        let b = def(["y"], ["w": WordMeta(r: t(10)), "y": WordMeta(a: t(2))])
        let ab = merged(a, b), ba = merged(b, a)
        #expect(Set(ab.ids) == Set(ba.ids))
        #expect(ab.wordMeta == ba.wordMeta)
    }

    @Test("idempotent: merging the same state twice is a fixpoint")
    func idempotent() {
        let a = def(["x"], ["w": WordMeta(a: t(1), r: t(10))])
        let b = def(["w", "x"])
        let once = merged(a, b)
        let twice = SyncMerge.wordLists(def(once.ids, once.wordMeta), def(once.ids, once.wordMeta))
            .lists[0]
        #expect(twice.ids == once.ids)
        #expect(twice.wordMeta == once.wordMeta)
    }

    @Test("associative: how devices pair off cannot change the outcome")
    func associative() {
        let a = def(["w"], ["w": WordMeta(a: t(1))])
        let b = def([], ["w": WordMeta(r: t(10))])
        let c = def(["w"], ["w": WordMeta(a: t(20))])
        let ab_c = SyncMerge.wordLists(def(merged(a, b).ids, merged(a, b).wordMeta), c).lists[0]
        let a_bc = SyncMerge.wordLists(a, def(merged(b, c).ids, merged(b, c).wordMeta)).lists[0]
        #expect(Set(ab_c.ids) == Set(a_bc.ids))
        #expect(ab_c.wordMeta == a_bc.wordMeta)
        #expect(ab_c.ids == ["w"], "t20 re-add is the latest event, so w is present")
    }

    // MARK: Compaction — regressions for the two bugs the TTL version shipped with

    @Test("compaction never drops a tombstone, however old — a v1.9 peer can't learn it")
    func compactionKeepsOldTombstones() {
        // The TTL version dropped this at day 30 on the argument that "every peer has had
        // the full TTL to receive it". A v1.9 peer never receives it (no wordMeta decode,
        // ids unioned), so dropping it handed the word back — and re-removing restarted the
        // same 30-day loop, making the removal permanently impossible.
        let now = t(0)
        let ancient = now.addingTimeInterval(-WordListStore.tombstoneTTL * 10)
        var store = WordListStore(lists: [WordList(
            id: WordList.defaultID, name: "★", ids: [], nameUpdatedAt: t(0), isDefault: true,
            wordMeta: ["w": WordMeta(r: ancient)])])
        store.compactTombstones(now: now)
        #expect(store.lists[0].wordMeta["w"]?.r == ancient)

        // ...and the tombstone still does its job against a v1.9 peer that never stopped
        // asserting the word.
        let v19 = def(["w"])
        #expect(merged(def([], store.lists[0].wordMeta), v19).ids.isEmpty)
    }

    @Test("compaction never drops a live re-add sitting on an expired tombstone")
    func compactionKeepsLiveReadd() {
        // {a: yesterday, r: 40 days ago}: the TTL version keyed retention off `r` alone and
        // dropped the entry whole, discarding a one-day-old `a`. The word then read as
        // uncontested, so any peer still holding the old tombstone deleted it on the next
        // merge — the user's re-add lost silently, on every device.
        let now = t(0)
        let old = now.addingTimeInterval(-WordListStore.tombstoneTTL - 86_400 * 10)
        let fresh = now.addingTimeInterval(-86_400)
        var store = WordListStore(lists: [WordList(
            id: WordList.defaultID, name: "★", ids: ["w"], nameUpdatedAt: t(0), isDefault: true,
            wordMeta: ["w": WordMeta(a: fresh, r: old)])])
        store.compactTombstones(now: now)
        #expect(store.lists[0].wordMeta["w"]?.a == fresh, "the load-bearing addedAt must survive")

        // The stale peer (still holding only the old tombstone) must NOT win.
        let stalePeer = def([], ["w": WordMeta(r: old)])
        #expect(merged(def(store.lists[0].ids, store.lists[0].wordMeta), stalePeer).ids == ["w"])
        #expect(merged(stalePeer, def(store.lists[0].ids, store.lists[0].wordMeta)).ids == ["w"])
    }

    @Test("compaction commutes with merge (it did not when it was a TTL)")
    func compactionCommutesWithMerge() {
        let now = t(0)
        let old = now.addingTimeInterval(-WordListStore.tombstoneTTL - 86_400)
        let fresh = now.addingTimeInterval(-86_400)
        let a = def(["w"], ["w": WordMeta(a: fresh, r: old)])
        let b = def([], ["w": WordMeta(r: old)])

        // merge → compact
        var mergeFirst = WordListStore(lists: [merged(a, b)])
        mergeFirst.compactTombstones(now: now)

        // compact → merge
        var ca = a; ca.compactTombstones(now: now)
        var cb = b; cb.compactTombstones(now: now)
        let compactFirst = SyncMerge.wordLists(ca, cb).lists[0]

        #expect(mergeFirst.lists[0].ids == compactFirst.ids)
        #expect(compactFirst.ids == ["w"])
    }

    @Test("compaction sweeps entries that carry no information")
    func compactionSweepsEmpty() {
        var store = WordListStore(lists: [WordList(
            id: WordList.defaultID, name: "★", ids: [], nameUpdatedAt: t(0), isDefault: true,
            wordMeta: ["empty": WordMeta()])])
        store.compactTombstones(now: t(0))
        #expect(store.lists[0].wordMeta["empty"] == nil)
    }

    // MARK: Store mutations stamp what the merge reads

    @Test("remove/clear stamp tombstones; a no-op remove stamps nothing")
    func mutationsStamp() {
        var s = WordListStore(lists: [WordList(id: WordList.defaultID, name: "★",
                                               ids: [], nameUpdatedAt: t(0), isDefault: true)])
        s.addWord("a", to: WordList.defaultID, now: t(1))
        s.addWord("b", to: WordList.defaultID, now: t(1))
        #expect(s.lists[0].wordMeta["a"]?.a == t(1))

        s.removeWord("a", from: WordList.defaultID, now: t(2))
        #expect(s.lists[0].wordMeta["a"]?.r == t(2))

        // Removing a word we never had must not tombstone a peer's pending add.
        s.removeWord("ghost", from: WordList.defaultID, now: t(3))
        #expect(s.lists[0].wordMeta["ghost"] == nil)

        s.clear(WordList.defaultID, now: t(4))
        #expect(s.lists[0].ids.isEmpty)
        #expect(s.lists[0].wordMeta["b"]?.r == t(4), "clear is N removals, each needing a tombstone")
    }
}
