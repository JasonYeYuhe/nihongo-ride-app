import Testing
import Foundation
@testable import SyncKit
import ReviewKit
import JournalKit
import SavedWordsKit
import ConjugationReviewKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func t(_ secs: Double) -> Date { t0.addingTimeInterval(secs) }

/// Builds an SRS card with an explicit last-reviewed instant.
private func card(_ id: String, reviewed: Date?) -> SRSCard {
    var c = SRSCard(id: id, createdAt: t0)
    c.lastReviewed = reviewed
    if let reviewed { c.dueDate = reviewed.addingTimeInterval(86_400) }
    return c
}

private func record(_ id: UUID, at date: Date, words: Int = 1) -> RideRecord {
    RideRecord(id: id, date: date, mode: "journey", level: "N5", score: 100,
               wpm: 30, accuracy: 0.95, wordsCompleted: words, lapsed: 0,
               distanceMeters: 100, duration: 60)
}

@Suite("SyncMerge — SRS review store")
struct ReviewStoreMergeTests {

    @Test("newer lastReviewed wins")
    func newerWins() {
        let local = ReviewStore(cards: ["w": card("w", reviewed: t(0))])
        let remote = ReviewStore(cards: ["w": card("w", reviewed: t(100))])
        let merged = SyncMerge.reviewStores(local, remote)
        #expect(merged.card(for: "w")?.lastReviewed == t(100))

        // Order-independent: remote older → local kept.
        let merged2 = SyncMerge.reviewStores(remote, local)
        #expect(merged2.card(for: "w")?.lastReviewed == t(100))
    }

    @Test("a never-reviewed (nil) card loses to a reviewed one, both directions")
    func nilLoses() {
        let reviewed = ReviewStore(cards: ["w": card("w", reviewed: t(50))])
        let fresh = ReviewStore(cards: ["w": card("w", reviewed: nil)])
        #expect(SyncMerge.reviewStores(fresh, reviewed).card(for: "w")?.lastReviewed == t(50))
        #expect(SyncMerge.reviewStores(reviewed, fresh).card(for: "w")?.lastReviewed == t(50))
    }

    @Test("both nil → not a crash, keeps a card")
    func bothNil() {
        let a = ReviewStore(cards: ["w": card("w", reviewed: nil)])
        let b = ReviewStore(cards: ["w": card("w", reviewed: nil)])
        let merged = SyncMerge.reviewStores(a, b)
        #expect(merged.card(for: "w") != nil)
        #expect(merged.cards.count == 1)
    }

    @Test("disjoint ids union together")
    func union() {
        let a = ReviewStore(cards: ["a": card("a", reviewed: t(1))])
        let b = ReviewStore(cards: ["b": card("b", reviewed: t(2))])
        let merged = SyncMerge.reviewStores(a, b)
        #expect(merged.cards.count == 2)
        #expect(merged.card(for: "a") != nil)
        #expect(merged.card(for: "b") != nil)
    }

    @Test("merge is idempotent: merge(a, merge(a,b)) == merge(a,b)")
    func idempotent() {
        let a = ReviewStore(cards: ["w": card("w", reviewed: t(0)), "x": card("x", reviewed: nil)])
        let b = ReviewStore(cards: ["w": card("w", reviewed: t(100)), "y": card("y", reviewed: t(5))])
        let once = SyncMerge.reviewStores(a, b)
        let twice = SyncMerge.reviewStores(a, once)
        #expect(once.cards == twice.cards)
    }
}

/// Builds a conjugation SRS card with an explicit last-reviewed instant.
private func conjCard(_ id: String, reviewed: Date?) -> ConjugationSRSCard {
    var c = ConjugationSRSCard(id: id, createdAt: t0)
    c.lastReviewed = reviewed
    if let reviewed { c.dueDate = reviewed.addingTimeInterval(86_400) }
    return c
}

@Suite("SyncMerge — conjugation SRS store")
struct ConjugationReviewStoreMergeTests {

    @Test("newer lastReviewed wins, per (verb, form) card, both directions")
    func newerWins() {
        let local = ConjugationReviewStore(cards: ["v#te": conjCard("v#te", reviewed: t(0))])
        let remote = ConjugationReviewStore(cards: ["v#te": conjCard("v#te", reviewed: t(100))])
        #expect(SyncMerge.conjugationReviewStores(local, remote).card(for: "v#te")?.lastReviewed == t(100))
        #expect(SyncMerge.conjugationReviewStores(remote, local).card(for: "v#te")?.lastReviewed == t(100))
    }

    @Test("never-reviewed (nil) loses to reviewed; both-nil keeps a card")
    func nilRules() {
        let reviewed = ConjugationReviewStore(cards: ["v#te": conjCard("v#te", reviewed: t(50))])
        let fresh = ConjugationReviewStore(cards: ["v#te": conjCard("v#te", reviewed: nil)])
        #expect(SyncMerge.conjugationReviewStores(fresh, reviewed).card(for: "v#te")?.lastReviewed == t(50))
        #expect(SyncMerge.conjugationReviewStores(reviewed, fresh).card(for: "v#te")?.lastReviewed == t(50))
        let bothNil = SyncMerge.conjugationReviewStores(fresh, fresh)
        #expect(bothNil.card(for: "v#te") != nil)
    }

    @Test("different forms of the same verb are distinct cards (form-level id)")
    func formLevelDistinct() {
        let a = ConjugationReviewStore(cards: ["v#te": conjCard("v#te", reviewed: t(1))])
        let b = ConjugationReviewStore(cards: ["v#past": conjCard("v#past", reviewed: t(2))])
        let merged = SyncMerge.conjugationReviewStores(a, b)
        #expect(merged.cards.count == 2)
        #expect(merged.card(for: "v#te") != nil)
        #expect(merged.card(for: "v#past") != nil)
    }

    @Test("empty remote is a no-op (backward compatible with a peer that has no cards)")
    func emptyRemoteNoOp() {
        let local = ConjugationReviewStore(cards: ["v#te": conjCard("v#te", reviewed: t(0))])
        let merged = SyncMerge.conjugationReviewStores(local, ConjugationReviewStore())
        #expect(merged.cards == local.cards)
    }

    @Test("merge is idempotent")
    func idempotent() {
        let a = ConjugationReviewStore(cards: ["v#te": conjCard("v#te", reviewed: t(0)),
                                               "v#past": conjCard("v#past", reviewed: nil)])
        let b = ConjugationReviewStore(cards: ["v#te": conjCard("v#te", reviewed: t(100)),
                                               "w#ない": conjCard("w#ない", reviewed: t(5))])
        let once = SyncMerge.conjugationReviewStores(a, b)
        let twice = SyncMerge.conjugationReviewStores(a, once)
        #expect(once.cards == twice.cards)
    }
}

@Suite("SyncMerge — ride history")
struct RideRecordMergeTests {

    @Test("union by id, deduped, sorted oldest-first")
    func unionSorted() {
        let shared = UUID()
        let a = [record(shared, at: t(10)), record(UUID(), at: t(30))]
        let b = [record(shared, at: t(10)), record(UUID(), at: t(20))]
        let merged = SyncMerge.rideRecords(a, b)
        #expect(merged.count == 3)                                  // shared counted once
        #expect(merged.map(\.date) == [t(10), t(20), t(30)])       // sorted ascending
    }

    @Test("overflow trims the OLDEST, keeping newest up to the cap")
    func trimOldest() {
        let a = (0..<6).map { record(UUID(), at: t(Double($0))) }       // t0..t5
        let b = (6..<12).map { record(UUID(), at: t(Double($0))) }      // t6..t11
        let merged = SyncMerge.rideRecords(a, b, cap: 8)
        #expect(merged.count == 8)
        #expect(merged.first?.date == t(4))   // dropped t0..t3, kept t4..t11
        #expect(merged.last?.date == t(11))
    }

    @Test("two sub-cap histories that overflow when combined keep newest, not one side's")
    func combinedOverflow() {
        // Interleaved dates so trimming the oldest must mix both inputs.
        let a = (0..<1500).map { record(UUID(), at: t(Double($0 * 2))) }       // even seconds
        let b = (0..<1500).map { record(UUID(), at: t(Double($0 * 2 + 1))) }   // odd seconds
        let merged = SyncMerge.rideRecords(a, b)   // cap = 2000
        #expect(merged.count == 2000)
        #expect(merged.last?.date == t(2999))      // newest overall retained
    }

    @Test("merge is idempotent")
    func idempotent() {
        let shared = UUID()
        let a = [record(shared, at: t(10)), record(UUID(), at: t(30))]
        let b = [record(shared, at: t(10)), record(UUID(), at: t(20))]
        let once = SyncMerge.rideRecords(a, b)
        let twice = SyncMerge.rideRecords(a, once)
        #expect(once == twice)
    }
}

@Suite("SyncMerge — lifetime odometer (G-Counter)")
struct OdometerMergeTests {

    @Test("concurrent offline rides on two devices SUM, not max (the bug a shared counter had)")
    func concurrentSum() {
        var a = OdometerLog()
        a.record(deviceID: "A", words: 50, distanceMeters: 500)   // device A offline +50
        var b = OdometerLog()
        b.record(deviceID: "B", words: 20, distanceMeters: 200)   // device B offline +20
        let merged = SyncMerge.odometers(a, b)
        #expect(merged.totalWords == 70)                          // not 50
        #expect(merged.totalDistanceMeters == 700)
        #expect(merged.totalRuns == 2)
    }

    @Test("same device on both sides → field-wise max, never double-counts")
    func sameDeviceMax() {
        var stale = OdometerLog(); stale.record(deviceID: "A", words: 30, distanceMeters: 300)
        var fresh = OdometerLog()
        fresh.record(deviceID: "A", words: 30, distanceMeters: 300)
        fresh.record(deviceID: "A", words: 25, distanceMeters: 250)   // A now at 55
        let merged = SyncMerge.odometers(stale, fresh)
        #expect(merged.totalWords == 55)        // max(30, 55), not 85
        #expect(merged.totalRuns == 2)
    }

    @Test("a fresh device reconstructs the peer's full lifetime by pulling its slot")
    func freshDevicePullsPeer() {
        var peer = OdometerLog()
        peer.record(deviceID: "A", words: 1000, distanceMeters: 9000, runs: 40)
        let fresh = OdometerLog()                 // brand-new device, empty
        let merged = SyncMerge.odometers(fresh, peer)
        #expect(merged.totalWords == 1000)
        #expect(merged.totalRuns == 40)
    }

    @Test("odometer merge is idempotent and order-independent")
    func idempotentCommutative() {
        var a = OdometerLog(); a.record(deviceID: "A", words: 10, distanceMeters: 100)
        var b = OdometerLog(); b.record(deviceID: "B", words: 7, distanceMeters: 70)
        let ab = SyncMerge.odometers(a, b)
        let ba = SyncMerge.odometers(b, a)
        #expect(ab == ba)
        #expect(SyncMerge.odometers(a, ab) == ab)
    }
}

@Suite("SyncMerge — saved words")
struct SavedWordsMergeTests {

    @Test("union keeps words saved on either device, deduped, local order first")
    func union() {
        let a = SavedWordsStore(ids: ["x", "y"])
        let b = SavedWordsStore(ids: ["y", "z"])
        #expect(SyncMerge.savedWords(a, b).ids == ["x", "y", "z"])
        // Order-dependent (local first), but the set is commutative.
        #expect(Set(SyncMerge.savedWords(b, a).ids) == ["x", "y", "z"])
    }

    @Test("merge is idempotent")
    func idempotent() {
        let a = SavedWordsStore(ids: ["a"])
        let b = SavedWordsStore(ids: ["b", "a"])
        let once = SyncMerge.savedWords(a, b)
        #expect(once.ids == ["a", "b"])
        #expect(SyncMerge.savedWords(a, once).ids == once.ids)
    }
}
