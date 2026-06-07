# Purpose
unplanned tasks that should be accomplished. Could be bugs or new features. LLM will need to research and present a plan for implementation, seeking approval from user before before implementing.

## HealthKit integration

> **Resolved (v0.0.11):** the sleep feature was removed — reminders now rely on the
> active-hours window. With only hydration-write remaining, the "single sheet" and
> "auto-toggle on grant" items no longer apply; Health write access is requested on
> demand when the user enables "Save to Apple Health". (Sleep read grant also can't
> be reliably detected via HealthKit, which informed the decision to drop it.)

When requesting access to health features (ie: sleep and hydration) we should do this in a single sheet, not two separate requests.
If health access is approved, we need to ensure the co-located settings  are toggled appropriately.

Scenarios:
- If a user accepts hydration logging the application should automatically toggle the setting to push hydration logs to apple health
- If a user accepts sleep tracking the application should automatically toggle the setting to respect sleep schedule
