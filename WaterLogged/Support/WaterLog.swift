import Foundation
import SwiftData
import UserNotifications

/// Convenience for inserting entries from places that don't have a SwiftUI
/// `modelContext` in scope (e.g. notification action handlers).
@MainActor
enum WaterLog {
    static func add(ounces: Double, at date: Date = Date()) {
        let context = PersistenceController.shared.mainContext
        let entry = DrinkEntry(amountOunces: ounces, timestamp: date)
        context.insert(entry)
        try? context.save()

        // The user just logged water, so any hydration reminders still sitting
        // in Notification Center are stale — clear the delivered ones.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // Best-effort mirror to Apple Health if the user opted in. Capture the
        // id so we don't pass the SwiftData model across the task boundary.
        if AppSettings.shared.writeToHealth {
            let entryID = entry.id
            Task { await HydrationHealthStore.shared.save(ounces: ounces, at: date, entryID: entryID) }
        }
    }
}
