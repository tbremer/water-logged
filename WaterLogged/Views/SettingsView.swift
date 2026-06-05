import SwiftUI

/// Goal + reminder configuration.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section(header: Text("Daily Goal").padding(.bottom, 1)) {
                    IncrementerRow(
                        glyph: "drop.fill",
                        title: "Goal",
                        value: Formatters.ounces(settings.dailyGoalOunces),
                        onPlus: { settings.dailyGoalOunces = min(300, settings.dailyGoalOunces + 8) },
                        onMinus: { settings.dailyGoalOunces = max(8, settings.dailyGoalOunces - 8) }
                    )
                }
                .padding(.top, 6)

                Section(header: Text("Reminders").padding(.bottom, 1)) {
                    Toggle(isOn: $settings.remindersEnabled) {
                        Text("Reminders")
//                        Label {  } icon:{ RowGlyph(name: "bell.badge") }
                    }

                    if settings.remindersEnabled {
                            Picker(selection: $settings.reminderIntervalMinutes) {
                                ForEach(AppSettings.reminderIntervalChoices, id: \.self) { minutes in
                                    Text("Every \(Formatters.interval(minutes: minutes))").tag(minutes)
                                }
                            } label: {
//                                Label { Text("Interval") } icon: { RowGlyph(name: "timer") }
                                Text("Interval")
                                    .padding(.bottom, 4)
                            }
                            
                            IncrementerRow(
                                glyph: "sunrise",
                                title: "Start",
                                value: Formatters.hourLabel(settings.activeStartHour),
                                onPlus: { settings.activeStartHour = min(23, settings.activeStartHour + 1) },
                                onMinus: { settings.activeStartHour = max(0, settings.activeStartHour - 1) }
                            )
                            IncrementerRow(
                                glyph: "sunset",
                                title: "End",
                                value: Formatters.hourLabel(settings.activeEndHour),
                                onPlus: { settings.activeEndHour = min(23, settings.activeEndHour + 1) },
                                onMinus: { settings.activeEndHour = max(0, settings.activeEndHour - 1) }
                            )
                            
                            Toggle(isOn: $settings.respectSleepSchedule) {
                                Text("Respect sleep schedule")
                            }
                    }
                }

                Section {
                    Text("Reminders fire on your chosen cadence within your active window. \"Respect sleep schedule\" uses Health sleep data to skip your sleeping hours.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: settings.remindersEnabled) { reschedule() }
            .onChange(of: settings.reminderIntervalMinutes) { reschedule() }
            .onChange(of: settings.activeStartHour) { reschedule() }
            .onChange(of: settings.activeEndHour) { reschedule() }
            .onChange(of: settings.respectSleepSchedule) { reschedule() }
        }
    }

    private func reschedule() {
        Task { await HydrationScheduler.shared.reschedule(settings: .shared) }
    }
}

/// A small cyan SF Symbol used as a leading glyph on settings rows.
/// (HIG: SF Symbols make list rows recognizable and signal interactivity.)
private struct RowGlyph: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.footnote)
            .foregroundStyle(.cyan)
            .frame(width: 20, alignment: .center)
    }
}

/// A +/- incrementer laid out as two consistent rows:
///
///     <glyph> <label>
///     (-)   <value>   (+)
private struct IncrementerRow: View {
    let glyph: String
    let title: String
    let value: String
    var onPlus: () -> Void
    var onMinus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(title)
                Spacer(minLength: 0)
            }

            HStack {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                }
                .frame(width:32)
                .accessibilityLabel("Decrease \(title)")

                Spacer()

                Text(value)
                    .font(.headline)

                Spacer()

                Button(action: onPlus) {
                    Image(systemName: "plus")
                }
                .frame(width:32)
                .accessibilityLabel("Increase \(title)")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(.blue)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings.shared)
}
