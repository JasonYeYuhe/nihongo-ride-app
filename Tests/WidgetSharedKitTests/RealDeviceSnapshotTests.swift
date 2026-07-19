import Testing
import Foundation
@testable import WidgetSharedKit

/// Pins the wire format against a snapshot the REAL iOS app actually wrote.
///
/// Every other test in this suite builds a `WidgetSnapshot` in memory, so all of them
/// would keep passing if the app and the widget disagreed about what lands on disk —
/// the encoder and decoder are the same code, so a shared mistake is invisible. The
/// bytes below are not hand-written: they were produced by running the v1.11 iOS build
/// in a simulator (real App Group container, real entitlement, real
/// `refreshWidgetSnapshot`) after seeding `review.json` with 3 cards due today and 2 due
/// in 3 days, then copied verbatim out of
/// `group.com.jasonye.nihongoride/widget-snapshot.json`.
///
/// That environment is the one thing `swift run` cannot reach — it has no App Group
/// entitlement, so the write path was unverifiable until v1.11 was already live. This
/// test is what closes that gap for good: change the on-disk shape and it fails here,
/// rather than on a user's home screen where nobody would see it.
@Suite("WidgetSnapshot — a snapshot written by the real iOS app")
struct RealDeviceSnapshotTests {

    /// Verbatim bytes from the simulator's App Group container (v1.11, schema 1).
    private static let realJSON = """
    {"generatedAt":806137931.580197,"vocabDueByDay":[3,0,0,2,0,0,0,0,0,0,0,0,0,0],\
    "streakByDay":[0,0,0,0,0,0,0,0,0,0,0,0,0,0],"lifetimeWords":0,\
    "conjugationDueByDay":[0,0,0,0,0,0,0,0,0,0,0,0,0,0],"languageCode":"en","schemaVersion":1}
    """

    private func decoded() throws -> WidgetSnapshot {
        try JSONDecoder().decode(WidgetSnapshot.self, from: Data(Self.realJSON.utf8))
    }

    @Test("it decodes, with the horizon and schema the app really wrote")
    func decodes() throws {
        let snap = try decoded()
        #expect(snap.schemaVersion == 1)
        #expect(snap.vocabDueByDay.count == 14)
        #expect(snap.conjugationDueByDay.count == 14)
        #expect(snap.streakByDay.count == 14, "streakByDay must be written — a scalar streak was the phantom-streak bug")
        #expect(snap.languageCode == "en")
    }

    @Test("the stored histogram is PER-DAY and the accumulation happens on read")
    func perDayHistogramAccumulates() throws {
        let snap = try decoded()
        // What the app stored: 3 cards fell due today, 2 more fall due on day 3.
        #expect(snap.vocabDueByDay == [3, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                "the file holds a per-day histogram, NOT a running total")
        // What the widget shows: "due since you last opened the app" = sum(0...offset).
        #expect(snap.vocabDue(onDayOffset: 0) == 3)
        #expect(snap.vocabDue(onDayOffset: 2) == 3, "nothing new falls due on days 1-2")
        #expect(snap.vocabDue(onDayOffset: 3) == 5, "day 3's two cards join the ones still waiting")
        #expect(snap.vocabDue(onDayOffset: 13) == 5)
        #expect(snap.vocabDue(onDayOffset: 99) == 5, "past the horizon clamps to the full sum")
    }

    @Test("an all-zero conjugation histogram reads as zero, not as missing")
    func emptyConjugation() throws {
        let snap = try decoded()
        #expect(snap.conjugationDue(onDayOffset: 0) == 0)
        #expect(snap.conjugationDue(onDayOffset: 13) == 0)
    }
}
