# Doseify — Product Specification

**Status:** Approved v1, June 2026.

> This app helps a real person manage real cancer medication. Before relying on it clinically, confirm timing tolerances and the timezone-shift rate with her oncologist. The 30 min/day default is a common chronopharmacology guideline, not a per-drug clinical recommendation.

---

## 0. How to use this document

- This is the source of truth for **product behaviour**.
- `CLAUDE.md` is the source of truth for **tooling, conventions, and hard rules**.
- Section numbers are referenced in commit messages (e.g., `see SPEC §2.4`).
- Open questions are in §12 — surface them to the user, do not guess answers.

---

## 1. Context & goals

- **Primary user:** a single person managing oral medication for CLL.
- **Differentiator:** existing medication apps don't handle international travel gracefully. Doseify migrates dose times smoothly across timezones without forcing 3 a.m. local doses.
- **Distribution:** TestFlight beta first (personal use), planned for App Store release. Spec choices must not block App Store submission (privacy strings present, no hardcoded user identity, etc.).
- **Platforms:** iPhone + Apple Watch.
- **Minimum OS:** iOS 17 / watchOS 10.
- **Data residency:** local-first on device. No cloud sync in v1.

---

## 2. Core features

### 2.1 Medication management

- Multiple concurrent medications, each with its own fixed schedule.
- Per-medication configuration:
  - Name, color/icon, optional pill photo
  - Dose amount + unit ("100 mg", "1 capsule")
  - Schedule: days of week + one or more times of day
  - With-food flag (display only)
  - On-time scoring window (default 5 minutes)
  - Late cutoff (default 120 minutes → "missed")
  - Per-drug timezone shift rate (default 30 min/day, configurable)
  - Inventory count + refill threshold
  - Free-text notes, active/paused toggle
- Edit history retained. Changing a schedule must not retroactively rewrite past dose events.
- **v1 deferred (schema must permit later):** ramp-up / taper schedules (Venetoclax-style). Build `Schedule` with `versionEffectiveFrom` so a future migration can introduce versioned schedules without data loss.

### 2.2 Reminders

Three-stage chain per dose:

1. **Pre-alert** — configurable lead time per medication, default 10 minutes.
2. **At-time** — at the scheduled time.
3. **Escalating follow-ups** — at +5, +15, +30 minutes if not logged, until logged or cutoff reached.

Notification action buttons: **Taken now** / **Snooze 5 min** / **Skip dose**.

`isCriticalAlert` flag per medication (overrides Do Not Disturb). See §10 risk on entitlement — implement with `interruptionLevel = .timeSensitive` by default and a feature flag for `.critical`.

Quiet hours: configurable window suppresses escalating follow-ups (pre-alert and at-time still fire).

### 2.3 Dose logging

- Log paths: notification action button, iPhone home-screen widget, Apple Watch app/complication, Lock Screen widget, Shortcuts action.
- "Log past dose" flow for back-dating when she forgets to log in the moment.
- Optional per-dose note.
- Once logged, status is locked except via explicit edit. Edits are recorded; the original log is preserved in history.

### 2.4 Timezone shifting

This is the differentiator. Two interacting modes:

**Planned trip (preferred):**
- User creates a Trip: destination timezone, start date, end date, optional name.
- App pre-computes per-medication shift schedule and shows a preview ("Day 1: dose at 8:00 AM home time / 8:30 AM destination-shifted … Day 6: locked to destination 8:00 AM local").
- Shift direction = shortest path (east vs. west).
- Strategy per trip:
  - **Gradual shift** (default): per-drug rate (default 30 min/day).
  - **Immediate shift**: snap to destination time on day 1.
  - **No shift**: stay on home time for the whole trip.
- Return shift home is automatically scheduled at the same rate.

**Auto-detect (fallback):**
- Listen for `NSSystemTimeZoneDidChange`.
- If no active Trip covers the current time, prompt: "You're now in [TZ]. Start shifting your schedule?"
- Options: Start gradual / Apply immediately / Not traveling — keep home time.

**Precedence:** active planned Trip wins over auto-detect during overlap.

**Dosing safety rules (owner-directed, override earlier drafts — June 2026):**
- **Doses follow the body clock.** The schedule migrates the geographic **short way** at the per-drug rate. During a gradual shift the dose *is* the traveller's body-time, so it is **never held or skipped because the local clock reads an awkward hour** (no "sleep window" avoidance). A dose may temporarily appear at an unusual *local* time mid-transition; that is expected and safe.
- **Skipping is for overdose prevention only.** A dose is skipped **only** when a flight realignment would place it closer than the drug's minimum safe gap (`minSpacingHours`, default 11h) to the previous dose. **At most one skip on the outbound flight and one on the return flight.** If more would be needed, keep the dose and flag the trip for the user/oncologist to review — never auto-skip more.
- Engine always migrates the short way; the "long way round" is not used.

**Edge cases the engine must handle (test these):**
- Trip too short to complete gradual shift → warn at trip creation, offer immediate or no-shift.
- User edits home timezone → confirmation dialog, no retroactive changes to past dose events.
- Dose taken right before phone detects a timezone change → dose stays anchored to the timezone in effect when it was scheduled.
- Multi-leg trip (home → A → B → home) → support a sequence of Trips.
- East vs. west shift past the international date line → choose the shorter shift direction by absolute hour delta, not signed.

**Display:**
- Today screen labels shifted doses: "8:30 AM (shifted +30 min for travel to London)".
- Trip detail view shows the full per-day, per-drug shift schedule.

### 2.5 Adherence & gentle gamification

- **Per-dose score:** 100% if logged within 5 min of dose time (per-drug configurable), linear decline to 0% at 120 min after, then "missed" if not logged.
- **Streak counter:** consecutive days where all scheduled doses were logged (any score > 0).
- **Adherence percentages:** rolling 7-day, 30-day, 90-day, all-time. Show both raw % and average on-time-score %.
- **Gentle milestones:** quiet animated celebration at 7 / 30 / 90 / 180 / 365 day streaks. Warm and dignified — no confetti, no loud sounds, no shame language for misses.
- **No leaderboards, no social, no points-as-currency.**

### 2.6 Pill inventory + refill reminders

- Per-medication pill count, auto-decremented on each logged dose.
- Refill threshold (default: enough for 7 more days at current dose rate).
- Notification when threshold crossed.
- Manual inventory adjustment.
- Optional pharmacy name / phone field (stored only).

### 2.7 Side effect / symptom log

- Quick logger: severity 1–10, optional body area tag, free-text description.
- Standalone or attached to a specific dose event.
- Appears in adherence report.

### 2.8 Adherence report export

- PDF for any date range: per-medication adherence %, on-time score average, list of missed/late doses with timestamps, side effect log.
- CSV export of raw dose-event log.
- Share sheet integration.

### 2.9 Apple Watch companion

- Complication: "Next dose in 47 min" / "Dose due now: [med name]".
- Notification with the same action buttons as iPhone.
- Today view: list of remaining scheduled doses, tap to log.
- Must function without iPhone in reach (during exercise).

### 2.10 HealthKit integration

- Write dose-taken events using `HKCategoryTypeIdentifierMedicationEvent` (verify availability — see §10).
- On first launch, offer to import medications already in Apple Health.
- Read-only otherwise. Do not depend on HealthKit as source of truth.

---

## 3. Data model (SwiftData)

```swift
@Model class Medication {
    var id: UUID
    var name: String
    var colorHex: String
    var iconName: String?
    var pillPhoto: Data?
    var doseAmount: Double
    var doseUnit: String
    var schedule: Schedule
    var withFood: Bool
    var onTimeWindowMinutes: Int         // default 5
    var cutoffMinutes: Int               // default 120
    var preAlertMinutes: Int             // default 10
    var timezoneShiftMinutesPerDay: Int  // default 30
    var inventoryCount: Int
    var refillThresholdDays: Int         // default 7
    var isCriticalAlert: Bool
    var notes: String?
    var isActive: Bool
    var createdAt: Date
    var doses: [DoseEvent]
}

@Model class Schedule {
    var daysOfWeek: [Int]                // ISO 1..7
    var timesOfDay: [TimeOfDay]
    var versionEffectiveFrom: Date       // future-proof for ramp-up
}

@Model class DoseEvent {
    var id: UUID
    var medication: Medication
    var scheduledTimeHome: Date          // UTC, anchored in home tz
    var effectiveScheduledTime: Date     // after shift adjustment
    var effectiveTimezone: String        // tz identifier at scheduling
    var loggedTime: Date?
    var status: DoseStatus               // pending, taken, missed, skipped
    var score: Double                    // 0–100
    var note: String?
}

@Model class Trip {
    var id: UUID
    var name: String
    var destinationTimezone: String
    var startDate: Date
    var endDate: Date
    var shiftStrategy: ShiftStrategy     // gradual, immediate, none
    var status: TripStatus               // planned, active, completed, cancelled
}

@Model class SideEffectLog {
    var id: UUID
    var timestamp: Date
    var severity: Int                    // 1–10
    var bodyArea: String?
    var notes: String
    var relatedDose: DoseEvent?
}

@Model class UserSettings {
    var homeTimezone: String
    var autoDetectTimezone: Bool         // default true
    var quietHoursStart: TimeOfDay?
    var quietHoursEnd: TimeOfDay?
    var theme: AppTheme                  // light, dark, system
}
```

---

## 4. Architecture notes

| Concern | Choice |
|---|---|
| Language / UI | Swift 5.10+, SwiftUI |
| Persistence | SwiftData (local only) |
| Notifications | UNUserNotificationCenter + categories + actions |
| Background | BGAppRefreshTask for scoring rollover, refill, missed-dose marking |
| Watch | WatchConnectivity, WidgetKit (complications, Lock Screen) |
| HealthKit | HKHealthStore (write-only initially) |
| Timezone | NSSystemTimeZoneDidChange + optional CoreLocation confirmation |
| PDF | PDFKit |

**Notification scheduling:** iOS caps at 64 pending notifications per app. Schedule the next N eagerly, rebuild on dose log or schedule change.

**Time math:** never store local times as naive `Date` without an explicit tz reference. `scheduledTimeHome` is UTC; `effectiveTimezone` records the local zone at scheduling.

**Service boundaries (suggested):**
- `MedicationStore` — SwiftData CRUD wrapper.
- `Scheduler` — translates Schedule + UserSettings + active Trip into a stream of upcoming DoseEvent records.
- `TimezoneShiftEngine` — pure functions: given home tz, destination tz, strategy, trip dates, and a date, return effective dose time. Heavily unit-tested.
- `NotificationService` — wraps UNUserNotificationCenter, manages the 64-slot queue.
- `DoseScorer` — pure: given scheduled time, logged time, window, cutoff → score.
- `AdherenceCalculator` — pure: given dose events and date range → percentages, streaks.
- `HealthKitGateway` — write-only, graceful no-op on failure.
- `ReportExporter` — PDF + CSV generation.

Pure functions (TimezoneShiftEngine, DoseScorer, AdherenceCalculator) must be implemented as `struct` with `static` methods or free functions and have full unit test coverage.

---

## 5. UX guidance

- **Tone:** warm, personal, wellness-app aesthetic — closer to Headspace/Calm than to a clinical pill app.
- **Color palette:** soft gradients, muted but warm — sage, peach, slate. Avoid sterile blue-white.
- **Typography:** SF Rounded, generous whitespace, large hit targets.
- **Copy voice:** encouraging without being saccharine. "Nice — 30 days in a row." Not "AMAZING JOB!!!"
- **No medical jargon** in app chrome; user-entered drug names appear as-is.
- **Dark mode:** first-class — used on the nightstand.
- **Accessibility:** full VoiceOver, Dynamic Type, AX-large tap targets, color is never the only signal.
- **First-run flow:** explain home timezone, add first medication, schedule first dose. Under 60 seconds.

---

## 6. Suggested build phases

Phasing is not prescriptive — Claude Code may sequence as it sees fit, but each shipped phase must produce a working build runnable in the simulator.

1. **Core:** Medication CRUD, schedule, local notifications, dose logging, SwiftData persistence.
2. **Adherence:** Scoring math, streaks, stats screen.
3. **Timezone engine:** Trip planner, auto-detect, shift computation, preview UI.
4. **Watch + HealthKit:** Watch companion, complications, HealthKit write.
5. **Polish:** Inventory, refill reminders, side effect log, PDF/CSV export.

---

## 7. Out of scope (v1)

- Ramp-up / taper schedules (reserve schema room only).
- Cloud sync / iCloud backup / multi-device.
- Family sharing or caregiver view.
- Drug interaction checking.
- Pharmacy integrations / e-refills.
- Doctor portal / shared dashboards.
- Apple Health *read* of dose events from other apps as source of truth.

---

## 8. Acceptance scenarios

Use these as the v1 acceptance test list. All must pass before TestFlight submission.

1. Med scheduled 8:00 AM, logged 8:03 AM → score 100, streak increments.
2. Med scheduled 8:00 AM, logged 9:00 AM → score ~50 (linear decline), counted in adherence but not "on-time".
3. Med never logged, 120 min passes → marked missed, streak breaks.
4. Trip to London (5 hr east), 10-day stay, 30 min/day shift → dose lands on London 8:00 AM by day 10; return shift starts on travel-home day.
5. 2-day trip to Tokyo (14 hr) at 30 min/day → app warns at trip creation and offers immediate or no-shift.
6. Unplanned travel, phone tz changes mid-day → prompt appears, user picks gradual; engine starts shifting from next dose.
7. Med at 14 pills, threshold 7 days × 1 dose/day → refill notification fires at pill count 7.
8. "Taken now" tapped from Watch → DoseEvent.loggedTime set to tap time, score computed, HealthKit write succeeds (or gracefully no-ops).
9. Killing the app and relaunching does not lose any DoseEvent or change any score.
10. Two doses scheduled within the on-time window of each other are independently scored.

---

## 9. Privacy & data handling

- No analytics, telemetry, crash reporting, or third-party SDKs.
- HealthKit usage string: `"Doseify writes the medications you log so they appear in your Health timeline."`
- Location usage string (if CoreLocation used): `"Doseify uses location only to confirm timezone changes when you travel. Your location is never stored."`
- Draft privacy policy when phase 5 nears completion.

---

## 10. Risks & flags

| Risk | Mitigation |
|---|---|
| No backup = data loss | User did not select iCloud. Prompt monthly PDF export. Revisit iCloud decision post-v1. |
| TestFlight builds expire every 90 days | Calendar reminder to rebuild and resubmit. |
| HealthKit medication API drift | Wrap writes in `HealthKitGateway` that gracefully no-ops on rejection. Never let HealthKit block dose logging. |
| Critical Alerts entitlement is hard for personal apps | Default to `.timeSensitive`; gate `.critical` behind a feature flag. |
| Airport tz flakiness during layovers | Always require user confirmation before shifting. Never silently re-anchor. |
| Clinical safety review needed | Confirm 30 min/day rate and 5-min/120-min defaults with her oncologist before relying on the app. |

---

## 11. Open questions for the product owner

Surface these — do not guess.

1. Target iOS: 17 (SwiftData) or 18? Depends on her phone.
2. Pursue Critical Alerts entitlement, or accept `.timeSensitive`?
3. HealthKit medication-event write API — confirm current behaviour on target iOS before sinking time into it.
4. Oncologist sign-off on 30 min/day shift rate for her specific regimen.
5. Watch face style preference (modular, infograph) — affects complication design.

---

## 12. Name

"Doseify" was chosen by the product owner. Web search did not surface a direct App Store medication-app match, but verify before paying for developer account / domains / marketing:

1. Direct App Store search on iOS and macOS App Stores.
2. USPTO TESS at https://tmsearch.uspto.gov/ — classes 9 (software) and 44 (medical services).
3. Domain check: doseify.com, doseify.app, doseify.io.
