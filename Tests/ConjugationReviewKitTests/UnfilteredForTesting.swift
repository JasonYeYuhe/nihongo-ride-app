import Foundation
@testable import ConjugationReviewKit

/// The unfiltered counts, for tests only — the `ConjugationReviewStore` half.
///
/// See `ReviewKitTests/UnfilteredForTesting.swift` for why the production defaults were
/// removed. This is a separate copy rather than a shared helper because it extends a different
/// type in a different module: `ConjugationReviewKit` is a deliberate zero-dependency sibling
/// of `ReviewKit` (PLAN-V1.8 §B), so there is no shared supertype to hang one extension off,
/// and nothing here can drift out of step with the other file — they describe different APIs.
extension ConjugationReviewStore {
    static var everythingResolves: (String) -> Bool { { _ in true } }

    func dueCards(on date: Date = Date(), limit: Int = 100,
                  calendar: Calendar = .current) -> [ConjugationSRSCard] {
        dueCards(on: date, limit: limit, calendar: calendar, resolves: Self.everythingResolves)
    }

    func dueCount(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        dueCount(on: date, calendar: calendar, resolves: Self.everythingResolves)
    }

    func dueByDay(asOf date: Date = Date(), horizon: Int,
                  calendar: Calendar = .current) -> [Int] {
        dueByDay(asOf: date, horizon: horizon, calendar: calendar, resolves: Self.everythingResolves)
    }

    func dueForecast(asOf date: Date = Date(), calendar: Calendar = .current) -> Forecast {
        dueForecast(asOf: date, calendar: calendar, resolves: Self.everythingResolves)
    }

    func leeches() -> [ConjugationSRSCard] { leeches(resolves: Self.everythingResolves) }

    func reviewedCount() -> Int { reviewedCount(resolves: Self.everythingResolves) }

    func weakestFormCards(limit: Int = 100) -> [ConjugationSRSCard] {
        weakestFormCards(limit: limit, resolves: Self.everythingResolves)
    }
}
