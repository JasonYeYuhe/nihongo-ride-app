import Testing
import Foundation
@testable import SyncKit
import WordListsKit

@Suite("probe")
struct ZZProbe {
    @Test("compaction eats a live re-add when its tombstone has expired")
    func probe() {
        let ttl = WordListStore.tombstoneTTL
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tRemove = now.addingTimeInterval(-ttl - 60)   // 30d+ ago: expired tombstone
        let tReadd  = now.addingTimeInterval(-2 * 86_400) // 2 days ago: the user's re-add

        // Device A: removed w long ago, re-added it 2 days ago. w IS in the list.
        var a = WordListStore(lists: [WordList(id: WordList.defaultID, name: "★",
            ids: ["w"], nameUpdatedAt: now, isDefault: true,
            wordMeta: ["w": WordMeta(a: tReadd, r: tRemove)])])
        #expect(a.lists[0].ids == ["w"])

        // A syncs (any incoming word-list change) -> compactTombstones runs.
        a.compactTombstones(now: now)
        print("A meta after compaction:", a.lists[0].wordMeta)

        // Device B: was offline since before the re-add. Still holds the old tombstone only.
        let b = WordListStore(lists: [WordList(id: WordList.defaultID, name: "★",
            ids: [], nameUpdatedAt: now, isDefault: true,
            wordMeta: ["w": WordMeta(r: tRemove)])])

        let ab = SyncMerge.wordLists(a, b).lists[0]
        let ba = SyncMerge.wordLists(b, a).lists[0]
        print("A(compacted) merge B ->", ab.ids)
        print("B merge A(compacted) ->", ba.ids)
        #expect(ab.ids == ["w"], "the re-add must survive")
        #expect(ba.ids == ["w"], "the re-add must survive")
    }
}
