import SwiftUI

/// Top-level paged navigation: Today, History, Settings.
struct RootView: View {
    var body: some View {
        // To preview a single screen (e.g. for screenshots), comment out the
        // TabView below and uncomment one of these — do NOT delete the TabView:
        // SettingsView()
        TabView {
            TodayView()
            HistoryView()
            SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppSettings.shared)
        .modelContainer(PersistenceController.shared)
}
