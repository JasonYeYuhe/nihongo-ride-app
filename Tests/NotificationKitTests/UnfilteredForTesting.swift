import Foundation
import ReviewKit
@testable import NotificationKit

/// The unfiltered planner, for tests only.
///
/// `vocabResolves` used to default to `{ _ in true }` and `conjugationDue` to `{ _, _ in 0 }`.
/// v1.24 §C removed every such default from the review stores and MISSED this file, while
/// `docs/STATE-2026-08-18.md` recorded that all ten were gone — a document asserting a property
/// nothing checked, which is the defect shape this project keeps logging, committed in the very
/// change that was meant to close it.
///
/// The defaults mattered more here than anywhere else. This planner writes the 20:00 push and
/// the app-icon badge, so an unfiltered count tells a learner that a word is due when no run can
/// ever produce it and no review can ever clear it — the planner's own doc comment says that
/// already shipped once.
///
/// As with the review stores, the convenience lives in the test target: on the planner it would
/// re-create exactly what was removed.
extension DueReminderPlanner {
    static func plan(store: ReviewStore, from now: Date, hour: Int,
                     days: Int = 7, calendar: Calendar = .current) -> [DueReminder] {
        plan(store: store, conjugationDue: { _, _ in 0 }, vocabResolves: { _ in true },
             from: now, hour: hour, days: days, calendar: calendar)
    }

    static func plan(store: ReviewStore, conjugationDue: @escaping (Date, Calendar) -> Int,
                     from now: Date, hour: Int,
                     days: Int = 7, calendar: Calendar = .current) -> [DueReminder] {
        plan(store: store, conjugationDue: conjugationDue, vocabResolves: { _ in true },
             from: now, hour: hour, days: days, calendar: calendar)
    }

    /// The variant that exercises the filter itself while leaving the conjugation half alone.
    static func plan(store: ReviewStore, vocabResolves: @escaping (String) -> Bool,
                     from now: Date, hour: Int,
                     days: Int = 7, calendar: Calendar = .current) -> [DueReminder] {
        plan(store: store, conjugationDue: { _, _ in 0 }, vocabResolves: vocabResolves,
             from: now, hour: hour, days: days, calendar: calendar)
    }
}
