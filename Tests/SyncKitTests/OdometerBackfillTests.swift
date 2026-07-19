import Testing
import Foundation
@testable import SyncKit
import JournalKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func ride(_ i: Int, words: Int) -> RideRecord {
    RideRecord(id: UUID(), date: t0.addingTimeInterval(Double(i) * 86_400),
               mode: "journey", level: "n5", score: words * 10, wpm: 30,
               accuracy: 0.95, wordsCompleted: words, lapsed: 0,
               distanceMeters: Double(words) * 10, duration: 60)
}

/// The lifetime odometer is a grow-only G-Counter: slots are summed, and merged with a
/// field-wise `max`. That makes an over-count PERMANENT and fleet-wide — there is no
/// subtraction and no UI to undo it. So the one place that ever *seeds* a slot from
/// something other than a real ride is load-bearing, and this suite pins it.
@Suite("Odometer backfill — the one seed that can double a lifetime")
struct OdometerBackfillTests {

    /// The rule the guard has to encode, stated once:
    /// backfill only from a journal that CANNOT contain another device's rides.
    private func backfill(into odo: inout OdometerLog, journal: RideJournal, deviceID: String) {
        guard OdometerLog.shouldBackfill(slots: odo.slots, localRuns: journal.totalRuns) else { return }
        odo.setSlot(.init(words: journal.totalWords,
                          distanceMeters: journal.totalDistanceMeters,
                          runs: journal.totalRuns), for: deviceID)
    }

    @Test("a v1.1 upgrader with local history and no odometer still gets seeded")
    func upgraderIsSeeded() {
        var odo = OdometerLog()
        let journal = RideJournal(records: [ride(0, words: 10), ride(1, words: 20)])
        backfill(into: &odo, journal: journal, deviceID: "A")
        #expect(odo.totalWords == 30, "the whole reason the backfill exists")
        #expect(odo.totalRuns == 2)
    }

    @Test("a second device that synced before its first ride does NOT re-seed the fleet's totals")
    func syncedPeerDoesNotDouble() {
        // The live sequence this pins (all three steps verified in the shipped code):
        //  1. Device B installs. Its journal is empty, so the backfill correctly does nothing.
        //  2. Sync pulls A's RideRecords. AppModel.applyCloudChanges rebuilds `journal` from the
        //     MERGED set and SAVES it — so B's on-disk journal now holds A's whole history.
        //     The same fetch brings A's odometer slot.
        //  3. The user quits without finishing a ride, so `odometer.record` never mints B's slot.
        // On the next launch the old guard (`slots[B] == nil && journal.totalRuns > 0`) is
        // satisfied by A's data, and B seeds ITSELF with A's lifetime. Slots are summed, so the
        // total doubles — and `max`-merge means it can never come back down.
        var odo = OdometerLog()
        odo.setSlot(.init(words: 1_000, distanceMeters: 10_000, runs: 50), for: "A")
        let journalFromCloud = RideJournal(records: (0..<50).map { ride($0, words: 20) })
        #expect(journalFromCloud.totalWords == 1_000, "the journal now mirrors A's lifetime")

        backfill(into: &odo, journal: journalFromCloud, deviceID: "B")

        #expect(odo.slots["B"] == nil, "B has ridden nothing; it must not claim A's history")
        #expect(odo.totalWords == 1_000, "lifetime stays A's real total, not 2000")
    }

    @Test("a device that already has its own slot is never re-seeded")
    func ownSlotIsNeverReseeded() {
        var odo = OdometerLog()
        odo.setSlot(.init(words: 500, distanceMeters: 5_000, runs: 25), for: "A")
        let journal = RideJournal(records: (0..<25).map { ride($0, words: 20) })
        backfill(into: &odo, journal: journal, deviceID: "A")
        #expect(odo.totalWords == 500)
    }

    @Test("no local history means nothing to seed")
    func emptyJournalSeedsNothing() {
        var odo = OdometerLog()
        backfill(into: &odo, journal: RideJournal(records: []), deviceID: "A")
        #expect(odo.slots.isEmpty)
    }

    @Test("the damage would have been permanent, which is why the guard matters")
    func doublingWouldBeIrreversible() {
        // Demonstrates the property that makes this severity HIGH rather than MEDIUM:
        // once a wrong slot exists anywhere, merge is max() per slot, so every device
        // converges UP to it. Nothing in the model can lower it again.
        var doubled = OdometerLog()
        doubled.setSlot(.init(words: 1_000, distanceMeters: 10_000, runs: 50), for: "A")
        doubled.setSlot(.init(words: 1_000, distanceMeters: 10_000, runs: 50), for: "B")
        var healthy = OdometerLog()
        healthy.setSlot(.init(words: 1_000, distanceMeters: 10_000, runs: 50), for: "A")

        let merged = SyncMerge.odometers(healthy, doubled)
        #expect(merged.totalWords == 2_000,
                "a healthy device that merges with a doubled peer becomes doubled too")
    }
}
