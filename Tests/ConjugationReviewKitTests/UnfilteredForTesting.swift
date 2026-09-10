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

    /// The `rideable:` half (v1.32 §C1). Same argument as `everythingResolves`: the production
    /// default was removed so a NEW counting method cannot silently ship unfiltered, and the
    /// noise that removal creates is absorbed here rather than at 40-odd call sites.
    static var everythingRideable: (ConjugationSRSCard) -> Bool { { _ in true } }

    func dueCards(on date: Date = Date(), limit: Int = 100,
                  calendar: Calendar = .current) -> [ConjugationSRSCard] {
        dueCards(on: date, limit: limit, calendar: calendar,
                 resolves: Self.everythingResolves, rideable: Self.everythingRideable)
    }

    func dueCount(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        dueCount(on: date, calendar: calendar,
                 resolves: Self.everythingResolves, rideable: Self.everythingRideable)
    }

    func dueByDay(asOf date: Date = Date(), horizon: Int,
                  calendar: Calendar = .current) -> [Int] {
        dueByDay(asOf: date, horizon: horizon, calendar: calendar,
                 resolves: Self.everythingResolves, rideable: Self.everythingRideable)
    }

    func dueForecast(asOf date: Date = Date(), calendar: Calendar = .current) -> Forecast {
        dueForecast(asOf: date, calendar: calendar,
                    resolves: Self.everythingResolves, rideable: Self.everythingRideable)
    }

    func leeches() -> [ConjugationSRSCard] {
        leeches(resolves: Self.everythingResolves, rideable: Self.everythingRideable)
    }

    func reviewedCount() -> Int { reviewedCount(resolves: Self.everythingResolves) }

    func weakestFormCards(limit: Int = 100) -> [ConjugationSRSCard] {
        weakestFormCards(limit: limit,
                         resolves: Self.everythingResolves, rideable: Self.everythingRideable)
    }

    // MARK: `resolves:` given, `rideable:` defaulted
    //
    // The suite has tests that exercise `resolves:` specifically — they predate `rideable:` and
    // are about a different predicate. These keep them saying exactly what they said before,
    // rather than editing them to carry an argument they are not about. A test rewritten to
    // mention a second predicate stops being evidence about the first one.

    func dueCards(on date: Date = Date(), limit: Int = 100, calendar: Calendar = .current,
                  resolves: (String) -> Bool) -> [ConjugationSRSCard] {
        dueCards(on: date, limit: limit, calendar: calendar,
                 resolves: resolves, rideable: Self.everythingRideable)
    }

    func dueCount(on date: Date = Date(), calendar: Calendar = .current,
                  resolves: (String) -> Bool) -> Int {
        dueCount(on: date, calendar: calendar, resolves: resolves, rideable: Self.everythingRideable)
    }

    func dueByDay(asOf date: Date = Date(), horizon: Int, calendar: Calendar = .current,
                  resolves: (String) -> Bool) -> [Int] {
        dueByDay(asOf: date, horizon: horizon, calendar: calendar,
                 resolves: resolves, rideable: Self.everythingRideable)
    }

    func dueForecast(asOf date: Date = Date(), calendar: Calendar = .current,
                     resolves: (String) -> Bool) -> Forecast {
        dueForecast(asOf: date, calendar: calendar,
                    resolves: resolves, rideable: Self.everythingRideable)
    }

    func leeches(resolves: (String) -> Bool) -> [ConjugationSRSCard] {
        leeches(resolves: resolves, rideable: Self.everythingRideable)
    }

    func weakestFormCards(limit: Int = 100, resolves: (String) -> Bool) -> [ConjugationSRSCard] {
        weakestFormCards(limit: limit, resolves: resolves, rideable: Self.everythingRideable)
    }
}
