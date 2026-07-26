import Testing
@testable import WidgetSharedKit

/// The widget must never claim the learner is done while it is simultaneously displaying
/// work that is due. That claim has been wrong twice — the small layout said "all caught up"
/// with conjugations due (v1.13 §B), and after that was fixed the MEDIUM layout said it while
/// the column beside it showed those same conjugations (v1.14 §D). Both times the condition
/// was written out per layout and one copy was missed.
///
/// v1.15 gives the five layouts one predicate. These tests pin that predicate, so the third
/// occurrence has to get past an assertion rather than past a reviewer.
@Suite("Widget — never claims caught up while work is due")
struct WidgetHonestyTests {

    private func data(vocab: Int, conj: Int, hasData: Bool = true, stale: Bool = false) -> ReviewWidgetData {
        ReviewWidgetData(hasData: hasData, stale: stale, vocabDue: vocab,
                         conjugationDue: conj, streakDays: 3)
    }

    @Test("caught up only when BOTH stores are empty")
    func bothMustBeZero() {
        #expect(data(vocab: 0, conj: 0).isAllCaughtUp)
        #expect(!data(vocab: 0, conj: 1).isAllCaughtUp, "conjugations due, still claimed caught up")
        #expect(!data(vocab: 1, conj: 0).isAllCaughtUp)
        #expect(!data(vocab: 3, conj: 4).isAllCaughtUp)
    }

    @Test("a widget with no snapshot yet is not 'caught up'")
    func noDataIsNotCaughtUp() {
        // Before the app has ever run there is nothing in the App Group container. Zero due
        // is then an absence of information, not an achievement — the layouts show "open
        // Nihongo Ride" for this, and the predicate must not tell them otherwise.
        #expect(!data(vocab: 0, conj: 0, hasData: false).isAllCaughtUp)
        #expect(!ReviewWidgetData.empty.isAllCaughtUp)
    }

    @Test("the total is what the badge shows — both stores, summed once")
    func totalIsBothStores() {
        #expect(data(vocab: 12, conj: 3).totalDue == 15)
        #expect(data(vocab: 0, conj: 0).totalDue == 0)
        #expect(ReviewWidgetData.placeholder.totalDue == 15)
    }

    @Test("staleness is independent of the counts")
    func stalenessIsOrthogonal() {
        // A stale snapshot can hold any numbers, including zeroes; "caught up" describes the
        // counts and the hint describes their age. Conflating them is how a widget ends up
        // stating a stale zero as an accomplishment.
        #expect(data(vocab: 0, conj: 0, stale: true).isAllCaughtUp)
        #expect(data(vocab: 0, conj: 0, stale: true).stale)
        #expect(!data(vocab: 5, conj: 0, stale: true).isAllCaughtUp)
    }
}
