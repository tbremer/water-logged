import SwiftUI
import SwiftData
import WatchKit

/// The main screen: today's progress ring plus the quick-log buttons.
struct TodayView: View {
    @Environment(AppSettings.self) private var settings
    @Query private var todaysEntries: [DrinkEntry]

    init() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay.addingTimeInterval(86_400)
        _todaysEntries = Query(
            filter: #Predicate { $0.timestamp >= startOfDay && $0.timestamp < endOfDay },
            sort: \.timestamp
        )
    }

    private var total: Double {
        todaysEntries.reduce(0) { $0 + $1.amountOunces }
    }

    var body: some View {
        NavigationStack {
                VStack(spacing: 14) {
                    ProgressRingView(total: total, goal: settings.dailyGoalOunces)
                        .padding(.top, 4)

                    if total >= settings.dailyGoalOunces, settings.dailyGoalOunces > 0 {
                        Label("Goal reached!", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    LogButtonsView(onLog: log(ounces:))
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
        }
    }

    private func log(ounces: Double) {
        WaterLog.add(ounces: ounces)
        WKInterfaceDevice.current().play(.success)
    }
}

#Preview {
    TodayView()
        .environment(AppSettings.shared)
        .modelContainer(PersistenceController.shared)
}
