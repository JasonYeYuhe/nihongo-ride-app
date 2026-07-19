import Testing
import Foundation
@testable import ReviewKit

private let cal = Calendar(identifier: .gregorian)

/// A card reviewed at `hour` on day 0 with a 1-day interval → due at `hour` on day 1.
private func card(_ id: String, dueAt: Date) -> SRSCard {
    var c = SRSCard(id: id)
    c.dueDate = dueAt
    c.interval = 1
    c.repetitions = 1
    c.lastReviewed = dueAt.addingTimeInterval(-86_400)
    return c
}

private func at(_ day: Int, _ hour: Int) -> Date {
    let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
    return cal.date(byAdding: .day, value: day, to: base)!
        .addingTimeInterval(Double(hour) * 3600)
}

/// The app has two families of "due" readers and they must never disagree:
///
///   - `dueCount` / `dueCards` — the menu footer, the badge, and what a ride actually PULLS
///   - `dueByDay` / `dueForecast` — the widget, the Ride Log, Stats, the daily notification
///
/// They disagreed for every shipped version through v1.11. `SRSCard.review` sets
/// `dueDate = reviewInstant + N days`, so a card keeps the clock time it was reviewed at;
/// the second family bucketed by calendar day and the first compared instants. Because
/// most people practise in the evening, the normal state for most of the day was: widget
/// says 12, app says 0, ride gives you none. This suite is the thing that was missing.
@Suite("Due semantics — the two families must agree")
struct DueAgreementTests {

    /// The exact shipped scenario: practise at 21:00, check at 09:00 the next morning.
    private var eveningLearner: ReviewStore {
        ReviewStore(cards: Dictionary(uniqueKeysWithValues:
            (0..<8).map { ("w\($0)", card("w\($0)", dueAt: at(1, 21))) }))
    }

    @Test("morning after an evening session: the count the widget shows is the count the app gives")
    func morningAgreement() {
        let store = eveningLearner
        let morning = at(1, 9)

        let forecastToday = store.dueByDay(asOf: morning, horizon: 14, calendar: cal)[0]
        #expect(forecastToday == 8, "the widget/Ride Log promise")

        #expect(store.dueCount(on: morning, calendar: cal) == 8,
                "the menu footer must not say 0 while the widget says 8")
        #expect(store.dueCards(on: morning, calendar: cal).count == 8,
                "and a ride must actually pull them — the promise has to be keepable")
    }

    @Test("a card due tomorrow is not counted today, in either family")
    func tomorrowIsNotToday() {
        let store = ReviewStore(cards: ["w": card("w", dueAt: at(2, 9))])
        let today = at(1, 23)
        #expect(store.dueCount(on: today, calendar: cal) == 0)
        #expect(store.dueByDay(asOf: today, horizon: 14, calendar: cal)[0] == 0)
    }

    @Test("agreement holds at every hour of the day, not just the convenient ones")
    func agreesAllDay() {
        let store = eveningLearner
        for hour in 0..<24 {
            let now = at(1, hour)
            let forecast = store.dueByDay(asOf: now, horizon: 14, calendar: cal)[0]
            let count = store.dueCount(on: now, calendar: cal)
            #expect(count == forecast, "hour \(hour): forecast \(forecast) vs count \(count)")
        }
    }

    @Test("an overdue card stays due — day granularity must not expire anything early")
    func overdueStaysDue() {
        let store = ReviewStore(cards: ["w": card("w", dueAt: at(-3, 21))])
        let now = at(1, 9)
        #expect(store.dueCount(on: now, calendar: cal) == 1)
        #expect(store.dueByDay(asOf: now, horizon: 14, calendar: cal)[0] == 1,
                "an overdue card belongs in today's bucket")
    }

    @Test("the notification planner's end-of-day instant still lands on the same answer")
    func plannerWorkaroundStillAgrees() {
        // DueReminderPlanner passes one-second-before-midnight rather than `now`. That
        // predates this fix and must keep working: 23:59:59 is still inside the same day,
        // so the day-granular cutoff is identical.
        let store = eveningLearner
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: at(1, 0)))!
            .addingTimeInterval(-1)
        #expect(store.dueCount(on: endOfDay, calendar: cal) == 8)
        #expect(store.dueCount(on: at(1, 9), calendar: cal) == 8)
    }
}
