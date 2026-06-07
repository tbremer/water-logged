import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Best-effort mirroring of logged water into Apple Health as `dietaryWater`
/// samples, so intake shows up across the Health ecosystem (Health app, other
/// hydration apps, etc.).
///
/// Best-effort: every entry point is `#if canImport(HealthKit)`-guarded and
/// silently no-ops on any failure, so a missing capability or denied permission
/// never breaks logging. SwiftData remains the source of truth — this is a
/// one-way write mirror.
final class HydrationHealthStore {
    static let shared = HydrationHealthStore()

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private let waterType = HKQuantityType(.dietaryWater)
    /// Custom metadata key linking a Health sample back to its `DrinkEntry`, so
    /// removing an entry can delete the matching sample.
    private let entryIDKey = "com.tbremer.waterlogged.entryID"
    #endif

    var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    /// Ask for permission to write dietary water. Safe to call repeatedly.
    @discardableResult
    func requestAuthorization() async -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [waterType], read: [])
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// Mirror a logged drink to Health as a `dietaryWater` sample, tagged with
    /// the originating entry's id so it can be deleted later.
    func save(ounces: Double, at date: Date, entryID: UUID) async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(), ounces > 0 else { return }
        let quantity = HKQuantity(unit: .fluidOunceUS(), doubleValue: ounces)
        let sample = HKQuantitySample(
            type: waterType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: [entryIDKey: entryID.uuidString]
        )
        try? await store.save(sample)
        #endif
    }

    /// Remove the Health samples mirroring the given entries (matched by id).
    func delete(entryIDs: [UUID]) async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(), !entryIDs.isEmpty else { return }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: entryIDKey,
            allowedValues: entryIDs.map(\.uuidString)
        )
        _ = try? await store.deleteObjects(of: waterType, predicate: predicate)
        #endif
    }
}
