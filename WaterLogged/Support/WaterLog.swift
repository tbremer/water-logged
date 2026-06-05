import Foundation
import SwiftData
import UserNotifications

/// Convenience for inserting entries from places that don't have a SwiftUI
/// `modelContext` in scope (e.g. notification action handlers).
@MainActor
enum WaterLog {
    static func add(ounces: Double, at date: Date = Date()) {
        let context = PersistenceController.shared.mainContext
        context.insert(DrinkEntry(amountOunces: ounces, timestamp: date))
        try? context.save()

        // The user just logged water, so any hydration reminders still sitting
        // in Notification Center are stale — clear the delivered ones.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
