import SwiftUI
import SwiftData

/// All entries for a single day, with totals and swipe-to-delete.
struct DayDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query private var entries: [DrinkEntry]

    /// The tapped entry, queued for a delete confirmation. Tapping a row (rather
    /// than swiping) surfaces the delete option — easier than swiping on-watch.
    @State private var entryToDelete: DrinkEntry?

    private let date: Date

    init(date: Date) {
        self.date = date
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay.addingTimeInterval(86_400)
        _entries = Query(
            filter: #Predicate { $0.timestamp >= startOfDay && $0.timestamp < endOfDay },
            sort: \.timestamp,
            order: .reverse
        )
    }

    private var total: Double {
        entries.reduce(0) { $0 + $1.amountOunces }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Total")
                    Spacer()
                    Text(Formatters.ounces(total)).bold()
                }
                ProgressView(
                    value: settings.dailyGoalOunces > 0 ? min(total / settings.dailyGoalOunces, 1) : 0
                ) {
                    Text("Goal \(Formatters.ounces(settings.dailyGoalOunces))")
                        .font(.caption2)
                }
                .tint(.cyan)
            }

            Section("Drinks") {
                ForEach(entries) { entry in
                    Button {
                        entryToDelete = entry
                    } label: {
                        HStack {
                            Image(systemName: "drop.fill").foregroundStyle(.blue)
                            Text(Formatters.ounces(entry.amountOunces))
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        // Tap a drink to confirm deletion (swipe-to-delete still works too).
        .confirmationDialog(
            "Delete this drink?",
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: entryToDelete
        ) { entry in
            Button("Delete \(Formatters.ounces(entry.amountOunces))", role: .destructive) {
                delete(entry)
                entryToDelete = nil
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: { entry in
            Text(entry.timestamp, style: .time)
        }
    }

    private func delete(at offsets: IndexSet) {
        let removed = offsets.map { entries[$0] }
        let removedIDs = removed.map(\.id)   // capture before deleting
        for entry in removed {
            context.delete(entry)
        }
        try? context.save()

        // Keep Apple Health in sync if mirroring is on.
        if AppSettings.shared.writeToHealth {
            Task { await HydrationHealthStore.shared.delete(entryIDs: removedIDs) }
        }
    }

    /// Delete a single tapped entry (shared by the tap-to-delete confirmation).
    private func delete(_ entry: DrinkEntry) {
        let id = entry.id   // capture before deleting
        context.delete(entry)
        try? context.save()

        // Keep Apple Health in sync if mirroring is on.
        if AppSettings.shared.writeToHealth {
            Task { await HydrationHealthStore.shared.delete(entryIDs: [id]) }
        }
    }
}
