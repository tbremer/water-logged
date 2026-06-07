# AGENTS.md

A map, not a mirror — orientation for an LLM working in this repo, not exhaustive docs. General Swift/SwiftUI/SwiftData/watchOS knowledge is assumed; only the non-obvious, repo-specific facts are here.

## What this is

A **standalone watchOS hydration app** (Water Logged): hourly "time to hydrate" reminders, one-tap logging, daily goal ring, history, optional iCloud sync. SwiftUI + SwiftData(+CloudKit) + HealthKit + UserNotifications, watchOS 10+.

Two defining traits set expectations:
- **There is no iPhone app target.** Watch-only (`WKWatchOnly` in Info.plist, `TARGETED_DEVICE_FAMILY=4`). Do not add an iOS/companion target unless asked.
- **The Xcode project is generated.** `WaterLogged.xcodeproj` is produced by XcodeGen from `project.yml` and is git-ignored. Edit `project.yml`, never the `.pbxproj`.

## Core mental model

The app is a handful of **global singletons wired together as dependency injection**, over a **single SwiftData model**.

- One model: `DrinkEntry` (`id: UUID`, `amountOunces: Double`, `timestamp: Date`). That's the entire schema.
- Singletons (`.shared`): `PersistenceController` (the `ModelContainer`), `AppSettings` (`@Observable`, UserDefaults-backed), `HydrationScheduler` (notifications), `HydrationHealthStore` (optional HealthKit water write). They are injected via `.environment(...)` / `.modelContainer(...)` and read directly by non-UI code (scheduler, background refresh) so UI and background see the same state.
- Reads happen through SwiftUI `@Query`; **inserts happen through `WaterLog.add(...)`** (a `@MainActor` helper), not via raw contexts.

## Architecture & canonical data flow

Layers: `WaterLoggedApp` (`@main`) → `AppDelegate` (lifecycle/notifications) → Views (`@Query`-driven) → `WaterLog`/singletons → SwiftData/`PersistenceController`.

Bootstrap: `WaterLoggedApp` adapts `AppDelegate` via `@WKApplicationDelegateAdaptor`. `applicationDidFinishLaunching` sets the `UNUserNotificationCenter` delegate, calls `HydrationScheduler.registerCategories()`, reschedules, and arms a ~3:30 AM background refresh. The `WindowGroup` shows `RootView` with `AppSettings.shared` in the environment and `PersistenceController.shared` as the model container; `scenePhase == .active` reschedules reminders.

Canonical trace — **logging a drink** (the one flow to internalize):
`TodayView.log(ounces:)` → `WaterLog.add(ounces:)` → inserts a `DrinkEntry` into `PersistenceController.shared.mainContext`, saves, and clears delivered notifications → `TodayView`'s today-filtered `@Query` recomputes the total → `ProgressRingView` updates. The notification quick-actions hit the **same** sink: `AppDelegate.userNotificationCenter(_:didReceive:)` → `WaterLog.add`.

## File map (open just-in-time)

- `WaterLogged/WaterLoggedApp.swift` — **start here**; `@main`, container + scene wiring.
- `WaterLogged/Persistence/PersistenceController.swift` — `ModelContainer` factory; CloudKit-vs-local gating (read this before touching persistence).
- `WaterLogged/Models/DrinkEntry.swift` — the only `@Model`; CloudKit-constrained (see Gotchas).
- `WaterLogged/Models/DrinkSize.swift` — in-app quick-log increments (source of truth for the Today buttons).
- `WaterLogged/Support/WaterLog.swift` — the insert path for code without a `modelContext`.
- `WaterLogged/Settings/AppSettings.swift` — `@Observable` settings + UserDefaults keys/defaults; copy this shape to add a setting.
- `WaterLogged/Notifications/HydrationScheduler.swift` — builds the repeating reminder set; notification categories/actions.
- `WaterLogged/Notifications/AppDelegate.swift` — notification delegate, action handling, background refresh.
- `WaterLogged/Health/HydrationHealthStore.swift` — optional, best-effort HealthKit write of logged water as `dietaryWater`.
- `WaterLogged/Views/` — `RootView` (paged TabView), `TodayView`, `ProgressRingView`, `LogButtonsView`, `HistoryView`, `DayDetailView`, `SettingsView`.
- `WaterLogged/Support/Formatters.swift` — display-string helpers (ounces, hour label, interval).
- `project.yml` — XcodeGen spec (build settings, signing, entitlements wiring).
- `Scripts/run-sim.fish` — generate + build + launch on a simulator.
- `Tools/MakeIcon.swift` — regenerates the app-icon PNG; not part of the app build.

## Legacy / dormant / distractors (do not trust blindly)

- **Stale increment claims.** `README.md` and the `LogButtonsView` doc comment say "8 / 16 / 24 oz". The actual in-app buttons render from `DrinkSize` = **8 / 12 / 16 oz**. `DrinkSize` is the truth for Today's buttons; the prose is out of date.
- **Two independent increment definitions.** Notification quick-actions are a *separately hardcoded* **8 oz / 16 oz** (`HydrationScheduler.actionLog8/16` + `AppDelegate`), unrelated to `DrinkSize`. Changing one does not change the other — update both if you intend them to match.
- **`RootView` has commented-out preview lines** for showing a single screen; the comment says do not delete the `TabView`. Respect that.
- **No tests exist.** The scheme declares a test config but there is no test target or test files. Do not assume a test command works.

## Conventions & idioms

- **Singleton-as-DI.** Add cross-cutting services as a `static let shared` and inject via environment/container; do not thread instances through initializers.
- **Settings pattern.** Each `AppSettings` property is `var ... { didSet { defaults.set(...) } }` with a `Key` constant and an entry in `register(defaults:)`. New settings must touch all three places; persisted values are re-validated on load (e.g. `reminderIntervalMinutes` falls back to 60 if not in `reminderIntervalChoices`).
- **Writes.** Inserts go through `@MainActor WaterLog.add`. Deletes are done inline via `@Environment(\.modelContext)` in `HistoryView`/`DayDetailView` (the only views that mutate directly).
- **Date-scoped queries.** Views build a `#Predicate` over `timestamp` in their `init` (see `TodayView`/`DayDetailView`) rather than filtering in memory; copy that shape for new day/range views.
- **HealthKit is best-effort.** All of `HydrationHealthStore` is `#if canImport(HealthKit)`-guarded and silently no-ops on any failure — it never throws into callers. Keep that contract.
- **Swallow-and-fallback error handling.** `try?` is used deliberately so missing capabilities degrade instead of crashing (see persistence + scheduler). Don't convert these to forced unwraps.
- Display strings come from `Formatters`; haptics via `WKInterfaceDevice.current().play(...)`.

## Build / run / setup

- Generate the project after any file add/rename/move: `xcodegen generate` (install once: `brew install xcodegen`).
- Simulator one-shot: `./Scripts/run-sim.fish` (default device `Apple Watch Series 11 (46mm)`; pass another name as `$1`). It generates, builds with `CODE_SIGNING_ALLOWED=NO`, boots, installs, launches `com.tbremer.waterlogged`.
- If a runtime is missing: `xcodebuild -downloadPlatform watchOS`.
- **`DEVELOPMENT_TEAM` lives in `project.yml`** (`Z5DFW5G77C`), not Xcode's UI — set it there or `xcodegen generate` overwrites the UI value.
- Swift language mode is **5** (`SWIFT_VERSION` in `project.yml`); bump to `6.0` to opt into strict concurrency checking.
- Device builds need a **paid** Apple Developer membership (iCloud/HealthKit/push/time-sensitive entitlements are restricted). Free-account path requires stripping those entitlements + the Health usage string — recipe is in `README.md`.

## Gotchas / known issues

- **CloudKit must be gated up front.** `ModelContainer(...)` constructs fine even when CloudKit can't work, then Core Data's mirroring layer **crashes asynchronously on its own queue** — a `try?` cannot catch it. `PersistenceController.isCloudKitAvailable` decides first; simulator is always local-only, device requires a signed-in iCloud account. Fallback chain is CloudKit → local → in-memory.
- **Keep `DrinkEntry` CloudKit-safe** or sync breaks: every stored property must have a default, no `@Attribute(.unique)`, no required (non-optional) relationships.
- `PersistenceController.cloudKitContainerIdentifier` must stay in sync with the container in `WaterLogged.entitlements`.
- **Notification budget.** `HydrationScheduler.reschedule` removes all pending requests, then adds repeating calendar triggers capped at 60 (system limit is 64; headroom left for snoozes). Don't schedule per-event without accounting for this.
- watchOS exposes **no wrist-detection API**; reminders are only schedule/time-gated (active hours). "Only when worn" is not achievable — don't try to add it.

## Security considerations

- `project.yml`/entitlements commit a real **Apple Team ID** (`Z5DFW5G77C`), bundle id, and iCloud container id. Expected for this single-owner repo, but surface this before forking/publishing rather than silently changing it.
- `aps-environment` is `development`; switching to App Store distribution requires promoting it (and the CloudKit schema) to production — flag, don't auto-change.
- No API keys/secrets in the repo. HealthKit is write-only (dietary water); no read scopes.

## Working agreement for agents

- Default to the live path; read `PersistenceController` and `AppSettings` before assuming how state flows.
- Insert drinks via `WaterLog.add`; read via `@Query`; add a setting by copying the `AppSettings` property/Key/register triad.
- Never hand-edit `WaterLogged.xcodeproj` — change `project.yml` and regenerate.
- Match the local swallow-and-fallback error style and the singleton-DI pattern; do not introduce new architecture, dependencies, or an iPhone target unprompted.
- Treat README prose as marketing, not spec, when it conflicts with code (notably the drink increments).
