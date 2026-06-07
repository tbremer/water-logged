import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// One-shot, combined HealthKit authorization for the app's two Health features
/// — writing water (`dietaryWater`) and reading sleep (`sleepAnalysis`) —
/// requested together at launch so the user sees a single permission sheet
/// instead of one per feature.
///
/// Mirrors the providers' contract: `#if canImport(HealthKit)`-guarded and
/// best-effort — any failure or missing capability silently no-ops. The actual
/// reads/writes still live in `SleepScheduleProvider` / `HydrationHealthStore`;
/// this only handles the up-front permission prompt.
enum HealthKitAccess {
    /// Request read (sleep) + write (water) in a single prompt. Safe to call on
    /// every launch — HealthKit won't re-prompt once the user has decided.
    static func requestAll() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let water = HKQuantityType(.dietaryWater)
        let sleep = HKCategoryType(.sleepAnalysis)
        try? await store.requestAuthorization(toShare: [water], read: [sleep])
        #endif
    }
}
