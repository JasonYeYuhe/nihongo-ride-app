import Foundation
import ReviewKit
import JournalKit
import SavedWordsKit

/// Pure, side-effect-free merge of two devices' state. These functions are the
/// risky core of iCloud sync, deliberately written and tested in isolation
/// *before* any CloudKit code so the merge logic can't hide bugs behind a slow,
/// hard-to-mock cloud layer. The CKSyncEngine layer (v1.2 Phase B) calls exactly
/// these — both for ordinary fetches and for `serverRecordChanged` conflicts — so
/// there is one merge implementation, not two.
public enum SyncMerge {

    // MARK: SRS review store — newer `lastReviewed` wins, per card.

    /// Merges two SRS stores. For each vocab id in either store, keeps the card
    /// with the newer `lastReviewed`. A `nil` `lastReviewed` (never reviewed)
    /// always loses to a real timestamp; if both are `nil` (both freshly created)
    /// the cards are data-equivalent and `local` is kept. Ties keep `local`.
    public static func reviewStores(_ local: ReviewStore, _ remote: ReviewStore) -> ReviewStore {
        var merged = local.cards
        for (id, remoteCard) in remote.cards {
            guard let localCard = merged[id] else {
                merged[id] = remoteCard
                continue
            }
            merged[id] = winner(localCard, remoteCard)
        }
        return ReviewStore(cards: merged)
    }

    private static func winner(_ a: SRSCard, _ b: SRSCard) -> SRSCard {
        switch (a.lastReviewed, b.lastReviewed) {
        case let (la?, lb?): return lb > la ? b : a   // newer wins; tie → local (a)
        case (nil, _?):      return b                 // local never reviewed → remote wins
        case (_?, nil):      return a                 // remote never reviewed → local wins
        case (nil, nil):     return a                 // both new → equivalent, keep local
        }
    }

    // MARK: Ride history — union by id, then trim oldest.

    /// Merges two ride-history record sets: union by record id (records are
    /// immutable, so a shared id is the same run), sorted oldest-first by date
    /// (id as a stable tie-breaker), then trimmed to `cap` keeping the NEWEST.
    /// The journal is a display-only capped rolling window (local append trims the
    /// same way); lifetime totals are odometer-backed and survive trimming. So an
    /// overflowing merge drops the oldest-by-DATE records — which, in the rare
    /// case the union exceeds `cap` (>1yr of daily history), could include a
    /// backdated record one device just contributed. That only loses old
    /// journal-analytics rows past the cap, never lifetime data.
    public static func rideRecords(
        _ a: [RideRecord],
        _ b: [RideRecord],
        cap: Int = RideJournal.maxStoredRecords
    ) -> [RideRecord] {
        var byID: [UUID: RideRecord] = [:]
        byID.reserveCapacity(a.count + b.count)
        for r in a { byID[r.id] = r }
        for r in b where byID[r.id] == nil { byID[r.id] = r }
        let sorted = byID.values.sorted {
            ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString)
        }
        return sorted.count > cap ? Array(sorted.suffix(cap)) : sorted
    }

    // MARK: Saved-words deck — union (add-wins). LEGACY (v1.4).

    /// Merges two saved-words decks as a union: a word saved on either device
    /// stays saved (local order first, then remote-only ids appended). This is
    /// add-wins — un-saving doesn't propagate across devices (a curated-favorites
    /// MVP choice); a future version could use per-id tombstones for that.
    ///
    /// **Superseded in v1.5 by ``wordLists(_:_:)``.** The user-facing ★ deck is now
    /// the default ``WordListsKit/WordList`` (id `"default"`), merged field-level.
    /// The v1.4 `SavedWords:deck` CloudKit record lives on only as a one-way-compat
    /// *mirror* of that default list (the app folds an incoming deck into the
    /// default via union and re-writes it for still-v1.4 peers — see
    /// `AppModel.foldLegacyDeck`). This pure union is retained for that mirror's
    /// tests and for any code still reading the legacy store; new word-list merges
    /// must use ``wordLists(_:_:)``, not this.
    public static func savedWords(_ local: SavedWordsStore, _ remote: SavedWordsStore) -> SavedWordsStore {
        var ids = local.ids
        let have = Set(ids)
        for id in remote.ids where !have.contains(id) { ids.append(id) }
        return SavedWordsStore(ids: ids)
    }

    // MARK: Lifetime odometer — G-Counter (per-device slot, summed).

    /// Merges two odometer G-Counters: union of slots; for a slot present on both
    /// sides take the field-wise `max` (a device only ever grows its own slot, so
    /// `max` safely picks whichever side has the fresher value). Global totals are
    /// the sum of the merged slots.
    public static func odometers(_ a: OdometerLog, _ b: OdometerLog) -> OdometerLog {
        var slots = a.slots
        for (device, rs) in b.slots {
            if let ls = slots[device] {
                slots[device] = OdometerLog.Slot(
                    words: max(ls.words, rs.words),
                    distanceMeters: max(ls.distanceMeters, rs.distanceMeters),
                    runs: max(ls.runs, rs.runs)
                )
            } else {
                slots[device] = rs
            }
        }
        return OdometerLog(slots: slots)
    }
}
