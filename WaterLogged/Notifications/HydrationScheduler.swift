import Foundation
import UserNotifications

/// Schedules the hourly "time to hydrate" reminders.
///
/// Strategy: one repeating calendar notification per active hour (e.g. 8:00,
/// 9:00 … 22:00). With a 14-hour window that's ~15 pending requests, well under
/// the system's 64-request limit. Re-run `reschedule` whenever settings change,
/// when the app becomes active, and from the daily background refresh.
final class HydrationScheduler {
    static let shared = HydrationScheduler()

    private let center = UNUserNotificationCenter.current()

    static let categoryID = "HYDRATE_REMINDER"
    static let actionLog8 = "LOG_8"
    static let actionLog16 = "LOG_16"
    static let actionSnooze = "SNOOZE_15"

    private let reminderPrefix = "hydrate-hour-"

    /// Register the notification actions (Log 8 oz / Log 16 oz / Snooze).
    func registerCategories() {
        let log8 = UNNotificationAction(identifier: Self.actionLog8, title: "Log 8 oz")
        let log16 = UNNotificationAction(identifier: Self.actionLog16, title: "Log 16 oz")
        let snooze = UNNotificationAction(identifier: Self.actionSnooze, title: "Snooze 15 min")
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [log8, log16, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Rebuild the pending reminder set from current settings.
    func reschedule(settings: AppSettings) async {
        center.removeAllPendingNotificationRequests()

        guard settings.remindersEnabled else { return }
        guard await requestAuthorization() else { return }

        var startHour = settings.activeStartHour
        let endHour = settings.activeEndHour

        // Optionally trim the morning to your habitual wake-up time.
        if settings.respectSleepSchedule {
            await SleepScheduleProvider.shared.requestAuthorization()
            if let wake = await SleepScheduleProvider.shared.estimatedWakeHour() {
                startHour = max(startHour, wake)
            }
        }

        guard startHour <= endHour else { return }

        let stepMinutes = max(15, settings.reminderIntervalMinutes)
        let startMinutes = startHour * 60
        let endMinutes = endHour * 60

        // Stay under the system's 64 pending-request limit (leave room for snoozes).
        let maxRequests = 60
        var scheduled = 0

        var minutesOfDay = startMinutes
        while minutesOfDay <= endMinutes && scheduled < maxRequests {
            let hour = minutesOfDay / 60
            let minute = minutesOfDay % 60
            let content = makeContent()
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(reminderPrefix)\(hour)-\(minute)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
            scheduled += 1
            minutesOfDay += stepMinutes
        }
    }

    /// One-off reminder used by the "Snooze" action.
    func scheduleSnooze(minutes: Int) async {
        let content = makeContent(body: "Snoozed — take a sip and log it.")
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, minutes) * 60), repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "hydrate-snooze-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    private func makeContent(body: String = "Take a sip and log your water.") -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time to hydrate 💧"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        // Break through Focus / Do Not Disturb and present prominently (with haptic).
        // Requires the "Time Sensitive Notifications" capability in the entitlements.
        content.interruptionLevel = .timeSensitive
        return content
    }
}
