import Testing
import Foundation
@testable import WordListsKit

/// v1.4's saved-words deck had no size cap. v1.5 introduced a 500-word per-list cap and the
/// migration applied it with `prefix(500)` — so a user upgrading with 620 favourites lost 120
/// of them, silently, and `enqueueAllLocal` then pushed the truncated deck over the cloud
/// copy so the loss reached their other devices too.
@Suite("Favourites migration — a cap must not delete what it was not there for")
struct MigrationCapTests {

    /// `Result<Void, _>` is not Equatable (Void isn't), so match rather than compare.
    private func isCapReached(_ r: Result<Void, WordListError>) -> Bool {
        if case .failure(.wordCapReached) = r { return true }
        return false
    }

    private func succeeded(_ r: Result<Void, WordListError>) -> Bool {
        if case .success = r { return true }
        return false
    }

    private func store(seededWith count: Int) -> WordListStore {
        var s = WordListStore()
        s.ensureDefault(name: "★", now: Date())
        s.seedDefaultIDs((0..<count).map { "w\($0)" })
        return s
    }

    @Test("every legacy favourite survives the migration, past the cap")
    func nothingIsDropped() {
        let s = store(seededWith: 620)
        #expect(s.defaultList?.ids.count == 620, "lost \(620 - (s.defaultList?.ids.count ?? 0)) favourites")
        #expect(s.defaultList?.ids.contains("w619") == true, "the tail is exactly what used to go missing")
    }

    @Test("a grandfathered list still refuses NEW words")
    func capStillHoldsForAdditions() {
        // Migration may leave it over the cap; that is not a licence to keep growing.
        var s = store(seededWith: 620)
        let result = s.addWord("brand-new", to: WordList.defaultID)
        #expect(isCapReached(result), "expected a cap refusal, got \(result)")
        #expect(s.defaultList?.ids.contains("brand-new") == false)
    }

    @Test("an over-cap list drains toward the limit and can then grow again")
    func drainsBackUnderTheCap() {
        var s = store(seededWith: 502)
        for i in 0..<3 { _ = s.removeWord("w\(i)", from: WordList.defaultID) }
        #expect(s.defaultList?.ids.count == 499)
        #expect(succeeded(s.addWord("brand-new", to: WordList.defaultID)))
        #expect(s.defaultList?.ids.count == 500)
        // …and is refused again at the limit.
        #expect(isCapReached(s.addWord("one-too-many", to: WordList.defaultID)))
    }

    @Test("an ordinary migration is unaffected")
    func normalCaseUnchanged() {
        let s = store(seededWith: 40)
        #expect(s.defaultList?.ids.count == 40)
        #expect(s.defaultList?.wordMeta.isEmpty == true,
                "migration must not stamp `a`, or legacy residue beats a peer's tombstone")
    }

    @Test("duplicates in the legacy deck are still collapsed")
    func stillDedupes() {
        var s = WordListStore()
        s.ensureDefault(name: "★", now: Date())
        s.seedDefaultIDs(["a", "b", "a", "c", "b"])
        #expect(s.defaultList?.ids == ["a", "b", "c"])
    }
}
