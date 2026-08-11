import Foundation
import ReviewKit
import ConjugationReviewKit
import NotificationKit
import VocabKit
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
    ///
    /// `conjugationStore` is counted alongside `store`: due means ONE thing across the
    /// app (v1.12), and until v1.14 a learner who drilled only conjugations was never
    /// reminded and saw a zero badge while the menu offered them reviews.
    @discardableResult
    static func apply(enabled: Bool, store: ReviewStore, conjugationStore: ConjugationReviewStore,
                      hour: Int, languageCode: String) async -> Bool {
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
        let reminders = DueReminderPlanner.plan(
            store: store,
            conjugationDue: { conjugationStore.dueCount(on: $0, calendar: $1) },
            vocabResolves: { VocabStore.shared.entry(id: $0) != nil },
            from: Date(), hour: hour)
        for (index, reminder) in reminders.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = zh ? "复习时间到" : "Time to review"
            content.body = body(reminder, zh: zh)
            content.sound = .default
            content.badge = NSNumber(value: reminder.dueCount)

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(idPrefix)\(index)", content: content, trigger: trigger)
            try? await center.add(request)
        }
        // Keep the app icon badge honest with what's due right now — both kinds.
        try? await center.setBadgeCount(
            store.dueCount(resolves: { VocabStore.shared.entry(id: $0) != nil })
                + conjugationStore.dueCount())
        return true
    }

    private static func cancelAll(_ center: UNUserNotificationCenter) {
        center.removeAllPendingNotificationRequests()
    }

    /// The body names what is actually due. Saying "words" when the pile is entirely
    /// conjugation drills would be a small lie the user can check against the menu, so
    /// each mix gets its own wording and the mixed case just says "reviews".
    private static func body(_ r: DueReminder, zh: Bool) -> String {
        let n = r.dueCount
        switch (r.vocabCount > 0, r.conjugationCount > 0) {
        case (true, false):
            if zh { return "今天有 \(n) 个词到期复习,上车继续吧。" }
            return "\(countLabel(n, "word")) \(countVerb(n)) due for review today."
        case (false, true):
            if zh { return "今天有 \(n) 个变形到期复习,上车继续吧。" }
            return "\(countLabel(n, "conjugation")) \(countVerb(n)) due for review today."
        default:
            // Both counts are non-zero here, so the outer noun is always plural; the two
            // inner counts are not — this branch shipped "(1 words + 1 conjugations)".
            if zh { return "今天有 \(n) 个复习到期(\(r.vocabCount) 词 + \(r.conjugationCount) 变形)。" }
            return "\(n) reviews are due today (\(countLabel(r.vocabCount, "word")) + "
                 + "\(countLabel(r.conjugationCount, "conjugation")))."
        }
    }
}
