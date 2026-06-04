import SwiftUI
import SwiftData

/// All entries for a single day, with totals and swipe-to-delete.
struct DayDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query private var entries: [DrinkEntry]

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
                    HStack {
                        Image(systemName: "drop.fill").foregroundStyle(.blue)
                        Text(Formatters.ounces(entry.amountOunces))
                        Spacer()
                        Text(entry.timestamp, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(entries[index])
        }
        try? context.save()
    }
}
