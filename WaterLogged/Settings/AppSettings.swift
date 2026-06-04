import Foundation
import Observation

/// User-tunable settings, persisted in `UserDefaults` and observable by SwiftUI.
///
/// A single shared instance is used so non-UI code (the notification scheduler,
/// background refresh) reads the same values the UI writes.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// Selectable reminder cadences, in minutes: 15 min, 30 min, 1 hr, 2 hr, 4 hr.
    static let reminderIntervalChoices = [15, 30, 60, 120, 240]

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Key {
        static let dailyGoalOunces      = "dailyGoalOunces"
        static let remindersEnabled     = "remindersEnabled"
        static let reminderIntervalMinutes = "reminderIntervalMinutes"
        static let activeStartHour      = "activeStartHour"
        static let activeEndHour        = "activeEndHour"
        static let respectSleepSchedule = "respectSleepSchedule"
    }

    var dailyGoalOunces: Double {
        didSet { defaults.set(dailyGoalOunces, forKey: Key.dailyGoalOunces) }
    }
    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Key.remindersEnabled) }
    }
    /// Reminder cadence in minutes; one of ``reminderIntervalChoices``.
    var reminderIntervalMinutes: Int {
        didSet { defaults.set(reminderIntervalMinutes, forKey: Key.reminderIntervalMinutes) }
    }
    /// First hour (0–23) a reminder may fire.
    var activeStartHour: Int {
        didSet { defaults.set(activeStartHour, forKey: Key.activeStartHour) }
    }
    /// Last hour (0–23) a reminder may fire.
    var activeEndHour: Int {
        didSet { defaults.set(activeEndHour, forKey: Key.activeEndHour) }
    }
    /// When on, Health sleep data is used to skip your sleeping hours.
    var respectSleepSchedule: Bool {
        didSet { defaults.set(respectSleepSchedule, forKey: Key.respectSleepSchedule) }
    }

    private init() {
        defaults.register(defaults: [
            Key.dailyGoalOunces: 96.0,
            Key.remindersEnabled: true,
            Key.reminderIntervalMinutes: 60,
            Key.activeStartHour: 8,
            Key.activeEndHour: 22,
            Key.respectSleepSchedule: true
        ])
        dailyGoalOunces      = defaults.double(forKey: Key.dailyGoalOunces)
        remindersEnabled     = defaults.bool(forKey: Key.remindersEnabled)
        let storedInterval = defaults.integer(forKey: Key.reminderIntervalMinutes)
        reminderIntervalMinutes = AppSettings.reminderIntervalChoices.contains(storedInterval) ? storedInterval : 60
        activeStartHour      = defaults.integer(forKey: Key.activeStartHour)
        activeEndHour        = defaults.integer(forKey: Key.activeEndHour)
        respectSleepSchedule = defaults.bool(forKey: Key.respectSleepSchedule)
    }
}
