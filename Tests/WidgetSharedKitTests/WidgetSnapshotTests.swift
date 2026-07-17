import Testing
import Foundation
@testable import WidgetSharedKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

@Suite("WidgetSnapshot — accumulation, staleness, round-trip")
struct WidgetSnapshotTests {

    private func snap(_ vocab: [Int], conj: [Int] = [], gen: Date = t0) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: gen, vocabDueByDay: vocab, conjugationDueByDay: conj,
                       streakDays: 3, lifetimeWords: 100)
    }

    // MARK: Accumulation — the one subtle rule

    @Test("day k shows the SUM of buckets 0...k, not bucket k alone")
    func accumulates() {
        let s = snap([2, 1, 0, 5])
        #expect(s.vocabDue(onDayOffset: 0) == 2)
        #expect(s.vocabDue(onDayOffset: 1) == 3)   // 2 + 1
        #expect(s.vocabDue(onDayOffset: 2) == 3)   // 2 + 1 + 0
        #expect(s.vocabDue(onDayOffset: 3) == 8)   // 2 + 1 + 0 + 5
    }

    @Test("an offset past the horizon clamps to the full total, never crashes")
    func clampsPastHorizon() {
        let s = snap([2, 1, 0, 5])
        #expect(s.vocabDue(onDayOffset: 99) == 8)
        #expect(s.vocabDue(onDayOffset: 4) == 8)
    }

    @Test("a negative offset clamps to bucket 0")
    func clampsNegative() {
        #expect(snap([2, 1, 5]).vocabDue(onDayOffset: -3) == 2)
    }

    @Test("an empty histogram is zero, not a crash")
    func emptyHistogram() {
        #expect(snap([]).vocabDue(onDayOffset: 0) == 0)
        #expect(snap([]).vocabDue(onDayOffset: 5) == 0)
    }

    @Test("vocab and conjugation accumulate independently")
    func independentStores() {
        let s = snap([1, 1], conj: [10, 0, 0])
        #expect(s.vocabDue(onDayOffset: 5) == 2)
        #expect(s.conjugationDue(onDayOffset: 5) == 10)
    }

    // MARK: Staleness

    @Test("fresh within the horizon, stale once the day count exceeds it")
    func staleness() {
        let cal = Calendar(identifier: .gregorian)
        let s = snap([0, 0, 0, 0, 0])   // 5-day horizon
        #expect(!s.isStale(asOf: t0, calendar: cal))
        #expect(!s.isStale(asOf: t0.addingTimeInterval(4 * 86_400), calendar: cal))
        #expect(s.isStale(asOf: t0.addingTimeInterval(5 * 86_400), calendar: cal),
                "day 5 is past a 5-bucket (0...4) histogram")
    }

    // MARK: Round-trip through the store

    @Test("write then read round-trips exactly through a container dir")
    func roundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nr-widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = snap([2, 1, 0, 5], conj: [0, 3])
        try WidgetSnapshotStore.write(s, to: dir).get()   // throws (fails the test) on write error
        #expect(WidgetSnapshotStore.read(from: dir) == s)
    }

    @Test("a nil container fails the write instead of crashing")
    func writeWithoutContainer() {
        #expect(throws: WidgetSnapshotStore.WriteError.containerUnavailable) {
            try WidgetSnapshotStore.write(snap([1]), to: nil).get()
        }
    }

    @Test("reads never throw: missing, corrupt, and newer-schema all degrade to nil")
    func readNeverThrows() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nr-widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(WidgetSnapshotStore.read(from: dir) == nil, "missing file → nil")

        try Data("{garbage".utf8).write(to: dir.appendingPathComponent(WidgetSnapshotStore.filename))
        #expect(WidgetSnapshotStore.read(from: dir) == nil, "corrupt file → nil, not a throw")

        var newer = snap([1])
        newer.schemaVersion = WidgetSnapshot.currentSchema + 1
        _ = WidgetSnapshotStore.write(newer, to: dir)
        #expect(WidgetSnapshotStore.read(from: dir) == nil, "a newer schema → nil, don't mis-render")
    }
}
