import Testing
import Foundation
import ReviewKit
@testable import NotificationKit

/// v1.14 §B. Reminders and the app-icon badge used to read the vocab SRS store ONLY, so a
/// learner who did nothing but conjugation drills was never reminded and saw a zero badge —
/// while the menu was simultaneously offering them "review N due conjugations". These pin
/// counts, not non-emptiness: a planner that scheduled the right DAYS with the wrong numbers
/// is exactly the failure that shipped.
@Suite("Due reminders count conjugations too")
struct ConjugationRemindersTests {

    private var tokyo: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    /// 2026-03-01 09:00 JST — before the 20:00 slot, so today is still schedulable.
    private var anchor: Date {
        tokyo.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9))!
    }

    /// Vocab cards due at the START of `anchor + offset` days (same shape the sibling
    /// suite uses, so both read against one notion of "due that day").
    private func store(dueOffsets: [Int]) -> ReviewStore {
        var cards: [String: SRSCard] = [:]
        for (i, days) in dueOffsets.enumerated() {
            var c = SRSCard(id: "v\(i)", createdAt: anchor)
            c.dueDate = tokyo.startOfDay(for: tokyo.date(byAdding: .day, value: days, to: anchor)!)
            c.lastReviewed = anchor
            cards["v\(i)"] = c
        }
        return ReviewStore(cards: cards)
    }

    @Test("a conjugation-only learner still gets reminders")
    func conjugationOnlyIsReminded() {
        // The shipped bug in one assertion: empty vocab store, real conjugation debt.
        let plan = DueReminderPlanner.plan(
            store: ReviewStore(),
            conjugationDue: { _, _ in 4 },
            from: anchor, hour: 20, days: 3, calendar: tokyo)

        #expect(plan.count == 3, "conjugation-only learner got \(plan.count) reminders")
        #expect(plan.allSatisfy { $0.dueCount == 4 })
        #expect(plan.allSatisfy { $0.vocabCount == 0 && $0.conjugationCount == 4 })
    }

    @Test("both kinds are summed per day, not one or the other")
    func countsAreSummed() {
        // 2 vocab due today, 1 more tomorrow; conjugation grows 1/day.
        let vocab = store(dueOffsets: [0, 0, 1])
        let plan = DueReminderPlanner.plan(
            store: vocab,
            conjugationDue: { end, cal in
                // days elapsed from the anchor's day → 1, 2, 3. Uses the calendar the planner
                // hands over, not a captured one: that is the contract finding 6 restored.
                let d = cal.dateComponents([.day], from: cal.startOfDay(for: self.anchor),
                                           to: cal.startOfDay(for: end)).day ?? 0
                return d + 1
            },
            from: anchor, hour: 20, days: 3, calendar: tokyo)

        #expect(plan.map(\.vocabCount) == [2, 3, 3])
        #expect(plan.map(\.conjugationCount) == [1, 2, 3])
        #expect(plan.map(\.dueCount) == [3, 5, 6])
    }

    @Test("a day with zero of BOTH is still skipped")
    func emptyDaysStillSkipped() {
        // The zero-skip must survive the sum: no "0 due" pings, and no reminder that
        // exists only because one of the two closures was called.
        let plan = DueReminderPlanner.plan(
            store: ReviewStore(), conjugationDue: { _, _ in 0 },
            from: anchor, hour: 20, days: 7, calendar: tokyo)
        #expect(plan.isEmpty)
    }

    @Test("the conjugation closure is asked about the END of each day")
    func closureSeesEndOfDay() {
        // The vocab side counts cards due before the day's midnight cutoff; the closure has
        // to be handed that same instant or the two halves would disagree by a day.
        var seen: [Date] = []
        _ = DueReminderPlanner.plan(
            store: ReviewStore(), conjugationDue: { d, _ in seen.append(d); return 1 },
            from: anchor, hour: 20, days: 2, calendar: tokyo)

        #expect(seen.count == 2)
        for (k, date) in seen.enumerated() {
            let expected = tokyo.date(byAdding: .day, value: k + 1,
                                      to: tokyo.startOfDay(for: anchor))!.addingTimeInterval(-1)
            #expect(date == expected, "day \(k) probed \(date), expected \(expected)")
        }
    }

    @Test("the injected calendar decides the day, not the machine's time zone")
    func injectedCalendarIsHonoured() {
        // `calendar:` used to be a half-injection: the planner built Tokyo days but then let
        // ReviewStore.dueCount re-derive the day from Calendar.current, so this suite passed
        // only because the machine is on JST. Counting the SAME cards under two calendars
        // must differ, and each must match its own calendar's day boundary.
        //
        // Anchor is 09:00 JST = 00:00 UTC the same day. A card due at the start of the NEXT
        // Tokyo day (2026-03-02 00:00 JST = 2026-03-01 15:00 UTC) falls inside UTC's first
        // day but outside Tokyo's — so day 1 counts it in UTC and not in Tokyo.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        utc.locale = Locale(identifier: "en_US_POSIX")

        let cards = store(dueOffsets: [1])           // due 2026-03-02 00:00 JST
        var seenCalendars: [TimeZone] = []
        let tokyoPlan = DueReminderPlanner.plan(
            store: cards, conjugationDue: { _, cal in seenCalendars.append(cal.timeZone); return 0 },
            from: anchor, hour: 20, days: 1, calendar: tokyo)
        let utcPlan = DueReminderPlanner.plan(
            store: cards, conjugationDue: { _, _ in 0 },
            from: anchor, hour: 20, days: 1, calendar: utc)

        // Tokyo's day 1 ends 2026-03-01 23:59:59 JST — the card is not due yet, so no ping.
        #expect(tokyoPlan.isEmpty, "Tokyo day 1 counted \(tokyoPlan.map(\.dueCount))")
        // UTC's day 1 ends 2026-03-01 23:59:59 UTC = 08:59:59 JST on the 2nd — it IS due.
        #expect(utcPlan.map(\.vocabCount) == [1], "UTC day 1 counted \(utcPlan.map(\.vocabCount))")
        // And the closure is handed the planner's calendar, not left to guess.
        #expect(seenCalendars == [TimeZone(identifier: "Asia/Tokyo")!])
    }

    @Test("omitting the closure keeps the old vocab-only behaviour")
    func defaultIsVocabOnly() {
        // The parameter defaults to zero so any caller I missed degrades to what shipped,
        // rather than to a crash or a doubled count.
        let plan = DueReminderPlanner.plan(store: store(dueOffsets: [0, 0]),
                                           from: anchor, hour: 20, days: 1, calendar: tokyo)
        #expect(plan.map(\.dueCount) == [2])
        #expect(plan.allSatisfy { $0.conjugationCount == 0 })
    }
}
