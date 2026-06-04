import Foundation
import SwiftData

/// Convenience for inserting entries from places that don't have a SwiftUI
/// `modelContext` in scope (e.g. notification action handlers).
@MainActor
enum WaterLog {
    static func add(ounces: Double, at date: Date = Date()) {
        let context = PersistenceController.shared.mainContext
        context.insert(DrinkEntry(amountOunces: ounces, timestamp: date))
        try? context.save()
    }
}
