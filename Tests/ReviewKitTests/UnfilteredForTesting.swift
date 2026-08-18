import Foundation
@testable import ReviewKit

/// The unfiltered counts, for tests only.
///
/// `resolves:` used to default to `{ _ in true }`, and the default was the trap: omitting the
/// argument compiled clean and silently returned a number computed over cards whose words no
/// longer exist. That shipped twice — v1.22 found four such call sites, v1.23 two more — and
/// each time the mistake was *forgetting*, which no runtime check can catch, because a missing
/// argument is indistinguishable from a store where everything resolves.
///
/// v1.23 kept the default on a count: 57 of 75 call sites were tests that build stores where
/// everything resolves anyway. All three reviewers said that was the wrong call and they were
/// right — the compiler is a stronger gate than a source scanner, and the test noise has this
/// answer, which neither the scanner nor the default needed.
///
/// It lives in the test target on purpose. Putting it on `ReviewStore` itself would recreate
/// the very thing being removed: a way to get an unfiltered number without saying so.
extension ReviewStore {
    /// Every card, unfiltered — these tests build stores where every id resolves by
    /// construction, so the filter has nothing to do. A computed property rather than a stored
    /// one because a closure is not Sendable and a stored static would not compile under strict
    /// concurrency.
    static var everythingResolves: (String) -> Bool { { _ in true } }

    func dueCards(on date: Date = Date(), limit: Int = 100,
                  calendar: Calendar = .current) -> [SRSCard] {
        dueCards(on: date, limit: limit, calendar: calendar, resolves: Self.everythingResolves)
    }

    func dueCount(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        dueCount(on: date, calendar: calendar, resolves: Self.everythingResolves)
    }

    func reviewedCount() -> Int { reviewedCount(resolves: Self.everythingResolves) }

    func weakestCards(limit: Int = 100) -> [SRSCard] {
        weakestCards(limit: limit, resolves: Self.everythingResolves)
    }

    func dueByDay(asOf date: Date = Date(), horizon: Int,
                  calendar: Calendar = .current) -> [Int] {
        dueByDay(asOf: date, horizon: horizon, calendar: calendar, resolves: Self.everythingResolves)
    }

    func dueForecast(asOf date: Date = Date(), calendar: Calendar = .current) -> DueForecast {
        dueForecast(asOf: date, calendar: calendar, resolves: Self.everythingResolves)
    }

    func leeches() -> [SRSCard] { leeches(resolves: Self.everythingResolves) }
}
