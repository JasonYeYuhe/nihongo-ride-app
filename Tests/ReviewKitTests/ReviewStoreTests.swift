import Testing
import Foundation
@testable import ReviewKit


@Suite("Due counts never promise a card the run cannot produce — v1.18")
struct OrphanedCardTests {

    private func store(with ids: [String], due: Bool) -> ReviewStore {
        // A card created at `when` is due at `when` — SRSCard(id:createdAt:) sets dueDate to
        // its creation date, so backdating creation makes it due and post-dating does not.
        let when = due ? Date().addingTimeInterval(-86_400) : Date().addingTimeInterval(86_400)
        let cards = Dictionary(uniqueKeysWithValues:
            ids.map { ($0, SRSCard(id: $0, createdAt: when)) })
        return ReviewStore(cards: cards)
    }

    /// The bug this fixes: the store counted every stored card while GameSession.make dropped
    /// ids that no longer resolve, so the badge and the daily push could promise more words
    /// than a run would ever hand over.
    @Test("a card whose word no longer exists is not counted as due")
    func orphanNotCounted() {
        let s = store(with: ["alive", "retired"], due: true)
        #expect(s.dueCount() == 2)                                    // old behaviour, unchanged
        #expect(s.dueCount(resolves: { $0 != "retired" }) == 1)
    }

    @Test("a card whose word no longer exists is not handed to a run")
    func orphanNotQueued() {
        let s = store(with: ["alive", "retired"], due: true)
        let ids = s.dueCards(resolves: { $0 != "retired" }).map(\.id)
        #expect(ids == ["alive"])
    }

    /// The predicate must not disturb the existing meaning of "due".
    @Test("resolvability does not override the due date")
    func stillRespectsDueDate() {
        let s = store(with: ["future"], due: false)
        #expect(s.dueCount(resolves: { _ in true }) == 0)
        #expect(s.dueCards(resolves: { _ in true }).isEmpty)
    }
}
