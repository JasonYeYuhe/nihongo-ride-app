import Foundation
import WordListsKit

extension SyncMerge {

    // MARK: Word lists — per-list, FIELD-LEVEL merge (NOT whole-list LWW).

    /// Merges two devices' word-list stores. Lists are matched by `id` and unioned
    /// (a list present on either side survives). For a list present on **both**, the
    /// merge is field-level and deliberately clock-skew-free:
    ///
    /// - `ids` + `wordMeta` → **LWW-element-set** (v1.10 §A). Uncontested words —
    ///   those with no tombstone, which is every word in a fleet that has never
    ///   removed one — are a plain **per-id union** (local order first, remote-only
    ///   appended), exactly as v1.5–v1.9 behaved: a word added concurrently on
    ///   either device is never lost. (Whole-list LWW would depend on cross-device
    ///   clocks and silently drop words — the bug this avoids.) Once a word carries
    ///   a tombstone it is present only if its `a` post-dates its `r`, which is what
    ///   makes a per-word removal propagate instead of being unioned back in by the
    ///   next fetch. See ``WordListsKit/WordList/isPresent(_:inIDs:)`` — the single
    ///   home of that rule.
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
    /// Convergent: every field (ids set, name, deleted, deletedAt) agrees on both
    /// devices regardless of merge direction, and the merge is idempotent. Display
    /// *order* (list order and ids order) is local-first BY DESIGN — each device
    /// keeps its own insertion order — so the two stores need not be byte-identical
    /// (same intentional property as `savedWords`); they converge as sets.
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
        // wordMeta: field-wise `max` per id. `max` is commutative, associative and
        // idempotent, which is what buys those same properties for the whole merge.
        var meta = a.wordMeta
        for (id, rm) in b.wordMeta {
            guard let lm = meta[id] else { meta[id] = rm; continue }
            meta[id] = WordMeta(a: later(lm.a, rm.a), r: later(lm.r, rm.r))
        }

        // ids: union local-first (unchanged add-wins order), then filtered through
        // the LWW-element-set rule. An id with no tombstone survives the filter
        // untouched, so a fleet that has never removed a word merges EXACTLY as it
        // did pre-v1.10.
        var union = a.ids
        let have = Set(union)
        for id in b.ids where !have.contains(id) { union.append(id) }
        var ids = union.filter { WordList.isPresent($0, inIDs: true, meta: meta[$0]) }
        // A word whose merged meta says present (a > r) but that is in NEITHER side's
        // ids. This is NOT the defensive edge case it was first written as ("no path to
        // get here today" — wrong): a MERGE RESULT is itself such a state. Merging
        // {ids:[w], a:t1} with {r:t10} yields ids [] while keeping meta for w, and
        // feeding that forward into a peer holding {a:t20} must re-materialise w, or the
        // merge is not associative — (a·b)·c drops w while a·(b·c) keeps it, so three
        // devices converge on the word being present or absent purely by which pair
        // synced first. Sorted, because Dictionary iteration order is not stable and
        // this must be device-independent.
        let listed = Set(ids)
        ids += meta.keys.sorted().filter {
            !listed.contains($0) && WordList.isPresent($0, inIDs: false, meta: meta[$0])
        }

        // name: later nameUpdatedAt wins; exact-timestamp tie → deterministic,
        // device-independent tie-break (lexicographically greater) so the chosen
        // name is the same regardless of merge direction.
        let name: String
        if b.nameUpdatedAt > a.nameUpdatedAt { name = b.name }
        else if a.nameUpdatedAt > b.nameUpdatedAt { name = a.name }
        else { name = max(a.name, b.name) }

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
            isDefault: a.isDefault || b.isDefault,
            wordMeta: meta
        )
    }

    /// `max` over optional Dates where nil means "no such event" and therefore loses
    /// to any real timestamp (NOT `.distantPast`-style arithmetic, which would make
    /// nil a legitimate, comparable value).
    private static func later(_ x: Date?, _ y: Date?) -> Date? {
        switch (x, y) {
        case let (l?, r?): return max(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil):    return nil
        }
    }
}
