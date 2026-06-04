import Foundation
import SwiftData

/// A single logged amount of water.
///
/// Designed to be CloudKit-compatible for SwiftData sync:
///  - every stored property has a default value,
///  - there are no `@Attribute(.unique)` constraints,
///  - there are no required (non-optional) relationships.
@Model
final class DrinkEntry {
    var id: UUID = UUID()
    var amountOunces: Double = 0
    var timestamp: Date = Date()

    init(amountOunces: Double, timestamp: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.amountOunces = amountOunces
        self.timestamp = timestamp
    }
}
