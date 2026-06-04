import Foundation

/// The three quick-log increments offered on the Today screen.
enum DrinkSize: Int, CaseIterable, Identifiable {
    case small = 8
    case medium = 12
    case large = 16

    var id: Int { rawValue }

    var ounces: Double { Double(rawValue) }

    var label: String { "\(rawValue) oz" }

    var systemImage: String {
        switch self {
        case .small:  return "drop"
        case .medium: return "drop.fill"
        case .large:  return "drop.circle.fill"
        }
    }
}
