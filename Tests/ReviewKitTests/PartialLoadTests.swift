import Testing
import Foundation
@testable import ReviewKit
import PersistKit

/// End-to-end for the store the app can least afford to lose: months of SM-2 progress that
/// exists nowhere else once the next save overwrites it.
///
/// These are golden fixtures written as JSON text rather than round-trips, because the thing
/// under test is what happens to a file THIS version did not write — an older one, a newer
/// one, or a damaged one.
@Suite("ReviewStore — a damaged file costs the damaged cards only")
struct PartialLoadTests {

    private func temp() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("review-\(UUID().uuidString).json")
    }

    private func write(_ json: String) throws -> URL {
        let url = temp()
        try Data(json.utf8).write(to: url)
        return url
    }

    /// A card as the app writes it today.
    private func cardJSON(_ id: String, due: String = "760000000") -> String {
        """
        "\(id)": {"id":"\(id)","easeFactor":2.5,"interval":3,"repetitions":2,
                  "dueDate":\(due),"lapses":0,"totalReviews":4,"totalMistakes":1}
        """
    }

    @Test("one card missing a field costs that card, not the other two")
    func oneBadCard() throws {
        let url = try write("""
        {"cards": {\(cardJSON("a")), "b": {"id":"b"}, \(cardJSON("c"))}}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let (store, outcome) = ReviewStore.loadReporting(from: url)
        // "b" is not lost — SRSCard's tolerant decoder fills a fresh card's defaults, so a
        // half-written card comes back due rather than vanishing.
        #expect(store.count == 3, "got \(store.count) cards")
        #expect(store.card(for: "b")?.easeFactor == SRSCard.initialEaseFactor)
        #expect(outcome == .loaded)
    }

    @Test("a card with no id at all is the one thing that IS dropped")
    func cardWithoutID() throws {
        // Everything else can default; an id cannot be invented, and a card that cannot be
        // matched to a word is unusable.
        let url = try write("""
        {"cards": {\(cardJSON("a")), "ghost": {"easeFactor":2.5}}}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let (store, outcome) = ReviewStore.loadReporting(from: url)
        #expect(store.count == 1)
        #expect(store.card(for: "a") != nil)
        #expect(outcome == .loadedWithSkips(skipped: 1))
    }

    @Test("BEFORE v1.15 this same file lost everything — the whole point")
    func theRegression() throws {
        // Written as the shape rather than the mechanism: 900 good cards and one bad one must
        // never again come back as zero.
        var entries = (0..<900).map { cardJSON("w\($0)") }
        entries.append("\"broken\": {\"id\":\"broken\",\"easeFactor\":\"not a number\"}")
        let url = try write("{\"cards\": {\(entries.joined(separator: ","))}}")
        defer { try? FileManager.default.removeItem(at: url) }

        let (store, _) = ReviewStore.loadReporting(from: url)
        #expect(store.count >= 900, "lost the file to one bad card again: \(store.count)")
    }

    @Test("a file from a newer version loads — unknown fields are ignored")
    func forwardCompatible() throws {
        let url = try write("""
        {"cards": {"a": {"id":"a","easeFactor":2.5,"interval":3,"repetitions":2,
                         "dueDate":760000000,"lapses":0,"totalReviews":4,"totalMistakes":1,
                         "confidenceFromTheFuture":0.8}},
         "schemaVersion": 99}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let (store, outcome) = ReviewStore.loadReporting(from: url)
        #expect(store.count == 1)
        #expect(outcome == .loaded)
    }

    @Test("undecodable bytes are quarantined, not silently discarded")
    func quarantine() throws {
        let url = try write("{ not json at all")
        let corrupt = url.appendingPathExtension("corrupt")
        defer { try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: corrupt) }

        let (store, outcome) = ReviewStore.loadReporting(from: url)
        #expect(store.count == 0)
        #expect(outcome == .undecodable)
        #expect(FileManager.default.fileExists(atPath: corrupt.path),
                "the only copy of the user's progress was thrown away")
    }

    @Test("a missing file is a fresh install, and is safe to write")
    func freshInstall() {
        let (store, outcome) = ReviewStore.loadReporting(from: temp())
        #expect(store.count == 0)
        #expect(outcome == .missing)
        #expect(LossyLoad.isSafeToWrite(outcome))
    }
}
