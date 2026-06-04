import Foundation

enum Formatters {
    /// "8 AM", "10 PM", etc. for an hour value 0–23.
    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = max(0, min(hour, 23))
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }

    /// Whole-ounce string, e.g. "96 oz".
    static func ounces(_ value: Double) -> String {
        "\(Int(value.rounded())) oz"
    }

    /// Reminder cadence label, e.g. "15 min", "30 min", "1 hr", "2 hr", "4 hr".
    static func interval(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return "\(hours) hr"
    }
}
