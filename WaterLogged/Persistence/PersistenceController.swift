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

    /// Must match the iCloud container in `WaterLogged.entitlements`.
    static let cloudKitContainerIdentifier = "iCloud.com.tbremer.waterlogged"

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
            return container
        }

        // 3) Last resort: in-memory so the UI still works this session.
        return try! ModelContainer(
            for: DrinkEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
