import Foundation
import UserNotifications

/// An immutable snapshot of the reminder-relevant settings.
///
/// Captured synchronously on the main actor before a rebuild starts, so the
/// (potentially off-main, multi-`await`) scheduling work reads a consistent set
/// of values and never races the UI mutating `AppSettings`.
struct ReminderConfig: Sendable {
    let remindersEnabled: Bool
    let reminderIntervalMinutes: Int
    let activeStartHour: Int
    let activeEndHour: Int
    let respectSleepSchedule: Bool

    init(_ settings: AppSettings) {
        remindersEnabled = settings.remindersEnabled
        reminderIntervalMinutes = settings.reminderIntervalMinutes
        activeStartHour = settings.activeStartHour
        activeEndHour = settings.activeEndHour
        respectSleepSchedule = settings.respectSleepSchedule
    }
}

/// Schedules the recurring "time to hydrate" reminders.
///
/// Strategy: one repeating calendar notification per active slot (e.g. 8:00,
/// 9:00 … 22:00 for an hourly cadence). With a 14-hour window that's ~15
/// pending requests, well under the system's 64-request limit.
///
/// Concurrency: rebuilds are triggered from several places (scene activation,
/// settings changes, the daily background refresh) that can overlap. Because a
/// rebuild first clears *all* pending requests and then re-adds them across
/// several `await`s, two overlapping runs could interleave (clear → clear →
/// add → add). To prevent that, every request funnels through
/// `enqueueReschedule`, which chains onto the previous run so they execute
/// strictly one-at-a-time, and debounces UI-driven bursts into a single rebuild.
@MainActor
final class HydrationScheduler {
    static let shared = HydrationScheduler()

    // Immutable identifiers — explicitly nonisolated so the stateless helpers
    // (which run off the main actor) can reference them without a hop.
    nonisolated static let categoryID = "HYDRATE_REMINDER"
    nonisolated static let actionLog8 = "LOG_8"
    nonisolated static let actionLog16 = "LOG_16"
    nonisolated static let actionSnooze = "SNOOZE_15"

    nonisolated private static let reminderPrefix = "hydrate-hour-"

    /// The most reminders we'll keep pending at once. Kept under the system's
    /// 64-request limit to leave headroom for snoozes.
    nonisolated static let maxPendingRequests = 60

    /// The actual spacing (in minutes) between reminders for a given window and
    /// requested cadence. When the window is wide enough that the requested
    /// cadence would exceed `maxPendingRequests`, the step is widened just
    /// enough to spread reminders evenly across the *whole* window (rather than
    /// filling earliest-first and dropping the tail). Returns the requested
    /// cadence (floored at 15) whenever it already fits. Pure — also used by the
    /// Settings UI to tell the user when the spacing was widened.
    nonisolated static func effectiveStepMinutes(startHour: Int, endHour: Int, requestedMinutes: Int) -> Int {
        let windowMinutes = max(0, (endHour - startHour) * 60)
        let requestedStep = max(15, requestedMinutes)
        guard windowMinutes > 0 else { return requestedStep }
        // ceil(windowMinutes / (maxPendingRequests - 1)) via integer math.
        let minStepToFit = (windowMinutes + maxPendingRequests - 2) / (maxPendingRequests - 1)
        return max(requestedStep, minStepToFit)
    }

    /// Collapses rapid UI-driven reschedules (e.g. several Settings toggles in a
    /// row) into a single rebuild.
    nonisolated private static let debounceDelay: Duration = .milliseconds(250)

    /// The most recent (possibly still-running) scheduling task. New requests
    /// chain onto it so runs never interleave.
    private var rescheduleTask: Task<Void, Never>?

    nonisolated init() {}

    // MARK: - Categories / authorization

    /// Register the notification actions (Log 8 oz / Log 16 oz / Snooze).
    nonisolated func registerCategories() {
        let log8 = UNNotificationAction(identifier: Self.actionLog8, title: "Log 8 oz")
        let log16 = UNNotificationAction(identifier: Self.actionLog16, title: "Log 16 oz")
        let snooze = UNNotificationAction(identifier: Self.actionSnooze, title: "Snooze 15 min")
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [log8, log16, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    nonisolated func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Reschedule (debounced, serialized)

    /// Fire-and-forget rebuild for UI / lifecycle triggers. Safe to call as
    /// often as you like: rapid calls are debounced and never run concurrently.
    func reschedule(settings: AppSettings) {
        enqueueReschedule(config: ReminderConfig(settings), debounced: true)
    }

    /// Awaitable rebuild for the background-refresh task, which must keep the
    /// app awake until the work has actually finished. Skips the debounce.
    func rescheduleNow(settings: AppSettings) async {
        enqueueReschedule(config: ReminderConfig(settings), debounced: false)
        await rescheduleTask?.value
    }

    private func enqueueReschedule(config: ReminderConfig, debounced: Bool) {
        let previous = rescheduleTask
        previous?.cancel()
        rescheduleTask = Task { [weak self] in
            // Let any superseded run unwind first so we never overlap.
            _ = await previous?.value
            if debounced {
                try? await Task.sleep(for: Self.debounceDelay)
                if Task.isCancelled { return }   // a newer request replaced us
            }
            await self?.performReschedule(config: config)
        }
    }

    /// Rebuild the pending reminder set from a settings snapshot.
    private nonisolated func performReschedule(config: ReminderConfig) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        guard config.remindersEnabled else { return }
        guard await requestAuthorization() else { return }

        var startHour = config.activeStartHour
        let endHour = config.activeEndHour

        // Optionally trim the morning to your habitual wake-up time.
        if config.respectSleepSchedule {
            await SleepScheduleProvider.shared.requestAuthorization()
            if let wake = await SleepScheduleProvider.shared.estimatedWakeHour() {
                startHour = max(startHour, wake)
            }
        }

        // The Settings UI keeps start <= end, but a high wake-hour estimate can
        // still push the start past the end — in which case there's simply no
        // room to schedule reminders today.
        guard startHour <= endHour else { return }

        let startMinutes = startHour * 60
        let endMinutes = endHour * 60

        // Widen the cadence if needed so the whole window fits within the
        // pending-request budget (see `effectiveStepMinutes`).
        let stepMinutes = Self.effectiveStepMinutes(
            startHour: startHour,
            endHour: endHour,
            requestedMinutes: config.reminderIntervalMinutes
        )

        var scheduled = 0
        var minutesOfDay = startMinutes
        while minutesOfDay <= endMinutes && scheduled < Self.maxPendingRequests {
            let hour = minutesOfDay / 60
            let minute = minutesOfDay % 60
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(Self.reminderPrefix)\(hour)-\(minute)",
                content: makeContent(),
                trigger: trigger
            )
            try? await center.add(request)
            scheduled += 1
            minutesOfDay += stepMinutes
        }
    }

    /// One-off reminder used by the "Snooze" action.
    nonisolated func scheduleSnooze(minutes: Int) async {
        let content = makeContent(body: "Snoozed — take a sip and log it.")
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, minutes) * 60), repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "hydrate-snooze-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private nonisolated func makeContent(body: String = "Take a sip and log your water.") -> UNMutableNotificationContent {
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
