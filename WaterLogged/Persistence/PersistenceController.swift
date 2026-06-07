import Foundation
import SwiftData

/// Owns the app's `ModelContainer`.
///
/// When iCloud is actually available we use a CloudKit-backed (syncing) store;
/// otherwise we fall back to a local-only store so the app always launches.
///
/// Why the explicit availability gate? `ModelContainer(...)` succeeds
/// synchronously even when CloudKit can't work, then Core Data's CloudKit
/// mirroring **crashes asynchronously on its own queue** (e.g. on a simulator
/// with no iCloud account, or before the iCloud capability is provisioned with
/// your team). A `try?` can't catch that, so we must decide up front.
enum PersistenceController {

    /// Which backing store `makeContainer()` actually settled on. Surfaced for
    /// the Settings diagnostics so we can see whether sync is live on-device.
    enum StoreKind {
        case cloudKit   // CloudKit-backed, syncing private database
        case local      // on-device only, no sync
        case inMemory   // last-resort, non-persistent

        var description: String {
            switch self {
            case .cloudKit: return "iCloud (syncing)"
            case .local:    return "On-device only"
            case .inMemory: return "In-memory (not saved)"
            }
        }
    }

    /// Must match the iCloud container in `WaterLogged.entitlements`.
    static let cloudKitContainerIdentifier = "iCloud.com.tbremer.waterlogged"

    /// The store `makeContainer()` chose. Valid once `shared` has been accessed
    /// (which happens at app launch). Defaults to `.inMemory` until then.
    static private(set) var activeStore: StoreKind = .inMemory

    /// The shared container used by the whole app.
    static let shared: ModelContainer = makeContainer()

    /// Whether it's safe to turn on CloudKit mirroring.
    ///
    /// - Simulator: disabled. Ad-hoc simulator builds have no provisioned
    ///   CloudKit container, which makes the mirroring layer trap.
    /// - Device: enabled only when someone is signed into iCloud.
    static var isCloudKitAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return FileManager.default.ubiquityIdentityToken != nil
        #endif
    }

    static func makeContainer() -> ModelContainer {
        // 1) Preferred: CloudKit-synced private database (real device, signed in).
        if isCloudKitAvailable,
           let container = try? ModelContainer(
            for: DrinkEntry.self,
            configurations: ModelConfiguration(
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )
           ) {
            activeStore = .cloudKit
            return container
        }

        // 2) Fallback: on-device store only (no sync).
        if let container = try? ModelContainer(
            for: DrinkEntry.self,
            configurations: ModelConfiguration(cloudKitDatabase: .none)
        ) {
            #if DEBUG
            print("[WaterLogged] Using a local-only store (CloudKit not available here).")
            #endif
            activeStore = .local
            return container
        }

        // 3) Last resort: in-memory so the UI still works this session.
        activeStore = .inMemory
        return try! ModelContainer(
            for: DrinkEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
