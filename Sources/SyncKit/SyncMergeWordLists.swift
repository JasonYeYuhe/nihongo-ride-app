import Foundation
import WordListsKit

extension SyncMerge {

    // MARK: Word lists — per-list, FIELD-LEVEL merge (NOT whole-list LWW).

    /// Merges two devices' word-list stores. Lists are matched by `id` and unioned
    /// (a list present on either side survives). For a list present on **both**, the
    /// merge is field-level and deliberately clock-skew-free:
    ///
    /// - `ids`  → **per-id union** (local order first, remote-only appended). This
    ///   preserves the v1.4 ★ *add-wins* guarantee: a word added concurrently on
    ///   either device is never lost. (Whole-list LWW would depend on cross-device
    ///   clocks and silently drop words — the bug this avoids.)
    /// - `name` → scalar **LWW** on `nameUpdatedAt` (renames are the one genuinely
    ///   conflicting scalar; tie keeps local).
    /// - `deleted` → **once-true-wins** (either side deleted ⇒ deleted), so a
    ///   whole-list deletion propagates instead of being resurrected; `deletedAt`
    ///   keeps the *later* timestamp so the tombstone lives long enough to spread
    ///   before 30-day compaction.
    ///
    /// The default "★" list uses the constant id ``WordList/defaultID`` on every
    /// device, so it converges to one record and never splits.
    ///
    /// Commutative on the set of lists and on each field; idempotent.
    public static func wordLists(_ local: WordListStore, _ remote: WordListStore) -> WordListStore {
        var byID: [String: WordList] = [:]
        var order: [String] = []
        for l in local.lists {
            byID[l.id] = l
            order.append(l.id)
        }
        for r in remote.lists {
            if let l = byID[r.id] {
                byID[r.id] = mergeList(l, r)
            } else {
                byID[r.id] = r
                order.append(r.id)
            }
        }
        return WordListStore(lists: order.compactMap { byID[$0] })
    }

    private static func mergeList(_ a: WordList, _ b: WordList) -> WordList {
        // ids: per-id union, local order first (add-wins, skew-free).
        var ids = a.ids
        let have = Set(ids)
        for id in b.ids where !have.contains(id) { ids.append(id) }

        // name: later nameUpdatedAt wins; tie → local (a).
        let name = b.nameUpdatedAt > a.nameUpdatedAt ? b.name : a.name

        // deleted: once-true-wins; deletedAt = later of the two (longer tombstone life).
        let deleted = a.deleted || b.deleted
        let deletedAt: Date?
        switch (a.deletedAt, b.deletedAt) {
        case let (x?, y?): deletedAt = max(x, y)
        case let (x?, nil): deletedAt = x
        case let (nil, y?): deletedAt = y
        case (nil, nil):    deletedAt = nil
        }

        return WordList(
            id: a.id,
            name: name,
            ids: ids,
            nameUpdatedAt: max(a.nameUpdatedAt, b.nameUpdatedAt),
            deleted: deleted,
            deletedAt: deletedAt,
            isDefault: a.isDefault || b.isDefault
        )
    }
}
