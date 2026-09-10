import Testing
import Foundation
@testable import ConjugationReviewKit

/// The `rideable:` half of every outstanding-work count (v1.32 §C1).
///
/// `resolves:` answers *does the verb still exist*; `rideable:` answers *can the drill build a
/// prompt for this (verb, form) pair at all*. The second is strictly stronger and the gap is
/// reachable: `verbClass` is read from the corpus's opaque `vc` field, so an entry can keep its
/// id and stop being conjugable. A card in that gap is never graded by any drill — the builder
/// skips it and pads the slot — so it stays overdue forever and inflates every number here.
///
/// **Why this suite exists separately from the app-level one.** Two of the six readouts that
/// count these cards — the home-screen widget and the app-icon badge / reminder body — cannot be
/// exercised from `NihongoRideAppTests`: both are gated on `Bundle.main.bundleIdentifier != nil`,
/// which is the guard that stops a test run overwriting the owner's real widget, and which must
/// not be weakened to reach them. `dueByDay` is the widget's number and `dueCount` is the badge's,
/// so this file is where those two are actually held.
@Suite("Outstanding work excludes a card no drill can build")
struct RideableFilterTests {

    /// Two overdue cards on two different verbs; `stranded` is the one no drill can build.
    private func store(now: Date) -> ConjugationReviewStore {
        var s = ConjugationReviewStore()
        _ = s.record(promptID: "live#te", outcome: .init(completed: false, mistakes: 8), on: now)
        _ = s.record(promptID: "stranded#te", outcome: .init(completed: false, mistakes: 8), on: now)
        return s
    }

    private let rideable: (ConjugationSRSCard) -> Bool = { $0.sourceID != "stranded" }

    /// Every member that answers "how much work is outstanding", in one test, because the
    /// failure this guards against is a fix applied to one of them.
    ///
    /// Each line is paired with the unfiltered shim call directly above it: without the pair,
    /// "1" is equally consistent with a store that only ever held one card.
    @Test("every outstanding-work count drops a card the drill cannot build")
    func everyOutstandingCountDropsIt() {
        let now = Date()
        var s = store(now: now)
        let tomorrow = now.addingTimeInterval(24 * 3600)

        #expect(s.dueCount(on: tomorrow) == 2)
        #expect(s.dueCount(on: tomorrow, resolves: ConjugationReviewStore.everythingResolves, rideable: rideable) == 1)

        #expect(s.dueCards(on: tomorrow).count == 2)
        #expect(s.dueCards(on: tomorrow, resolves: ConjugationReviewStore.everythingResolves,
                           rideable: rideable).count == 1)

        // The widget's number. Nothing in the app target can read this one back.
        #expect(s.dueByDay(asOf: tomorrow, horizon: 7).first == 2)
        #expect(s.dueByDay(asOf: tomorrow, horizon: 7, resolves: ConjugationReviewStore.everythingResolves,
                           rideable: rideable).first == 1)

        // The Stats screen's number.
        #expect(s.dueForecast(asOf: tomorrow).today == 2)
        #expect(s.dueForecast(asOf: tomorrow, resolves: ConjugationReviewStore.everythingResolves,
                              rideable: rideable).today == 1)

        // "N tough forms" is a promise of work the learner can drill down, so a card no drill
        // can build belongs out of it for the same reason a withdrawn verb's does.
        for _ in 0..<9 {
            _ = s.record(promptID: "live#te", outcome: .init(completed: false, mistakes: 5), on: now)
            _ = s.record(promptID: "stranded#te", outcome: .init(completed: false, mistakes: 5), on: now)
        }
        #expect(s.leeches().count == 2)
        #expect(s.leeches(resolves: ConjugationReviewStore.everythingResolves, rideable: rideable).count == 1)

        #expect(s.weakestFormCards().count == 2)
        #expect(s.weakestFormCards(resolves: ConjugationReviewStore.everythingResolves,
                                   rideable: rideable).count == 1)
    }

    /// "Returns one fewer" is satisfied by a filter that drops the WRONG card, and under the
    /// `{ _ in true }` shim an ignored parameter and an applied one are indistinguishable. So
    /// pin that each member CONSULTS the closure and is handed the whole card — not the source
    /// id, not the prompt key. This mirrors the two pinning tests `resolves:` already has.
    @Test("every one of them consults the closure, and is handed the CARD")
    func eachMemberConsultsTheClosure() {
        let now = Date()
        var s = store(now: now)
        for _ in 0..<9 {
            _ = s.record(promptID: "live#te", outcome: .init(completed: false, mistakes: 5), on: now)
        }
        let tomorrow = now.addingTimeInterval(24 * 3600)

        let calls: [(String, (@escaping (ConjugationSRSCard) -> Bool) -> Void)] = [
            ("dueCount", { f in _ = s.dueCount(on: tomorrow, resolves: ConjugationReviewStore.everythingResolves, rideable: f) }),
            ("dueCards", { f in _ = s.dueCards(on: tomorrow, resolves: ConjugationReviewStore.everythingResolves, rideable: f) }),
            ("dueByDay", { f in _ = s.dueByDay(asOf: tomorrow, horizon: 7, resolves: ConjugationReviewStore.everythingResolves, rideable: f) }),
            ("dueForecast", { f in _ = s.dueForecast(asOf: tomorrow, resolves: ConjugationReviewStore.everythingResolves, rideable: f) }),
            ("leeches", { f in _ = s.leeches(resolves: ConjugationReviewStore.everythingResolves, rideable: f) }),
            ("weakestFormCards", { f in _ = s.weakestFormCards(resolves: ConjugationReviewStore.everythingResolves, rideable: f) }),
        ]
        for (name, call) in calls {
            var seen: [String] = []
            call({ card in seen.append(card.id); return true })
            #expect(!seen.isEmpty, "\(name) never consulted rideable:")
            #expect(seen.allSatisfy { $0.contains("#") },
                    "\(name) was handed \(seen) — the whole card's id, with its form, is the point")
        }
    }

    /// The v1.23 weak-words bug verbatim, in the two members that cap.
    ///
    /// A card the drill cannot build only ever grows more overdue, so it sorts to the FRONT of
    /// `dueCards` and to the front of `weakestFormCards` (leeches first). Filtering after the cap
    /// would let it spend a slot and hand back a short run — the exact shape that promised
    /// fifteen and rode twelve.
    @Test("the filter is applied BEFORE the cap, not after")
    func filterPrecedesTheCap() {
        let now = Date()
        var s = ConjugationReviewStore()
        // The unbuildable one is the MOST overdue, so it sorts first in every ordering here.
        _ = s.record(promptID: "stranded#te", outcome: .init(completed: false, mistakes: 9),
                     on: now.addingTimeInterval(-10 * 86_400))
        for index in 0..<3 {
            _ = s.record(promptID: "live\(index)#te", outcome: .init(completed: false, mistakes: 9), on: now)
        }
        for _ in 0..<9 {
            _ = s.record(promptID: "stranded#te", outcome: .init(completed: false, mistakes: 5), on: now)
            for index in 0..<3 {
                _ = s.record(promptID: "live\(index)#te", outcome: .init(completed: false, mistakes: 5), on: now)
            }
        }
        let tomorrow = now.addingTimeInterval(24 * 3600)

        let due = s.dueCards(on: tomorrow, limit: 2, resolves: ConjugationReviewStore.everythingResolves,
                             rideable: rideable)
        #expect(due.count == 2, "a cap of 2 must yield 2 buildable cards, not 1 plus a hole")
        #expect(!due.contains { $0.sourceID == "stranded" })

        let weakest = s.weakestFormCards(limit: 2, resolves: ConjugationReviewStore.everythingResolves,
                                         rideable: rideable)
        #expect(weakest.count == 2)
        #expect(!weakest.contains { $0.sourceID == "stranded" })
    }

    /// `reviewedCount` is the deliberate exception, asserted rather than left to a comment.
    /// "Forms practised" is a historical fact and the learner did practise it; filtering there
    /// would make a true number false. Work remaining filters; history does not.
    @Test("reviewedCount takes no rideable: — history is not outstanding work")
    func historyTakesNoRideableFilter() {
        let now = Date()
        let s = store(now: now)
        #expect(s.reviewedCount(resolves: ConjugationReviewStore.everythingResolves) == 2)
    }
}
