import Testing
import Foundation
@testable import VocabKit

/// A percentage written in a doc comment is a claim about data that grows (v1.32 §F1).
///
/// `ReadingNotes.note(for:)` said *"nil for the 96% of the corpus that needs none"*. Measured
/// 2026-09-10: 66 notes against 7,071 entries is **99.07%** without one. The number was probably
/// right when it was written; the corpus has grown by thousands of entries since, and nothing
/// re-read the sentence.
///
/// That is the same shape as `AboutView`'s "183 Practice-mode passages" — corrected in the same
/// pass, and worse, because twelve lines below it the same screen computed and displayed the real
/// count of 233. **One screen contradicting itself is this repo's signature defect;** a number in
/// prose that quietly stops matching the data is the version of it nobody can see.
///
/// So this recomputes the figure and fails when the comment stops being true, rather than when
/// somebody happens to re-check. The band is ±1 percentage point: tighter would fail on a single
/// batch of new words, which is drift the comment tolerates and a reader would not be misled by;
/// wider would let it become the old lie again.
@Suite("The reading-note coverage claim is true")
struct ReadingNoteCoverageTests {

    @Test("the share of the corpus needing no reading note matches the documented 99%")
    func coverageMatchesTheDocumentedFigure() throws {
        let corpus = VocabStore.shared.entries.count
        #expect(corpus > 5_000, "only \(corpus) entries loaded — the store did not load")

        let notes = ReadingNotes.all.count
        #expect(ReadingNotes.isLoaded, "the reading-note file did not load; every card lost its note")
        #expect(notes > 0)

        let withoutNote = Double(corpus - notes) / Double(corpus) * 100
        #expect(withoutNote >= 98 && withoutNote < 100,
                Comment(rawValue: "\(notes) notes over \(corpus) entries is "
                        + "\(String(format: "%.2f", withoutNote))% without one; "
                        + "ReadingNotes' doc comment says 99%"))
    }

    /// The instrument's own control. Every assertion above is satisfied by a corpus with no notes
    /// at all — `withoutNote` would be 100% and the band's upper bound is what catches it — but
    /// "the notes loaded" deserves its own statement, because a missing resource file is the
    /// failure `isLoaded` was added for and it degrades silently.
    @Test("a note that exists is reachable through the public accessor")
    func aKnownNoteResolves() throws {
        let anID = try #require(ReadingNotes.all.keys.sorted().first)
        let note = try #require(ReadingNotes.note(for: anID),
                                "`all` holds \(anID) and `note(for:)` does not return it")
        #expect(!note.common.isEmpty)
        // …and an id that has no note must come back nil, or the accessor is not discriminating.
        #expect(ReadingNotes.note(for: "definitely-not-an-entry-id") == nil)
    }
}
