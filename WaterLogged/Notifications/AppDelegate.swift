import Foundation
import WatchKit
import UserNotifications

/// App lifecycle hooks: wires up notifications, handles reminder actions, and
/// re-arms the reminder schedule via a daily background refresh.
final class AppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        HydrationScheduler.shared.registerCategories()
        // Initial scheduling is driven by the scene becoming active (see
        // WaterLoggedApp's `.task`), so we only arm the background refresh here.
        scheduleNextBackgroundRefresh()
    }

    // MARK: - Foreground presentation

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Always present reminders prominently while the app is foregrounded.
        return [.banner, .sound, .list]
    }

    // MARK: - Notification actions

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case HydrationScheduler.actionLog8:
            WaterLog.add(ounces: 8)
        case HydrationScheduler.actionLog16:
            WaterLog.add(ounces: 16)
        case HydrationScheduler.actionSnooze:
            await HydrationScheduler.shared.scheduleSnooze(minutes: 15)
        default:
            break
        }
    }

    // MARK: - Background refresh

    /// Ask the system for a wake-up around 3:30am to rebuild the day's schedule
    /// (e.g. to re-fit the morning start to your latest sleep data).
    func scheduleNextBackgroundRefresh() {
        let next = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 3, minute: 30),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)

        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: next, userInfo: nil
        ) { _ in }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let refresh = task as? WKApplicationRefreshBackgroundTask {
                // Await the rebuild so the system keeps us awake until it's done,
                // then arm the next refresh and report completion.
                Task { @MainActor in
                    await HydrationScheduler.shared.rescheduleNow(settings: .shared)
                    self.scheduleNextBackgroundRefresh()
                    refresh.setTaskCompletedWithSnapshot(false)
                }
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
