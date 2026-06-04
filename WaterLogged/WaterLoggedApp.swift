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
        }
        .modelContainer(PersistenceController.shared)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await HydrationScheduler.shared.reschedule(settings: .shared) }
            }
        }
    }
}
