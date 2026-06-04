import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Best-effort access to the wearer's sleep schedule via HealthKit.
///
/// Platform reality: watchOS gives third-party apps **no** API to know whether
/// the watch is currently on your wrist, and local notifications fire on their
/// trigger regardless. The closest we can do for "don't remind me while I'm
/// asleep" is:
///   - learn your habitual wake-up hour and not schedule reminders before it, and
///   - suppress a reminder that's about to present while a current sleep sample
///     says you're asleep.
final class SleepScheduleProvider {
    static let shared = SleepScheduleProvider()

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue
    ]
    #endif

    var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    /// Ask for read access to sleep analysis. Safe to call repeatedly.
    @discardableResult
    func requestAuthorization() async -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let sleep = HKCategoryType(.sleepAnalysis)
        do {
            try await store.requestAuthorization(toShare: [], read: [sleep])
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// True if the most recent sleep sample indicates you're asleep right now.
    func currentlyAsleep() async -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let sleep = HKCategoryType(.sleepAnalysis)
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-12 * 3600), end: now, options: []
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleep, predicate: predicate, limit: 1, sortDescriptors: [sort]
            ) { [asleepValues] _, samples, _ in
                guard let sample = samples?.first as? HKCategorySample else {
                    continuation.resume(returning: false); return
                }
                let isAsleep = asleepValues.contains(sample.value)
                    && sample.startDate <= now
                    && sample.endDate >= now.addingTimeInterval(-30 * 60)
                continuation.resume(returning: isAsleep)
            }
            store.execute(query)
        }
        #else
        return false
        #endif
    }

    /// Estimate your habitual wake-up hour (0–23) from recent sleep samples.
    ///
    /// We use the *end* of asleep segments because morning wake times cluster
    /// tightly and don't wrap around midnight, making the average reliable.
    func estimatedWakeHour() async -> Int? {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let sleep = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -10, to: Date())
            ?? Date().addingTimeInterval(-10 * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleep, predicate: predicate, limit: 300, sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let wakeHours = samples
            .filter { asleepValues.contains($0.value) }
            .map { calendar.component(.hour, from: $0.endDate) }
        guard !wakeHours.isEmpty else { return nil }

        let average = Double(wakeHours.reduce(0, +)) / Double(wakeHours.count)
        return min(max(Int(average.rounded()), 0), 23)
        #else
        return nil
        #endif
    }
}
