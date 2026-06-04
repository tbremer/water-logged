import SwiftUI
import SwiftData

/// A reverse-chronological list of days with their total intake.
struct HistoryView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \DrinkEntry.timestamp, order: .reverse) private var entries: [DrinkEntry]

    private struct DaySummary: Identifiable {
        let id: Date
        let date: Date
        let total: Double
    }

    private var days: [DaySummary] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { day in
            let total = grouped[day]?.reduce(0) { $0 + $1.amountOunces } ?? 0
            return DaySummary(id: day, date: day, total: total)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    ContentUnavailableView(
                        "No water logged yet",
                        systemImage: "drop",
                        description: Text("Log your first drink on the Today screen.")
                    )
                } else {
                    List(days) { day in
                        NavigationLink {
                            DayDetailView(date: day.date)
                        } label: {
                            DayRow(date: day.date, total: day.total, goal: settings.dailyGoalOunces)
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

/// A single row summarizing one day.
private struct DayRow: View {
    let date: Date
    let total: Double
    let goal: Double

    private var metGoal: Bool { goal > 0 && total >= goal }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if metGoal {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            }
            HStack(spacing: 6) {
                Text(Formatters.ounces(total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: goal > 0 ? min(total / goal, 1) : 0)
                    .tint(.cyan)
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
    }
}

#Preview {
    HistoryView()
        .environment(AppSettings.shared)
        .modelContainer(PersistenceController.shared)
}
