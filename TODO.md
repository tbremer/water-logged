# TODO — Code Review Findings

Prioritized list of suggested changes from a static review of the Water Logged
watchOS app. Items are ordered by priority (P0 highest). Each item notes the
**impact**, **location**, and a **suggested fix**. Nothing here was built or
run — these are findings from reading the source.

---

## P0 — Correctness / user-facing bugs

### 1. `reschedule` can run concurrently and is invoked redundantly
- **Impact:** `HydrationScheduler.reschedule` starts with `removeAllPendingNotificationRequests()`, then `await`s authorization + a HealthKit query before re-adding requests. It is fired from four places that can overlap, so two runs can interleave inside those `await` gaps (clear → clear → add → add) and thrash the pending set. It is also run twice on every cold launch (delegate launch + scene becomes active) and **five times** when the Settings screen changes several values.
- **Where:**
  - `WaterLogged/Notifications/HydrationScheduler.swift:42`
  - launch + scene: `WaterLogged/WaterLoggedApp.swift:15`, `WaterLogged/Notifications/AppDelegate.swift:13`
  - settings: `WaterLogged/Views/SettingsView.swift:68`
- **Fix:** Make `HydrationScheduler` an `actor` (or `@MainActor`) and serialize reschedules — e.g. coalesce/debounce rapid calls and cancel an in-flight reschedule before starting a new one. Drop one of the duplicate launch triggers.

### 2. Invalid active window silently disables all reminders
- **Impact:** `reschedule` does `guard startHour <= endHour else { return }`. The Settings incrementers let Start go up to 23 and End down to 0 with no coupling, so a user who sets e.g. Start 10 PM / End 8 AM (a reasonable "overnight" intent) gets **zero reminders and no feedback**. `start == end` yields a single reminder. There is no validation in `AppSettings` or the UI.
- **Where:** `WaterLogged/Notifications/HydrationScheduler.swift:59`; UI `WaterLogged/Views/SettingsView.swift:40`; model `WaterLogged/Settings/AppSettings.swift:37`.
- **Fix:** Clamp in the UI (End can't go below Start+1, Start can't exceed End−1), or validate in `AppSettings`, or explicitly support overnight windows. At minimum show a warning when the window is empty.

### 3. `estimatedWakeHour` is statistically unreliable — sleep-aware trim is largely ineffective
- **Impact:** It averages the `.hour` of the **end date of every asleep segment** (core/deep/REM all produce many short segments through the night). Those segment ends cluster in the middle of the night, so the average typically lands around 02:00–05:00, well below the default 8 AM start; `max(startHour, wake)` then has no effect. Numeric hour averaging also breaks near midnight (23 and 1 average to 12). Net: the "respect sleep schedule" morning trim rarely changes anything, and when it does it can be wrong.
- **Where:** `WaterLogged/Health/SleepScheduleProvider.swift:86` (esp. `:105`–`:111`).
- **Fix:** Group samples into sleep **sessions** (gap-based), take the latest `endDate` per session as that night's wake time, then average those few values (or take the median). Consider circular averaging if midnight wrap is possible.

### 4. Silent save failure with unconditional success haptic
- **Impact:** `WaterLog.add` uses `try? context.save()`, so a failed insert is swallowed. `TodayView.log` plays `.success` haptic regardless, so the user believes water was logged even if it wasn't. The notification action path has no feedback at all.
- **Where:** `WaterLogged/Support/WaterLog.swift:12`; haptic at `WaterLogged/Views/TodayView.swift:45`.
- **Fix:** Return a `Bool`/throw from `add`, log the error (at least under `#if DEBUG`), and only play the success haptic on a confirmed save (play a failure haptic otherwise).

---

## P1 — Quality / maintainability / latent issues

### 5. Swift 6 concurrency hardening
- **Impact:** Project is on Swift language mode 5, which hides several isolation issues (the shared mutable `HydrationScheduler` singleton, `WaterLog.add` call sites from the notification delegate, `HKHealthStore`/sample `Sendable`-ness). Bumping to 6 today would surface errors.
- **Where:** `project.yml:15`; ties into item #1.
- **Fix:** Adopt actor/`@MainActor` isolation (item #1), audit `Sendable` conformances, then flip `SWIFT_VERSION` to `6.0`.

### 6. Dead / unused UI code
- **Impact:** Confusing and produces "never used" warnings. `IncrementerRow` accepts a `glyph` parameter that is **never rendered** (the leading icon it was meant to show is missing on every Settings row). The `RowGlyph` view is defined but unused. Commented-out `Label`/preview lines linger.
- **Where:** `WaterLogged/Views/SettingsView.swift:98` (unused `glyph`, passed at `:14`, `:41`, `:48`), `:83` (`RowGlyph`), `:26`, `:35`; `WaterLogged/Views/RootView.swift:6`.
- **Fix:** Either wire `glyph` into `IncrementerRow`'s body (via `RowGlyph`) to restore the intended icons, or remove the parameter and `RowGlyph`. Delete stale commented code (keep the intentional `TabView` note per AGENTS.md).

### 7. `Formatters.hourLabel` recreates a `DateFormatter` per call and ignores 24-hour locales
- **Impact:** `DateFormatter` allocation is relatively expensive and this is called per Settings render; the hardcoded `"h a"` format shows "8 AM" even for users whose locale uses 24-hour time.
- **Where:** `WaterLogged/Support/Formatters.swift:5`.
- **Fix:** Cache a `static` formatter (or use `Date.FormatStyle`) and let it respect the locale's hour preference.

### 8. Unbounded `@Query` + per-render regrouping in history
- **Impact:** `HistoryView` loads **all** `DrinkEntry` rows and regroups them by day on every body evaluation; the dataset grows forever. Fine early on, slower over months/years.
- **Where:** `WaterLogged/Views/HistoryView.swift:7`, `:15`.
- **Fix:** Add a fetch limit / date window, or precompute daily aggregates. Cache the grouping rather than recomputing in the `body`-derived property.

### 9. Notification permission prompt fires immediately on first launch
- **Impact:** `reschedule` calls `requestAuthorization()` during `applicationDidFinishLaunching`, so the system prompt appears before the user sees any context.
- **Where:** `WaterLogged/Notifications/HydrationScheduler.swift:46` via `AppDelegate.swift:13`.
- **Fix:** Request notification authorization at a deliberate moment (first view of Today, or when reminders are toggled on) rather than at launch.

### 10. "Today" predicate is captured at view init and goes stale across midnight
- **Impact:** `TodayView` builds its date-range `#Predicate` in `init` using `startOfDay(for: Date())`. If the app stays foregrounded across midnight, the ring keeps showing the previous day.
- **Where:** `WaterLogged/Views/TodayView.swift:10`.
- **Fix:** Re-evaluate the day boundary on `scenePhase`/significant-time-change, or key the query off a day value that refreshes.

### 11. Notification quick-actions (8/16) diverge from in-app increments (8/12/16)
- **Impact:** Two independent definitions of "increments" that can drift; the notification only offers 8 and 16 while the app offers 8/12/16. Easy to update one and forget the other.
- **Where:** `WaterLogged/Notifications/HydrationScheduler.swift:16`/`:24`, handled in `AppDelegate.swift:40`; vs `WaterLogged/Models/DrinkSize.swift`.
- **Fix:** Derive the notification actions from `DrinkSize` (or document deliberately why they differ).

### 12. Dangling test config with no test target
- **Impact:** The scheme declares a `test` configuration but there is no test target or tests, so "run tests" fails and there is zero automated coverage of the testable logic (formatters, interval stepping, day grouping, wake-hour math).
- **Where:** `project.yml:46`.
- **Fix:** Add a unit-test target with tests for `Formatters`, the scheduling step loop, history grouping, and `estimatedWakeHour` — or remove the dangling `test:` scheme entry.

---

## P2 — Docs / cosmetics / release hygiene

### 13. README/doc-comment increment mismatch (8/16/24 vs actual 8/12/16)
- **Impact:** Misleading docs. `DrinkSize` is the source of truth (8/12/16); prose says 8/16/24 in several places, and the `LogButtonsView` doc comment is wrong too.
- **Where:** `README.md:6`, `README.md:173`; `WaterLogged/Views/LogButtonsView.swift:3`.
- **Fix:** Update prose/comments to 8/12/16 (and reconcile the notification-action claim in `README.md:6`, which implies all three increments are loggable from the notification when only 8/16 are).

### 14. Stale doc comment in `ProgressRingView`
- **Impact:** References a previous `accessoryCircularCapacity` gauge implementation that no longer exists.
- **Where:** `WaterLogged/Views/ProgressRingView.swift:11`.
- **Fix:** Trim the comment to describe the current ring only.

### 15. No localization despite `SWIFT_EMIT_LOC_STRINGS: YES`
- **Impact:** All user-facing strings are hardcoded English; the flag implies an intent to localize that isn't realized.
- **Where:** throughout `Views/` and `Support/Formatters.swift`; `project.yml:37`.
- **Fix:** If localization is a goal, extract strings into a catalog; otherwise drop the flag to reflect reality.

### 16. Release checklist: promote dev entitlements / CloudKit schema before App Store
- **Impact:** `aps-environment` is `development` and the CloudKit schema is dev-only; shipping requires promoting both.
- **Where:** `WaterLogged/WaterLogged.entitlements:15`; noted in `README.md:158`.
- **Fix:** Add a pre-submission checklist (promote `aps-environment` to `production`, promote CloudKit schema to Production).

### 17. Hardcoded Team ID / bundle id / iCloud container
- **Impact:** Real Apple Team ID (`Z5DFW5G77C`), bundle id, and container id are committed. Expected for a single-owner repo, but a sharp edge before forking/publishing.
- **Where:** `project.yml:16`; `WaterLogged/WaterLogged.entitlements:8`.
- **Fix:** Document this for forkers (or parameterize) so it's a conscious change rather than a silent copy.
