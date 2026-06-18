import Foundation
import ReviewKit
import NotificationKit
import UserNotifications

/// The impure side of SRS due-reminders: it talks to `UNUserNotificationCenter`.
/// The *what to schedule* decision lives in `NotificationKit.DueReminderPlanner`
/// (pure, unit-tested); this type just requests authorization and registers the
/// concrete notification requests the planner produced.
///
/// Reminders are rescheduled (not `repeats:true`) so each day carries an accurate
/// due count — the next 7 days are registered as individual calendar triggers and
/// refreshed whenever the SRS state changes or the app becomes active.
enum ReminderScheduler {
    /// Notification APIs trap for an unbundled process (`swift run` has no
    /// Info.plist) and are pointless during headless screenshot capture, so the
    /// `@MainActor` caller gates every call on a real bundle.
    @MainActor
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && !Screenshotter.isCapturing
    }

    private static let idPrefix = "nihongoride.due-reminder."

    /// Applies the current reminder preference. Returns `true` once reminders are
    /// scheduled, `false` if reminders are off or authorization was denied (the
    /// caller flips its toggle back to reflect a denial). Only call when
    /// `isAvailable`.
    @discardableResult
    static func apply(enabled: Bool, store: ReviewStore, hour: Int, languageCode: String) async -> Bool {
        let center = UNUserNotificationCenter.current()

        guard enabled else {
            cancelAll(center)
            try? await center.setBadgeCount(0)
            return false
        }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            status = granted ? .authorized : .denied
        }
        guard status == .authorized || status == .provisional else { return false }

        cancelAll(center)
        let zh = languageCode == "zh"
        let reminders = DueReminderPlanner.plan(store: store, from: Date(), hour: hour)
        for (index, reminder) in reminders.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = zh ? "复习时间到" : "Time to review"
            content.body = body(count: reminder.dueCount, zh: zh)
            content.sound = .default
            content.badge = NSNumber(value: reminder.dueCount)

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(idPrefix)\(index)", content: content, trigger: trigger)
            try? await center.add(request)
        }
        // Keep the app icon badge honest with what's due right now.
        try? await center.setBadgeCount(store.dueCount())
        return true
    }

    private static func cancelAll(_ center: UNUserNotificationCenter) {
        center.removeAllPendingNotificationRequests()
    }

    private static func body(count: Int, zh: Bool) -> String {
        if zh { return "今天有 \(count) 个词到期复习,上车继续吧。" }
        return count == 1 ? "1 word is due for review today." : "\(count) words are due for review today."
    }
}
