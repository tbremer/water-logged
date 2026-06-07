import SwiftUI

/// Goal + reminder configuration.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    /// iCloud/CloudKit status, surfaced read-only so we can see whether sync is
    /// live on-device without opening the CloudKit Dashboard.
    @State private var cloudKitDiagnostics: [DiagnosticRow] = []

    var body: some View {
        @Bindable var settings = settings

        // The spacing reminders will actually use; differs from the picked
        // interval only when the active window is too wide to fit them all.
        let effectiveStep = HydrationScheduler.effectiveStepMinutes(
            startHour: settings.activeStartHour,
            endHour: settings.activeEndHour,
            requestedMinutes: settings.reminderIntervalMinutes
        )

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
                                // Keep Start at or before End so the active window
                                // is never empty (which would silently disable all
                                // reminders).
                                onPlus: { settings.activeStartHour = min(settings.activeEndHour, settings.activeStartHour + 1) },
                                onMinus: { settings.activeStartHour = max(0, settings.activeStartHour - 1) }
                            )
                            IncrementerRow(
                                glyph: "sunset",
                                title: "End",
                                value: Formatters.hourLabel(settings.activeEndHour),
                                onPlus: { settings.activeEndHour = min(23, settings.activeEndHour + 1) },
                                // Keep End at or after Start (same reasoning).
                                onMinus: { settings.activeEndHour = max(settings.activeStartHour, settings.activeEndHour - 1) }
                            )

                            if effectiveStep > settings.reminderIntervalMinutes {
                                Text("Your window is wide for this interval, so reminders are spaced about every \(Formatters.interval(minutes: effectiveStep)) to fit the watch's reminder limit.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }

                Section {
                    Text("Reminders fire on your chosen cadence within your active window.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if HydrationHealthStore.shared.isAvailable {
                    Section(header: Text("Apple Health").padding(.bottom, 1)) {
                        Toggle(isOn: $settings.writeToHealth) {
                            Text("Save to Apple Health")
                        }
                        Text("Logged drinks are written to Apple Health as water, so they appear in Health and other apps.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Read-only: which store SwiftData settled on, and whether an
                // iCloud account is available to sync with.
                Section(header: Text("iCloud Sync (Diagnostics)").padding(.bottom, 1)) {
                    ForEach(cloudKitDiagnostics) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.label)
                            Spacer(minLength: 8)
                            Text(row.value)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.caption2)
                    }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: settings.remindersEnabled) { reschedule() }
            .onChange(of: settings.reminderIntervalMinutes) { reschedule() }
            .onChange(of: settings.activeStartHour) { reschedule() }
            .onChange(of: settings.activeEndHour) { reschedule() }
            .onChange(of: settings.writeToHealth) { _, isOn in
                // Prompt for Health write access the first time the user opts in.
                if isOn {
                    Task { await HydrationHealthStore.shared.requestAuthorization() }
                }
            }
            .task { loadCloudKitDiagnostics() }
        }
    }

    /// Snapshot the persistence layer's current store + iCloud availability.
    /// The chosen store is fixed for the session (decided when the container is
    /// created at launch), so a one-time read is enough.
    private func loadCloudKitDiagnostics() {
        _ = PersistenceController.shared   // ensure the container has been created
        cloudKitDiagnostics = [
            DiagnosticRow(label: "Store", value: PersistenceController.activeStore.description),
            DiagnosticRow(
                label: "iCloud account",
                value: PersistenceController.cloudKitAccountStatusDescription
            ),
            DiagnosticRow(label: "Container", value: PersistenceController.cloudKitContainerIdentifier),
        ]
    }

    @MainActor
    private func reschedule() {
        // Fire-and-forget; the scheduler debounces the burst of onChange calls
        // that fire when several settings are adjusted in quick succession.
        HydrationScheduler.shared.reschedule(settings: .shared)
    }
}

/// One row of the read-only diagnostics (label + current value).
private struct DiagnosticRow: Identifiable {
    var id: String { label }
    let label: String
    let value: String
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
