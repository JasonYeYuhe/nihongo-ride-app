import Foundation
import ReviewKit

/// One scheduled "reviews due" reminder: fire at `fireDate`, telling the user how
/// many cards are due (`dueCount`) by that day.
///
/// The two kinds are kept apart rather than pre-summed because the notification body
/// is worded differently for each ("3 words" vs "3 reviews"): a reminder that says
/// "words" while the due pile is entirely conjugation drills is the same class of lie
/// v1.12 removed from the sync status. (v1.14 §B.)
public struct DueReminder: Equatable, Sendable {
    public let fireDate: Date
    public let vocabCount: Int
    public let conjugationCount: Int

    /// What the user actually owes that day, and what the badge shows.
    public var dueCount: Int { vocabCount + conjugationCount }

    public init(fireDate: Date, vocabCount: Int, conjugationCount: Int = 0) {
        self.fireDate = fireDate
        self.vocabCount = vocabCount
        self.conjugationCount = conjugationCount
    }
}

/// Pure planner for the SRS "reviews due" reminders.
///
/// Instead of one `repeats: true` daily notification — which would keep firing a
/// *stale* count if the user doesn't open the app — this produces an explicit
/// per-day schedule for the next `days` days, each with the count of cards that
/// will be due by the END of that day. The UserNotifications layer (v1.2 Phase B)
/// registers one non-repeating `UNCalendarNotificationTrigger` per entry. Days
/// with zero due cards are skipped, so the user never gets a "0 cards due" ping.
public enum DueReminderPlanner {

    /// - Parameters:
    ///   - store: current vocab SRS state (its cards' `dueDate`s drive the counts).
    ///   - vocabResolves: whether a card's vocabulary entry still exists. NotificationKit
    ///     cannot see VocabKit, so the caller injects it — the same shape `ReviewStore`
    ///     uses. Defaulting to "everything resolves" is what let this path keep counting
    ///     retired entries after the check existed.
    ///   - conjugationDue: how many CONJUGATION cards are due by a given instant, **in the
    ///     calendar passed as the second argument**. A closure, not a store, so this module
    ///     keeps depending on ReviewKit alone — the conjugation SRS is a deliberately separate
    ///     store (red line §1) and NotificationKit must not learn about it. Defaults to zero
    ///     so existing callers are unchanged.
    ///
    ///     Both counts are taken in `calendar`, not `Calendar.current`. Leaving that to the
    ///     default made `calendar:` a half-injection: the planner built Tokyo days and then
    ///     asked the stores to re-derive "which day is this instant in" from the machine's
    ///     time zone, so the same code counted differently under `TZ=UTC` and the unit tests
    ///     were passing only because this Mac is on JST.
    ///   - now: the reference instant ("now").
    ///   - hour: local hour-of-day to fire at (clamped to 0…23).
    ///   - days: how many days ahead to plan (default 7; iOS allows 64 pending).
    ///   - calendar: calendar used for day boundaries (injectable for tests).
    /// - Returns: future reminders, soonest first, skipping zero-due days.
    public static func plan(
        store: ReviewStore,
        conjugationDue: (Date, Calendar) -> Int = { _, _ in 0 },
        vocabResolves: @escaping (String) -> Bool = { _ in true },
        from now: Date,
        hour: Int,
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [DueReminder] {
        guard days > 0 else { return [] }
        let clampedHour = min(23, max(0, hour))
        let startOfToday = calendar.startOfDay(for: now)
        var reminders: [DueReminder] = []

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let fire = calendar.date(bySettingHour: clampedHour, minute: 0, second: 0, of: day),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            else { continue }

            // Only schedule reminders that are still in the future (today's slot
            // may already have passed).
            guard fire > now else { continue }

            // Cards due by the end of this calendar day (one second before midnight).
            let endOfDay = nextDay.addingTimeInterval(-1)
            // Same orphan filter the run itself applies. A reminder that counts a card the
            // run will drop tells the learner about work that does not exist, which is the
            // failure `resolves:` was added for — and this call site never got it.
            let vocab = store.dueCount(on: endOfDay, calendar: calendar, resolves: vocabResolves)
            let conj = conjugationDue(endOfDay, calendar)
            if vocab + conj > 0 {
                reminders.append(DueReminder(fireDate: fire, vocabCount: vocab, conjugationCount: conj))
            }
        }
        return reminders
    }
}
