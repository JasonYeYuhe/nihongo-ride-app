import Foundation
import ReviewKit

/// One scheduled "reviews due" reminder: fire at `fireDate`, telling the user how
/// many cards are due (`dueCount`) by that day.
public struct DueReminder: Equatable, Sendable {
    public let fireDate: Date
    public let dueCount: Int

    public init(fireDate: Date, dueCount: Int) {
        self.fireDate = fireDate
        self.dueCount = dueCount
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
    ///   - store: current SRS state (its cards' `dueDate`s drive the counts).
    ///   - now: the reference instant ("now").
    ///   - hour: local hour-of-day to fire at (clamped to 0…23).
    ///   - days: how many days ahead to plan (default 7; iOS allows 64 pending).
    ///   - calendar: calendar used for day boundaries (injectable for tests).
    /// - Returns: future reminders, soonest first, skipping zero-due days.
    public static func plan(
        store: ReviewStore,
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
            let count = store.dueCount(on: endOfDay)
            if count > 0 {
                reminders.append(DueReminder(fireDate: fire, dueCount: count))
            }
        }
        return reminders
    }
}
