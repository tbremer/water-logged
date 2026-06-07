import SwiftUI
import SwiftData

@main
struct WaterLoggedApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppSettings.shared)
                // Reliable initial schedule on launch (scenePhase.onChange does
                // not fire for the initial value).
                .task { HydrationScheduler.shared.reschedule(settings: .shared) }
        }
        .modelContainer(PersistenceController.shared)
        .onChange(of: scenePhase) { _, phase in
            // Rebuild when returning to the foreground (e.g. permission granted
            // while away, or a day boundary passed). Debounced in the scheduler.
            if phase == .active {
                HydrationScheduler.shared.reschedule(settings: .shared)
            }
        }
    }
}
