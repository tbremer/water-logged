import Foundation
import SwiftData
import CloudKit

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

    /// The CloudKit account status observed when the container was created.
    /// Resolved once at launch and surfaced in the Settings diagnostics;
    /// `.couldNotDetermine` until then (and on the simulator).
    static private(set) var cloudKitAccountStatus: CKAccountStatus = .couldNotDetermine

    /// Whether CloudKit mirroring is safe to enable: a real device whose iCloud
    /// account is available to CloudKit (read from the resolved status above).
    static var isCloudKitAvailable: Bool { cloudKitAccountStatus == .available }

    /// Human-readable CloudKit account status, for the Settings diagnostics.
    static var cloudKitAccountStatusDescription: String {
        #if targetEnvironment(simulator)
        return "Simulator (local only)"
        #else
        switch cloudKitAccountStatus {
        case .available:              return "Available"
        case .noAccount:              return "No iCloud account"
        case .restricted:             return "Restricted"
        case .couldNotDetermine:      return "Couldn't determine"
        case .temporarilyUnavailable: return "Temporarily unavailable"
        @unknown default:             return "Unknown"
        }
        #endif
    }

    /// The shared container used by the whole app.
    static let shared: ModelContainer = makeContainer()

    /// Resolve CloudKit account availability up front.
    ///
    /// Uses `CKContainer.accountStatus()` — the canonical CloudKit signal —
    /// rather than `FileManager.ubiquityIdentityToken`, which only tracks iCloud
    /// Drive and reads "unavailable" for accounts that are perfectly fine for
    /// CloudKit. `accountStatus()` is async and its callback runs off the main
    /// thread, so we bridge it synchronously with a bounded wait (the container
    /// is built synchronously at launch). On timeout we fall back to local-only.
    private static func resolveCloudKitAvailability() -> Bool {
        #if targetEnvironment(simulator)
        return false   // sim has no provisioned container; mirroring would trap
        #else
        let semaphore = DispatchSemaphore(value: 0)
        var status: CKAccountStatus = .couldNotDetermine
        CKContainer(identifier: cloudKitContainerIdentifier).accountStatus { result, _ in
            status = result
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
        cloudKitAccountStatus = status
        return status == .available
        #endif
    }

    static func makeContainer() -> ModelContainer {
        // 1) Preferred: CloudKit-synced private database (real device, account available).
        if resolveCloudKitAvailability(),
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
