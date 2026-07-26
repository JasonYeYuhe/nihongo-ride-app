import Testing
import Foundation
@testable import SyncKit
import PersistKit

/// The one-time odometer backfill seeds this device's slot from the local journal. Slots SUM
/// and merge by `max`, so seeding it from a journal that is NOT this device's own history
/// doubles the fleet's lifetime totals **permanently** and propagates the wrong number to
/// every device. There is no path back: nothing ever subtracts.
///
/// v1.12 §A already narrowed the condition from `slots[deviceID] == nil` to `slots.isEmpty`.
/// These pin the three remaining ways an empty slot map can appear on a device whose journal
/// belongs to the fleet.
@Suite("Odometer backfill — only for a provable upgrader")
struct OdometerBackfillGateTests {

    private func gate(slots: [String: OdometerLog.Slot] = [:], runs: Int = 40,
                      considered: Bool = false, synced: Bool = false,
                      outcome: LossyLoad.Outcome = .missing) -> Bool {
        OdometerLog.shouldBackfill(slots: slots, localRuns: runs,
                                   alreadyConsidered: considered,
                                   hasSyncedBefore: synced, fileOutcome: outcome)
    }

    @Test("the case it exists for: a genuine v1.1 upgrader still backfills")
    func genuineUpgrader() {
        // No odometer file (the format did not exist), never synced, real local rides.
        #expect(gate())
    }

    @Test("a device that has synced before never backfills")
    func neverAfterSync() {
        // The trigger this closes: a first sync persists the fleet's ride RECORDS and dies
        // before the Odometer record page arrives — separate branches over a paged fetch. The
        // journal is now 40 of someone else's rides and the slot map is still empty.
        #expect(!gate(synced: true))
    }

    @Test("an unreadable odometer file is not an absent one")
    func unreadableIsNotMissing() {
        // Decoding an unreadable file yields an empty log, which looks exactly like a fresh
        // install to `slots.isEmpty`. Only a genuinely MISSING file may backfill.
        #expect(!gate(outcome: .unreadable))
        #expect(!gate(outcome: .undecodable))
        #expect(!gate(outcome: .loaded))
        #expect(!gate(outcome: .loadedWithSkips(skipped: 1)))
    }

    @Test("the decision is taken once per install, not re-taken every launch")
    func onlyConsideredOnce() {
        // Without this, a device that correctly declined on Monday could fire on Tuesday the
        // moment transient state made it look eligible.
        #expect(!gate(considered: true))
    }

    @Test("an existing slot map still blocks it, from any device")
    func existingSlotsBlock() {
        #expect(!gate(slots: ["other-device": .init(words: 900, distanceMeters: 5000, runs: 40)]))
        #expect(!gate(slots: ["this-device": .init(words: 10, distanceMeters: 50, runs: 1)]))
    }

    @Test("a device with no local rides has nothing to seed")
    func noLocalRuns() {
        #expect(!gate(runs: 0))
    }

    @Test("every gate is independently sufficient to block")
    func gatesAreIndependent() {
        // Guards against a future refactor that collapses them into one condition: each of
        // the four must veto on its own, with the other three permissive.
        #expect(!gate(considered: true, synced: false, outcome: .missing))
        #expect(!gate(considered: false, synced: true, outcome: .missing))
        #expect(!gate(considered: false, synced: false, outcome: .loaded))
        #expect(!gate(slots: ["x": .init()], considered: false, synced: false, outcome: .missing))
        // …and with none of them vetoing, it fires.
        #expect(gate(considered: false, synced: false, outcome: .missing))
    }
}
