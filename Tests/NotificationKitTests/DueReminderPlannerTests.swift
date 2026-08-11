import Testing
import Foundation
@testable import NotificationKit
import ReviewKit

/// Fixed calendar so day boundaries don't depend on the machine's locale.
private let tokyo: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return c
}()

/// 2026-06-01 09:00 JST.
private let anchor: Date = {
    var d = DateComponents()
    d.year = 2026; d.month = 6; d.day = 1; d.hour = 9
    return tokyo.date(from: d)!
}()

/// A card due at the start of `dayOffset` days from the anchor's day.
private func dueCard(_ id: String, dayOffset: Int) -> SRSCard {
    var c = SRSCard(id: id, createdAt: anchor)
    let day = tokyo.startOfDay(for: tokyo.date(byAdding: .day, value: dayOffset, to: anchor)!)
    c.dueDate = day
    c.lastReviewed = anchor
    return c
}

@Suite("DueReminderPlanner")
struct DueReminderPlannerTests {

    @Test("plans one reminder per future day, counts cumulative cards due by end of day")
    func cumulativeCounts() {
        // 2 cards due today, +1 due in 2 days, +1 due in 5 days.
        let store = ReviewStore(cards: [
            "a": dueCard("a", dayOffset: 0),
            "b": dueCard("b", dayOffset: 0),
            "c": dueCard("c", dayOffset: 2),
            "d": dueCard("d", dayOffset: 5),
        ])
        let plan = DueReminderPlanner.plan(store: store, from: anchor, hour: 20, days: 7, calendar: tokyo)

        // Today's 20:00 is still ahead of the 09:00 anchor, so day 0 is included.
        #expect(plan.count == 7)
        #expect(plan.map(\.dueCount) == [2, 2, 3, 3, 3, 4, 4])
        // All fire at 20:00 local, strictly in the future, soonest first.
        #expect(plan.allSatisfy { tokyo.component(.hour, from: $0.fireDate) == 20 })
        #expect(plan.allSatisfy { $0.fireDate > anchor })
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
    }

    @Test("days with zero due cards are skipped entirely")
    func skipsZeroDays() {
        // Nothing due until 3 days out.
        let store = ReviewStore(cards: ["x": dueCard("x", dayOffset: 3)])
        let plan = DueReminderPlanner.plan(store: store, from: anchor, hour: 20, days: 7, calendar: tokyo)
        #expect(plan.count == 4)                      // days 3,4,5,6 only
        #expect(plan.allSatisfy { $0.dueCount == 1 })
        let firstDay = tokyo.dateComponents([.day], from: plan[0].fireDate).day
        let anchorDay = tokyo.dateComponents([.day], from: anchor).day
        #expect(firstDay == (anchorDay! + 3))
    }

    @Test("today's slot is dropped once its hour has already passed")
    func pastHourDropped() {
        let store = ReviewStore(cards: ["a": dueCard("a", dayOffset: 0)])
        // Anchor is 09:00; an 08:00 reminder for today is in the past.
        let plan = DueReminderPlanner.plan(store: store, from: anchor, hour: 8, days: 7, calendar: tokyo)
        // Day 0 skipped (08:00 < 09:00), days 1…6 each still due → 6 reminders.
        #expect(plan.count == 6)
        #expect(plan.allSatisfy { $0.fireDate > anchor })
    }

    @Test("empty store → no reminders")
    func emptyStore() {
        let plan = DueReminderPlanner.plan(store: ReviewStore(), from: anchor, hour: 20, calendar: tokyo)
        #expect(plan.isEmpty)
    }

    @Test("days = 0 → no reminders")
    func zeroDays() {
        let store = ReviewStore(cards: ["a": dueCard("a", dayOffset: 0)])
        let plan = DueReminderPlanner.plan(store: store, from: anchor, hour: 20, days: 0, calendar: tokyo)
        #expect(plan.isEmpty)
    }

    @Test("an out-of-range hour is clamped, not crashed")
    func clampHour() {
        let store = ReviewStore(cards: ["a": dueCard("a", dayOffset: 1)])
        let plan = DueReminderPlanner.plan(store: store, from: anchor, hour: 99, days: 2, calendar: tokyo)
        #expect(plan.allSatisfy { tokyo.component(.hour, from: $0.fireDate) == 23 })
    }
}

// MARK: - v1.21 §C

/// The reminder body is planned here, and NotificationKit cannot see the vocabulary, so the
/// "does this card's entry still exist" check arrives as a closure. It defaulted to "yes"
/// and no caller overrode it — so after v1.18 retired two entries, a learner who had studied
/// them was told at 9pm that N words were waiting and handed a run with N-1. The run had
/// been filtering all along; only the promise was wrong.
@Suite("Reminders count the run the learner will actually get")
struct ReminderOrphanTests {
    @Test("a card whose vocabulary entry is gone is not promised")
    func retiredEntryIsNotCounted() {
        let now = Date()
        var store = ReviewStore()
        store.record(entryID: "live", outcome: TypingOutcome(completed: false, mistakes: 3), on: now)
        store.record(entryID: "retired", outcome: TypingOutcome(completed: false, mistakes: 3), on: now)

        let unfiltered = DueReminderPlanner.plan(store: store, from: now, hour: 21)
        let filtered = DueReminderPlanner.plan(store: store,
                                               vocabResolves: { $0 != "retired" },
                                               from: now, hour: 21)
        #expect(unfiltered.first?.vocabCount == 2)
        #expect(filtered.first?.vocabCount == 1)
    }
}
