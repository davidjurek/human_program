# Human Program iOS — Application Design Document

**Last updated:** 2026-05-29  
**Platform:** iOS 17+  
**Language:** Swift 5.10+, SwiftUI, SwiftData  
**Purpose:** Authoritative product and architecture spec for AI agents and the owner.

---

## 0. Owner Decisions (overrides everything else)

These are locked-in decisions. Do not second-guess or work around them without explicit owner approval.

| Decision | Rule |
|---|---|
| Minimum OS | iOS 17+ |
| Persistence | SwiftData only |
| Third-party dependencies in binary | None. Zero. XcodeGen is a dev tool only. |
| Cloud, analytics, Firebase, trackers, ads | Not present, not planned |
| App lock | Face ID + PIN (4–20 digits). Forget PIN = reset app. No recovery phrase. |
| Backup encryption | .hprgm backups are NOT encrypted. App lock protects on-device data. iOS encrypts at rest when device is locked. |
| Sleep block | Mandatory first block in every schedule template. Cannot be deleted. |
| Exercise and completion | Exercise does NOT count toward day completion unless a separate required task exists for it. |
| Swipe-to-delete | Never, anywhere in the app. |
| Confirmation dialogs for delete | None. Undo/redo is the safety net. |
| Weekday encoding | 1=Sun 2=Mon 3=Tue 4=Wed 5=Thu 6=Fri 7=Sat. This is iOS Calendar `.weekday`. Use it everywhere, without exception. |
| Cat Corner | Kept. Owner will provide photos later. |
| Hidden human rights document | Kept. Double-tap the version label in About to reveal it. |
| Easter egg gate puzzle | Simplified to a 4x4 Latin-square puzzle (not a full Sudoku). |
| Van Gogh picture | Removed. |
| Recovery phrase | Removed. Forget PIN = reset. Full stop. |
| Daily page generation | On app open and on-demand when browsing dates. No background jobs needed because pages are pre-generated when browsing ahead. |
| Tags on tasks | Dropped. Not in v1. |
| Metadata (project bucket, source type) | Kept. Hideable in settings. |
| Notification image attachments | Included. |
| Universal search | Deferred to post-v1. |
| Full calendar app inside Human Program | Deferred. v1 shows calendar events in Today only. |
| Database-level encryption | Not implemented. iOS encrypts app storage when device is locked. |

---

## 1. What is Human Program

Human Program is a personal daily operating system for iOS.

Every day, the app generates one page. That page combines everything you need to do: tasks that repeat on a schedule (recurring), items you've queued up for the day (backlog), things you added manually, and events from your calendar. Together these form a single required checklist. The schedule section shows when to do what, but the schedule blocks themselves are not part of the checklist.

When every required task is checked off, the day is complete. Completing the day unlocks a hidden game — a small reward baked into the app, not advertised anywhere. The game entry is found by double-tapping the developer name on the About screen, but only works when today is actually done.

The design goal: clean, opinionated, and personal. Not a generic productivity app. Not a social app. No cloud sync, no accounts, no analytics. Everything stays on your device.

---

## 2. Architecture Overview

### Two-Container Model

The app uses two separate SwiftData model containers that cannot directly access each other's data.

**Planning Container** owns all planner data:
- Daily pages and tasks
- Recurring task templates
- Backlog items and project buckets
- Schedule templates and blocks
- Exercise routines
- Calendar event local state
- Notification reminders
- Streak and completion state

**Game Container** owns game data:
- Game engine state
- Game saves (per slot)
- Game access unlock records

**GameBridge** is the only allowed communication path between containers. It is a one-way read: the planner's `GameAccessService` and `EasterEggGateService` answer yes/no questions about completion state. The game never reads task tables directly. The planner never reads game state.

### Layered Architecture

Each layer has a strict job. Do not skip layers.

```
Views (SwiftUI)
    ↓ user actions, display state
ViewModels (@Observable @MainActor)
    ↓ prepared screen state, no raw model objects in the view layer
Repositories (@MainActor)
    ↓ own ModelContext, coordinate between services and persistence
Services (pure Sendable structs)
    ↓ business logic with no SwiftData dependency; fully unit-testable
SwiftData Models
    persistence
```

**Views** are dumb. They display state prepared by the ViewModel and send user actions up. Views do not import SwiftData except to receive a ModelContext at init.

**ViewModels** are `@Observable @MainActor` classes. They prepare display state (sorted lists, computed booleans, formatted strings). They call repositories, not services directly.

**Repositories** are `@MainActor` final classes. They own one `ModelContext`. They call services for logic and apply the results to the model objects. They save the context.

**Services** are `Sendable` structs with no SwiftData dependency. All logic lives here. These are the only things that unit tests call directly.

**SwiftData Models** are `@Model` classes. They hold data. They do not contain business logic.

---

## 3. Project Structure

```
HumanProgram/
├── App/
│   ├── HumanProgramApp.swift       — @main entry, creates ModelContainer, launches AppStartup
│   ├── ContentView.swift           — root tab bar
│   ├── AppState.swift              — @Observable global app state (selected tab, viewing date, streak stats, lock state)
│   └── AppStartup.swift            — on-launch sequence (clear overdue, generate today, refresh, recalculate streaks)
│
├── Core/
│   ├── Models/
│   │   ├── Models.swift            — all SwiftData @Model classes and plain Codable structs
│   │   └── RecurrenceRule.swift    — RecurrenceRule struct and RecurrenceFrequency enum
│   │
│   ├── Services/
│   │   ├── RecurrenceEngine.swift  — pure service; matches(), nextOccurrence(), occurrences(), occurrenceLimit counting
│   │   ├── DailyPageGenerator.swift — pure service; generate() and refresh() for daily pages
│   │   ├── CompletionService.swift — pure service; isComplete(), recalculate()
│   │   ├── StreakCalculator.swift  — pure service; calculate() streak stats from snapshots
│   │   └── BacklogMaintenanceService.swift — pure service; clearOverdueAssignments(), syncCompletion(), syncUncompletion()
│   │
│   ├── Repositories/
│   │   ├── DailyPageRepository.swift — getOrCreate, refresh, toggleTask, addManualTask, deleteTask, unlock/lock past page
│   │   └── BacklogRepository.swift   — CRUD for BacklogItem and ProjectBucket, maintenance delegation
│   │
│   ├── Persistence/
│   │   └── ModelContainerSetup.swift — makeModelContainer() for production, makeTestModelContainer() for tests
│   │
│   ├── GameBridge/
│   │   ├── GameAccessService.swift   — canAccessGame(), lockReason()
│   │   ├── EasterEggGateService.swift — shouldRevealGate()
│   │   └── GameContainer.swift       — stub GameContainerView (black screen, "Coming soon")
│   │
│   └── DesignSystem/
│       ├── AppColors.swift           — all color tokens (asset catalog backed, light+dark)
│       └── AppTypography.swift       — all font tokens
│
├── Features/
│   ├── Today/
│   │   ├── TodayView.swift           — main daily page screen
│   │   ├── TodayViewModel.swift      — @Observable ViewModel for Today
│   │   └── Components/
│   │       ├── DateHeaderView.swift  — date header with prev/next/today/picker
│   │       ├── TaskRowView.swift     — single task row (checkbox + title)
│   │       └── CompletionBannerView.swift — green "you are done" banner
│   │
│   ├── Backlog/
│   │   └── BacklogView.swift         — stub (Phase 2)
│   │
│   ├── Routines/
│   │   └── RoutinesView.swift        — stub (Phase 2)
│   │
│   ├── Stats/
│   │   └── StatsView.swift           — stub (Phase 7)
│   │
│   ├── HiddenGate/
│   │   └── SudokuGateView.swift      — full-screen black 4x4 Latin square puzzle + GameContainerView
│   │
│   └── Settings/
│       ├── SettingsView.swift        — settings menu with navigation rows
│       └── AboutView.swift           — version info, Cat Corner, hidden document, easter egg gesture
│
└── Resources/
    └── Assets.xcassets               — named colors for AppColors, app icon

HumanProgramTests/
├── RecurrenceEngineTests.swift
├── DailyPageGeneratorTests.swift
├── CoreServicesTests.swift           — CompletionService, StreakCalculator, BacklogMaintenanceService
├── GameBridgeTests.swift             — GameAccessService, EasterEggGateService
└── PastPageSnapshotTests.swift       — snapshot isolation rules
```

---

## 4. Data Models

All models live in `Core/Models/`. `@Model` classes are persisted by SwiftData. Plain structs are `Codable` and stored as attributes inside model objects.

### 4.1 BacklogItem `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| title | String | Required |
| notes | String | Default empty |
| assignedDate | Date? | Normalized to start-of-day when set |
| status | BacklogStatus | `.backlog` or `.done` |
| project | ProjectBucket? | Optional FK, nullify on delete |
| createdAt | Date | Set at init |
| updatedAt | Date | Updated on mutations |

Rules:
- Unassigned items (`assignedDate == nil`) are unscheduled; they appear in the backlog view but not on any daily page.
- Assigned items appear on the daily page for their date when `status == .backlog`.
- Overdue items (assignedDate < today, status == .backlog) have their `assignedDate` cleared on app startup. They do not auto-roll forward.
- Items with `status == .done` are historical; they do not appear on daily pages.

---

### 4.2 ProjectBucket `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| name | String | User-provided label |
| createdAt | Date | |
| updatedAt | Date | |
| items | [BacklogItem] | Cascade nullify (items keep existing, project field cleared) |

Rules:
- "Unorganized" is a virtual bucket. It is never stored in the database and never deleted. It is used in the UI for items with `project == nil`.
- Real project buckets can be deleted. Their items get `project = nil` (or moved to another bucket).

---

### 4.3 RecurringTaskTemplate `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| title | String | Required |
| notes | String | Default empty |
| recurrenceRule | RecurrenceRule | Codable struct stored as attribute |
| active | Bool | Inactive templates are never added to pages |
| createdAt | Date | |
| updatedAt | Date | |

Rules:
- Only templates where `active == true` are evaluated during page generation.
- Deactivating a template causes its tasks to be removed from today's and future pages on next refresh.

---

### 4.4 RecurrenceRule (plain struct)

`RecurrenceRule` is `Codable`, `Hashable`, `Sendable`. It is stored as an attribute inside `RecurringTaskTemplate` and `ExerciseRoutine`.

| Field | Type | Notes |
|---|---|---|
| frequency | RecurrenceFrequency | One of 8 values |
| weekdays | [Int] | 1=Sun...7=Sat; used for selectedWeekdays and everyNWeeks |
| interval | Int | For everyNDays/everyNWeeks; always >= 1 (enforced at init) |
| anchorDate | Date? | Reference date for interval-based frequencies |
| startDate | Date? | Earliest date the rule can fire |
| endDate | Date? | Latest date the rule can fire (inclusive) |
| occurrenceLimit | Int? | Max number of total occurrences; nil = unlimited |

**RecurrenceFrequency** — all 8 values:

| Value | Behavior |
|---|---|
| `everyDay` | Fires every calendar day |
| `weekdays` | Fires Monday–Friday (weekdays 2–6) |
| `weekends` | Fires Saturday–Sunday (weekdays 1 and 7) |
| `selectedWeekdays` | Fires only on weekdays listed in `rule.weekdays` |
| `everyNDays` | Fires every N days counting from `anchorDate` (or `startDate`, or epoch) |
| `everyNWeeks` | Fires every N weeks on the weekdays listed in `rule.weekdays`; anchor determines the week alignment |
| `everyOtherDay` | Fires every 2nd day from anchor; shorthand for everyNDays(2) |
| `fourDaySplit` | Repeating 4-day exercise cycle: day 0 = Workout A, day 1 = Workout B, day 2 = Workout C, day 3 = Rest. Only fires on days 0/1/2 (not rest day). |

**How `occurs(on:calendar:)` works:**

1. Checks `startDate` — returns false if the date is before the start.
2. Checks `endDate` — returns false if the date is after the end.
3. Evaluates the frequency rule.
4. For interval-based rules (`everyNDays`, `everyNWeeks`, `everyOtherDay`, `fourDaySplit`): counts whole days from the resolved anchor. Anchor resolution order: `anchorDate` → `startDate` → Unix epoch (1970-01-01).
5. Does NOT check `occurrenceLimit`. That is handled by `RecurrenceEngine.matches()`.

**How `occurrenceLimit` works:**

`RecurrenceEngine.matches()` calls `occurs()` first. If that passes and an `occurrenceLimit` is set, it counts how many times the rule has fired from the origin up to (but not including) the candidate date. If that count >= limit, the rule does not fire on the candidate date. This means the limit is a total cap on lifetime occurrences.

---

### 4.5 ExerciseRoutine `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| name | String | |
| notes | String | |
| recurrenceRule | RecurrenceRule | Controls which days the routine appears |
| active | Bool | |
| createdAt | Date | |
| updatedAt | Date | |
| items | [ExerciseRoutineItem] | Cascade delete |

---

### 4.6 ExerciseRoutineItem `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| text | String | Name of the exercise |
| sets | Int? | Optional |
| reps | Int? | Optional |
| notes | String | |
| sortOrder | Int | Display order within the routine |
| routine | ExerciseRoutine? | Parent reference |

---

### 4.7 ScheduleTemplate `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| name | String | User-provided name |
| isEnabled | Bool | Disabled templates produce no blocks |
| assignedWeekdays | [Int] | Weekdays this template applies to (1=Sun...7=Sat) |
| customDateStart | Date? | Start of custom date range override |
| customDateEnd | Date? | End of custom date range override (inclusive) |
| blocks | [ScheduleBlock] | Codable array; first block MUST be Sleep |
| createdAt | Date | |
| updatedAt | Date | |

Rules:
- If `customDateStart` and `customDateEnd` are both set, the template applies to any date in that range, overriding weekday assignment.
- Only one template can apply to a given day. Priority: custom date range first, then weekday assignment.
- The Sleep block must always be the first block. It is locked (cannot be deleted).
- Block start times are computed from the previous block's end time. Reordering blocks recomputes all start/end times while preserving durations.

---

### 4.8 ScheduleBlock (plain struct)

Stored in `ScheduleTemplate.blocks` as a Codable array.

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string |
| title | String | Block label |
| startMinuteOfDay | Int | Minutes from midnight (0–1439) |
| endMinuteOfDay | Int | Minutes from midnight; may be <= start for overnight blocks |
| sortOrder | Int | Order within the template |

`durationMinutes` is computed:
- If `endMinuteOfDay > startMinuteOfDay`: `end - start`
- Otherwise (overnight): `(1440 - start) + end`

---

### 4.9 DailyPageScheduleBlock (plain struct)

A snapshot of a `ScheduleBlock` as it was when the daily page was generated. Stored in `DailyPage.scheduleBlocks`. Identical fields to `ScheduleBlock`. Past pages retain the schedule as it was at generation time — changes to the template do not retroactively update past pages.

---

### 4.10 DailyPage `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| date | Date | Normalized to start-of-day |
| createdAutomatically | Bool | Always true for generated pages |
| dayComplete | Bool | Recomputed by CompletionService after every task change |
| isPastLocked | Bool | True = historical snapshot; false = editable |
| scheduleBlocks | [DailyPageScheduleBlock] | Codable array snapshot from template |
| createdAt | Date | |
| updatedAt | Date | |
| tasks | [DailyPageTask] | Cascade delete |

Rules:
- One page per calendar date. The date field is unique by design; do not create duplicates.
- Past pages (`isPastLocked == true`) are never refreshed from templates. They are historical records.
- Today and future pages are refreshed from current templates every time they are loaded (unless manually locked).
- `dayComplete` is never set manually. Always recomputed by `CompletionService.recalculate()`.

---

### 4.11 DailyPageTask `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| sourceType | DailyTaskSourceType | `.recurring`, `.backlog`, `.manual`, or `.calendar` |
| sourceId | String? | ID of the source template or backlog item; nil for manual tasks |
| title | String | Task title at time of generation (may differ from current template title) |
| notes | String | |
| completed | Bool | |
| completedAt | Date? | Set when completed, cleared when unchecked |
| sortOrder | Int | Display order within the page |
| page | DailyPage? | Parent page reference |

Rules:
- Manual tasks (`sourceType == .manual`) stay forever on the page they were created on. They are never removed by template refreshes.
- Calendar tasks (`sourceType == .calendar`) are not removed by refresh. They come from EventKit and are managed separately.
- Recurring and backlog tasks are removed from a page if their source template/item no longer matches that date.

---

### 4.12 CalendarEventLocalState `@Model`

Stores per-event, per-day local state. The identity is the combination of `date + eventId`.

| Field | Type | Notes |
|---|---|---|
| date | Date | Start-of-day for the event's day |
| eventId | String | EventKit event identifier |
| completed | Bool | Human Program's completion mark (does not affect Apple Calendar) |
| hidden | Bool | If true, event is hidden from Today view |
| titleOverride | String? | User-provided override for the event title |
| notesOverride | String? | User-provided override for notes |
| sortOrder | Int | Manual sort position within the day |
| updatedAt | Date | |

Rules:
- Checking a calendar event as complete in Human Program does NOT modify the Apple Calendar event.
- Hiding an event does NOT delete it from Apple Calendar.
- Hidden events are excluded from the completion calculation.

---

### 4.13 NotificationReminder `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| title | String | Notification title |
| message | String | Notification body text |
| isEnabled | Bool | |
| recurrenceMode | NotificationRecurrenceMode | One of 5 modes |
| weekdays | [Int] | Used for selectedWeekdays and hourlyWindow |
| fireHour | Int | 0–23 |
| fireMinute | Int | 0–59 |
| intervalMinutes | Int | For everyNMinutes |
| windowStartMinute | Int | Start of time window (minutes from midnight) |
| windowEndMinute | Int | End of time window (minutes from midnight) |
| soundMode | NotificationSoundMode | `.defaultSound`, `.silent`, or `.chimeOnly` |
| imageFilename | String? | Filename in app's local storage for notification image |
| attachedTaskId | String? | Optional link to a task |
| createdAt | Date | |
| updatedAt | Date | |

Recurrence modes:
- `daily` — fires every day at fireHour:fireMinute
- `weekdays` — fires Mon–Fri at fireHour:fireMinute
- `selectedWeekdays` — fires on days in `weekdays` at fireHour:fireMinute
- `everyNMinutes` — fires every `intervalMinutes` minutes, optionally within windowStart/windowEnd on specified weekdays
- `hourlyWindow` — fires every hour on the hour between windowStart and windowEnd on specified weekdays

---

### 4.14 GameAccessState `@Model`

| Field | Type | Notes |
|---|---|---|
| date | Date | Normalized to start-of-day |
| isUnlocked | Bool | Whether the game was accessed on this day |
| unlockedAt | Date? | Timestamp of first access |
| reason | String | Internal log string (never shown to user) |

---

### 4.15 GameSaveMetadata `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| engine | String | Game engine identifier |
| saveSlot | String | Save slot name |
| lastPlayedAt | Date? | |
| localPath | String | Path to save file on device |
| schemaVersion | Int | For migration handling |

---

### 4.16 Routine `@Model`

A named checklist (not exercise-specific — a generic routine list).

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| title | String | |
| notes | String | |
| createdAt | Date | |
| updatedAt | Date | |
| items | [RoutineItem] | Cascade delete |

---

### 4.17 RoutineItem `@Model`

| Field | Type | Notes |
|---|---|---|
| id | String | UUID string, `@Attribute(.unique)` |
| text | String | |
| notes | String | |
| sortOrder | Int | |
| routine | Routine? | Parent reference |

---

## 5. Daily Page Generation

### Inputs

- All `RecurringTaskTemplate` records (active and inactive)
- All `BacklogItem` records (with any status, with or without dates)
- All `ScheduleTemplate` records with their `ScheduleBlock` arrays
- All calendar events for the date (when EventKit integration is active)
- All `ExerciseRoutine` records (for the exercise section — not for task generation)

### Output

A `GeneratedPage` containing:
- An ordered array of `GeneratedTask` items
- An ordered array of `DailyPageScheduleBlock` items

### Generation Rules

1. **Recurring tasks:** filter active templates where `RecurrenceEngine.matches(rule, on: date)` returns true. Sort alphabetically by title. Assign sortOrder starting at 0.

2. **Backlog tasks:** filter items where `status == .backlog` AND `assignedDate` is the same calendar day as the date being generated. Sort alphabetically by title. Continue sortOrder after recurring tasks.

3. **Manual tasks:** not added during generation. They are added by the user directly and never appear in the generator output.

4. **Calendar tasks:** provided by the EventKit layer. Added after generation with the `.calendar` source type.

5. **Schedule blocks:** determined by `DailyPageGenerator.activeScheduleBlocks()`. Priority: a template whose custom date range contains the date wins over weekday assignment. If multiple templates match, the first one (in insert order) wins. Disabled templates produce no blocks.

### One Page Per Date

Each calendar date has exactly one `DailyPage` record. The date field is normalized to start-of-day. Do not create duplicate pages for the same date.

### Past Pages (isPastLocked = true)

Past pages are historical snapshots. Once `isPastLocked` is true:
- The generator is never called on this page again.
- Template changes have no effect.
- The page's tasks and schedule blocks reflect what was on the page when it was last active.
- Users can manually double-tap the lock banner to unlock a past page for editing.

### Today and Future Pages

Today's page and any pre-generated future pages are refreshed from current templates every time they are loaded. The refresh algorithm:
- Keeps all manual and calendar tasks unchanged.
- Keeps recurring and backlog tasks that still match, preserving their completion state.
- Adds recurring and backlog tasks that now match but were not previously on the page.
- Removes recurring and backlog tasks whose source no longer matches.
- Refreshes schedule blocks from current templates.

### App Startup Sequence

Implemented in `AppStartup.run()`:

1. Clear overdue backlog assignments (any backlog item with `assignedDate < today` and `status == .backlog` has its `assignedDate` cleared).
2. Fetch all recurring templates, backlog items, and schedule templates.
3. `getOrCreate` today's page (creates it if missing; refreshes if existing).
4. `refreshTodayAndFuture` — refresh all non-past-locked pages with date >= today.
5. Fetch all pages and recalculate streak stats.

### On-Demand Generation When Browsing Dates

When the user navigates to a future date, `DailyPageRepository.getOrCreate()` is called for that date. If no page exists, one is generated and saved. If one exists and is not past-locked, it is refreshed. This means the user pre-generates pages by browsing ahead — no background jobs are needed.

---

## 6. Completion Logic

Implemented in `CompletionService`.

### What Makes a Day Complete

```
dayComplete = tasks.isNotEmpty && tasks.allSatisfy { $0.completed }
```

- The task list must be non-empty. An empty task list is never complete.
- Every task in the list must be checked.

### What Counts Toward Completion

- Recurring tasks (sourceType == .recurring)
- Backlog-derived tasks (sourceType == .backlog)
- Manual tasks (sourceType == .manual)
- Calendar tasks (sourceType == .calendar) — except hidden ones

### What Does NOT Count

- Exercise routines — they appear in the exercise section but are not `DailyPageTask` records.
- Schedule blocks — they are display-only; not tasks.
- Hidden calendar events — filtered out before the completion check.

### Completion State Changes

| Action | Result |
|---|---|
| Check all tasks | `dayComplete = true` |
| Uncheck any task | `dayComplete = false` |
| Add an unchecked task | `dayComplete = false` |
| Delete a task | Recompute (may become true if all remaining are checked) |
| Empty task list | `dayComplete = false` |

`CompletionService.recalculate(page:)` is called after every task mutation. The repository layer is responsible for calling it.

---

## 7. Backlog Logic

### BacklogItem Lifecycle

Items start as `status == .backlog`. They become `status == .done` when their corresponding task on a daily page is checked off. They go back to `.backlog` if unchecked (within the date-matching rules below).

### Assignment to Dates

- An item with `assignedDate == nil` is unscheduled. It appears in the backlog view but not on any daily page.
- An item with `assignedDate == someDate` and `status == .backlog` flows into the daily page for that date.

### Completion Sync Rules

When a backlog-derived `DailyPageTask` is **checked**:
- Find the source `BacklogItem` by `sourceId`.
- The page must be today or in the future.
- The item's `assignedDate` must match the page's date.
- If both conditions pass: mark item `status = .done`.

When a backlog-derived `DailyPageTask` is **unchecked**:
- Same conditions as above.
- Restore item to `status = .backlog`.

If either condition fails (page is in the past, or date doesn't match), the sync is skipped. The task toggle still happens on the page, but the source item is not touched.

### Overdue Rule

If `item.assignedDate < today` and `item.status == .backlog`: clear `assignedDate` on app startup. The item does NOT roll forward. It goes back into the unscheduled backlog. The user must reassign it manually.

### Project Buckets

Project buckets are lightweight labels. "Unorganized" is virtual (never stored, never deleted). Real buckets can be created, renamed, and deleted. Deleting a bucket sets `project = nil` on its items (or moves them to a destination bucket).

### Text Import

One line per task. Each line becomes a `BacklogItem` with that line as the title. Empty lines are skipped.

### CSV Import

Format: `title,date,project_bucket,note` (UTF-8). Preview before insert. Invalid rows are shown but skipped. Date format: ISO 8601 (YYYY-MM-DD).

---

## 8. Schedule Logic

### Templates and Blocks

A `ScheduleTemplate` is a named set of time blocks for a type of day. Examples: "Workday", "Weekend", "Deep Work Day".

The first block in every template is always Sleep. Sleep has an editable start time and end time. It cannot be deleted or reordered.

Additional blocks have a title and a duration. Their start time is computed automatically from the end time of the previous block. Changing any block's duration cascades forward to update subsequent start/end times.

### Reordering Blocks

When blocks are reordered (excluding Sleep which is fixed at position 0):
- Each block's duration is preserved.
- Start and end times are recomputed from top to bottom.
- Sleep's end time becomes the start of the first non-Sleep block.

### Assignment

A template applies to a day in one of two ways:

1. **Weekday assignment:** the template's `assignedWeekdays` array contains the day's weekday number.
2. **Custom date range:** the template has `customDateStart` and `customDateEnd` set, and the target date falls within that range (inclusive).

Custom date range overrides weekday assignment. If a date falls within a custom range, the weekday-assigned template for that day is ignored.

### Conflict Prevention

When saving or enabling a schedule template, the system checks whether any other enabled template already covers the same days. If a conflict exists, the save is blocked and the user is shown which template conflicts.

### How Blocks Appear on a Page

The `DailyPageGenerator.activeScheduleBlocks()` method:
1. Groups blocks by their parent template's metadata (enabled, weekdays, date range).
2. Finds the first enabled template whose custom date range contains the date (Phase 1).
3. Falls back to the first enabled weekday-assigned template (Phase 2).
4. Returns all blocks from the winning template, sorted by `sortOrder`.
5. Returns an empty array if no template matches.

---

## 9. Recurrence Engine

The `RecurrenceEngine` is a pure `Sendable` struct. It wraps `RecurrenceRule` with higher-level helpers.

### All 8 Frequency Types

| Frequency | When it fires |
|---|---|
| `everyDay` | Every day, no exceptions |
| `weekdays` | Monday through Friday (weekdays 2–6 in 1=Sun...7=Sat encoding) |
| `weekends` | Saturday and Sunday (weekdays 1 and 7) |
| `selectedWeekdays` | Only on the weekdays listed in `rule.weekdays` |
| `everyNDays` | Every N days from the anchor date. Day 0 = anchor, day N = first occurrence, etc. |
| `everyNWeeks` | Every N weeks on specified weekdays. The anchor determines which week cycle aligns. A date fires only if it is exactly a multiple of N*7 days from the anchor AND its weekday is in `rule.weekdays`. |
| `everyOtherDay` | Every 2nd day from anchor; equivalent to everyNDays(2). |
| `fourDaySplit` | 4-day repeating cycle starting at anchor. Day 0 = Workout A, Day 1 = Workout B, Day 2 = Workout C, Day 3 = Rest. Days 0/1/2 fire; day 3 does not. |

### Weekday Encoding

Always use iOS Calendar `.weekday` format: 1=Sunday, 2=Monday, 3=Tuesday, 4=Wednesday, 5=Thursday, 6=Friday, 7=Saturday. This is the convention used in `Calendar.component(.weekday, from:)`. Never use 0-based weekday encoding anywhere in this codebase.

### `occurs(on:calendar:)` Behavior

Direct method on `RecurrenceRule`. Checks date bounds, then evaluates frequency. Does NOT check `occurrenceLimit`. Safe to call in a loop without infinite recursion risk.

### `matches(_:on:calendar:)` in RecurrenceEngine

Calls `occurs()` first. If that passes and `occurrenceLimit` is set, counts prior occurrences from the rule's origin (startDate → anchorDate → epoch) up to (not including) the candidate date. If the count equals or exceeds the limit, returns false.

### `occurrenceLimit` Behavior

`occurrenceLimit` is a total lifetime cap. After N occurrences, the rule never fires again. Origin for counting: `startDate` if set, else `anchorDate` if set, else Unix epoch (1970-01-01). Every call that needs limit checking counts from this origin — this is intentionally simple but not optimized for large occurrence counts.

---

## 10. Game Bridge

The game bridge is the strict isolation layer between the planning container and the game container.

### EasterEggGateService

`shouldRevealGate(todayPage:today:calendar:)` returns `true` only when:
- `todayPage` is not nil
- `todayPage.dayComplete == true`
- `todayPage.date` matches today's date

This method is called when the user double-taps the developer name on the About screen.

If it returns `false`: trigger a subtle haptic (light impact). No text. No error message. No hint that anything exists.

If it returns `true`: present `SudokuGateView` full-screen.

### GameAccessService

`canAccessGame(todayPage:today:calendar:)` returns `true` only when:
- `todayPage` is not nil
- `todayPage.dayComplete == true`
- `todayPage.date` matches today's calendar date

`lockReason(todayPage:today:calendar:)` returns a human-readable reason. This is for internal logging only — never display the lock reason in the UI. The UI only knows "locked" or "unlocked".

### Sudoku Gate (4x4 Latin Square)

`SudokuGateView`:
- Full-screen black background. No navigation bar. No normal app chrome.
- Shows a 4x4 grid. Given cells are pre-filled and disabled (slightly brighter background). Empty cells cycle through 1-4 on tap.
- Solution is validated automatically after every cell change. When the puzzle matches the solution exactly: medium haptic, fade to black over 0.8 seconds, then present `GameContainerView`.
- X button in the top-left corner to dismiss.

The puzzle uses a fixed solution:
- Row 0: 2, 1, 4, 3
- Row 1: 4, 3, 2, 1
- Row 2: 1, 4, 3, 2
- Row 3: 3, 2, 1, 4

### Game Container

`GameContainerView` is currently a stub: black screen, white text "Game / Coming soon."

When a real game engine is integrated, it replaces this view's content. The bridge contract does not change.

### Game Saves

`GameSaveMetadata` records are in the game container and are independent from the daily gate. Solving or resetting the gate does not affect saved games. Game saves persist until the user deletes the app or explicitly deletes them.

### Entry Point

The entry point is the double-tap gesture on the developer name row in `AboutView`. There is no visible affordance. The row looks like any other text row.

---

## 11. App Lock and Security

### Overview

App lock is optional. Off by default. Once enabled, the app requires biometric or PIN authentication to view any content.

### Lock Options

- Face ID (or Touch ID on compatible devices) with PIN fallback
- PIN: 4 to 20 digits
- Lock timing: configurable — immediate, 30 seconds, 1 minute, 5 minutes, 15 minutes

### PIN Setup

The user chooses a PIN during security setup. There is no recovery phrase. If the PIN is forgotten, the only option is a full app reset. The reset is destructive and requires a two-step confirmation: first a standard confirmation step, then typing the word "reset" in a text field.

### What is Hidden While Locked

Everything: all planner content, backlog, calendar events, game access, stats. The lock screen shows only the unlock UI.

### Notifications While Locked

When the device is locked or the app is locked, notification text is generic: "Human Program reminder". When tapped, the user goes to the app's lock screen first, then normal navigation after authentication.

### On-Device Data Security

iOS encrypts the app's data directory when the device is locked. Human Program does not add a second layer of encryption on top of this. The app lock protects against unauthorized access while the device is unlocked.

### Backup Security

`.hprgm` backup files are NOT encrypted. This is intentional — simpler implementation, and the operating system protects on-device data. Users who share backup files should be aware they contain their planning data in plain JSON.

---

## 12. Import / Export

### .hprgm Format

`.hprgm` is a ZIP archive with the `.hprgm` file extension. It is not encrypted.

Internal file structure:

| File | Contents |
|---|---|
| `manifest.json` | Format version, app version, export date, schema version |
| `planning.json` | All planning data: pages, tasks, recurring templates, backlog items, project buckets, schedule templates, exercise routines |
| `preferences.json` | User settings and preferences |
| `calendar_local_state.json` | All `CalendarEventLocalState` records |
| `notifications.json` | All `NotificationReminder` records |

### Import Rules

1. Preview before writing: show the user what will be imported (item counts, date range).
2. Validate the manifest — reject files with unknown schema versions.
3. Import replaces existing data — it is not a merge. The user must confirm before data is overwritten.
4. If validation fails at any point, no data is written.

### CSV Backlog Export

Exports all active backlog items (status == .backlog). UTF-8 encoding. Date format: ISO 8601 (YYYY-MM-DD). Columns: `title,date,project_bucket,note`.

### CSV History Export

Exports completed day history. Presets: last 7 days, 30 days, 60 days, 90 days, or custom date range. Columns include: `date,day_complete,task_count,completed_count`.

### Backlog Text Import

Each non-empty line becomes one backlog item with that text as the title. No date, no project, no notes. Items land in "Unorganized".

### Backlog CSV Import

Format: `title,date,project_bucket,note`. Show a preview table before insert. Invalid rows are flagged but do not block import of valid rows.

---

## 13. Notifications

### Recurrence Modes

| Mode | Behavior |
|---|---|
| `daily` | One notification per day at fireHour:fireMinute |
| `weekdays` | Fires Mon–Fri at fireHour:fireMinute |
| `selectedWeekdays` | Fires on days in `weekdays` array at fireHour:fireMinute |
| `everyNMinutes` | Fires every `intervalMinutes` minutes, optionally within windowStart–windowEnd, optionally filtered to `weekdays` |
| `hourlyWindow` | Fires every hour on the hour from windowStart to windowEnd, on days in `weekdays` |

### iOS 64-Notification Limit

iOS only allows 64 pending local notifications per app. Human Program uses a rolling scheduler:
- On app open, compute the next ~50 fire times for each enabled reminder.
- Schedule those as `UNNotificationRequest` items.
- On each app open, reschedule to keep the queue full.
- This covers approximately 1–4 weeks depending on notification frequency.

### Missed Reminders

If a notification fires and the user doesn't see it (app is backgrounded, device was off), it is simply missed. Notifications are not rescheduled or accumulated.

### Notification Images

Image files are stored in the app's local storage (not in SwiftData). `NotificationReminder.imageFilename` references the filename. The image is attached to the `UNNotificationContent` as a `UNNotificationAttachment`.

### Permission Handling

Notification definitions are saved even when the user has denied notification permission. Scheduling is skipped if permission is denied. The app does not nag the user — it prompts once and respects the decision.

---

## 14. Calendar Integration

### Framework

EventKit. Calendar access is read by default. Write access is requested only for features that need to create or modify events (not planned for v1 of calendar integration).

### Permission

Permission is requested only when the user navigates to the Calendar settings screen or enables calendar integration. Not requested on first launch.

### Source Selection

The user selects which device calendars (from EventKit) feed into Human Program's Today view. This selection is stored in preferences.

### Events in Today View

Selected calendar events for the current date appear:
1. In the schedule timeline (by time).
2. As checkable tasks in the Required section (with `sourceType == .calendar`).

### Local State

`CalendarEventLocalState` stores Human Program's view of each event:
- Whether the user has checked it off in HP (does not modify Apple Calendar).
- Whether the user has hidden it.
- Optional title override (user can rename an event in HP without changing the real event).
- Optional notes override.
- Sort order within the day.

### Key Rules

- Checking a calendar event in HP does NOT modify the Apple Calendar event.
- Hiding a calendar event in HP does NOT delete it from Apple Calendar.
- `CalendarEventLocalState` records persist even if the underlying calendar event is deleted. Stale records are cleaned up periodically.

---

## 15. Today Screen

The Today screen is the main screen of the app. It shows the daily page for the currently viewed date.

### Layout (top to bottom)

**1. Date Header (`DateHeaderView`)**
- Shows: day name, day number, month, year.
- Previous/next arrows to move one day at a time.
- "Today" button to jump back to the current date.
- Calendar picker icon opens a `DatePickerSheet` (sheet, medium detent).

**2. Past-Lock Banner (conditional)**
- Shown when `isPastLocked == true`.
- Lock icon + text: "This day is locked. Double-tap to edit."
- Double-tap the banner to unlock the past page (calls `unlockPastPage`).

**3. Schedule Section**
- Section header: "SCHEDULE".
- Lists `DailyPageScheduleBlock` items sorted by `sortOrder`.
- Each row: start time — block title — end time.
- If no schedule template matches the day: "No schedule for this day" in tertiary text.

**4. Today's Tasks Section (labeled "REQUIRED")**
- Section header: "REQUIRED" with a `+` button (hidden when past-locked).
- Lists `DailyPageTask` items sorted by `sortOrder`.
- Each row: checkbox + task title. Tapping the row toggles completion.
- If no tasks: "No tasks for this day" in tertiary text.

**5. Completion Banner (conditional)**
- Shown when `vm.isComplete == true`.
- Green banner: "Congratulations, you are done for the day!"
- Appears below the task list.

**6. Exercise Section (labeled "EXERCISE")**
- Section header: "EXERCISE".
- Reference only — shows the exercise routine for the day.
- Not part of the completion checklist.
- Current state: shows "No exercise routine" (stub).

### Behavior Notes

- On view appear: loads the page via `vm.loadPage()`.
- Pull to refresh: re-runs `vm.loadPage()`.
- The `+` button opens an `AddTaskSheet` for adding a manual task.
- Date navigation calls `vm.jumpTo(date:)` which loads the page for the new date.
- All mutations go through `TodayViewModel` → `DailyPageRepository`.

---

## 16. Stats

### v1 Stats (implemented)

- **Current streak:** consecutive complete days ending today.
- **Longest streak:** longest consecutive run of complete days ever.
- **Total tracked days:** count of all DailyPage records with date <= today.
- **Total complete days:** count of those pages where `dayComplete == true`.

Calculated by `StreakCalculator.calculate(snapshots:today:)`. Future pages are excluded automatically (only dates <= today are counted).

### Future Stats (post-v1)

- Charts: daily completion over time (bar/line).
- Weekly and monthly summaries.
- Completion rate trends (e.g., 7-day rolling average).
- Task type breakdown (recurring vs. backlog vs. manual).

---

## 17. About and Easter Eggs

### About Screen

Displays:
- App name: "Human Program"
- Version string: "Version X.Y (build N)" from Bundle info
- A row labeled "Build" showing the build number. **Double-tap this row** to open the hidden document (UDHR text).
- A row labeled "Developer" showing "David Jurek". **Double-tap this row** to trigger the easter egg gate.
- A "Cat Corner" navigation link.
- A "Licenses" section noting no third-party libraries are bundled.

### Easter Egg Gesture

Double-tapping the developer name row:
- Calls `EasterEggGateService.shouldRevealGate()`.
- If today is complete: presents `SudokuGateView` full-screen.
- If today is not complete: light haptic, nothing else. No text, no animation, no hint.

### Hidden Document

Double-tapping the Build row opens `HiddenDocumentView` — a sheet containing the Universal Declaration of Human Rights (Articles 1–10 plus a note pointing to the full text at un.org).

### Cat Corner

A navigation destination showing a personal photo gallery. Photos are not yet provided. The current state is a placeholder: black background, paw print icon, "Photos coming soon".

---

## 18. Settings Menu Structure

Settings is a `NavigationStack` with grouped list rows.

```
Settings
├── Planning
│   ├── Recurring Tasks   → RecurringTaskEditorView (Phase 2)
│   ├── Schedule          → ScheduleEditorView (Phase 2)
│   └── Exercise          → ExerciseEditorView (Phase 2)
│
├── Notifications & Calendar
│   ├── Notifications     → NotificationListView + editor (Phase 4)
│   └── Calendar          → CalendarSourceSelectionView (Phase 3)
│
├── Data
│   ├── Import / Export   → ImportExportView (Phase 6)
│   └── Security          → AppLockSetupView (Phase 5)
│
└── About                 → AboutView (done)
```

All non-About destinations are currently `PlaceholderSettingsView` stubs.

---

## 19. UI Design Principles

### Overall Approach

Clean, minimal, custom. This is NOT a stock iOS app. Do not reach for List/Form when a custom VStack of rows will do. Do not use system disclosure indicators unless navigation is involved.

Design inspirations: Things 3 (task clarity, clean typography) and Notability (layout confidence, not generic). The goal is an app that feels made, not assembled.

### Color and Typography

All color and font values come from `AppColors` and `AppTypography` tokens. Never hardcode hex values or font sizes inline. Named colors in the asset catalog support automatic light/dark mode.

### Read Mode Default

The default state of most screens is read mode — controls are hidden. Edit mode reveals delete buttons, reorder handles, and inline editors. This keeps the day-to-day experience clean.

### No Swipe to Delete

Never. Anywhere. Not on tasks, not on backlog items, not on templates. Undo/redo is the safety net.

### No Confirmation Dialogs for Delete

Do not show "Are you sure?" alerts. Delete immediately. Undo/redo handles mistakes. This keeps the UI fast and uncluttered.

### Dark Mode

Dark mode is designed deliberately, not just color-inverted. The design should look good and feel intentional in both modes. Test in both.

### Custom Task Rows

Tasks use a `VStack` of custom `TaskRowView` components, not `List` with its default styling. This gives full control over appearance and avoids the disclosure indicator / separator issues that come with List.

---

## 20. Build Phases

### Phase 1 — Core Foundation (DONE)

- `RecurrenceRule` and `RecurrenceFrequency` with all 8 frequency types
- All SwiftData `@Model` classes and plain structs
- `RecurrenceEngine` with `matches()`, `nextOccurrence()`, `occurrences()`
- `DailyPageGenerator` with `generate()` and `refresh()`
- `CompletionService` with `isComplete()` and `recalculate()`
- `StreakCalculator` with full streak math
- `BacklogMaintenanceService` with overdue clearing and completion sync
- `DailyPageRepository` with full CRUD and refresh logic
- `BacklogRepository` with CRUD and project management
- `GameAccessService` and `EasterEggGateService`
- `AppStartup` sequence (clear overdue → generate today → refresh → recalculate)
- Today screen (date header, schedule, task list, completion banner, exercise stub)
- Stub screens for Backlog, Routines, Stats, Settings
- `SudokuGateView` (4x4 Latin square gate)
- `AboutView` with Cat Corner and hidden document
- `AppColors` and `AppTypography` design tokens
- Unit tests for all services and game bridge

### Phase 2 — Planning Editors (NEXT)

- Full backlog UI: list, create, edit, assign to date, project filter
- Recurring task editor: create, edit, set recurrence rules, activate/deactivate
- Schedule editor: create templates, add/reorder/delete blocks (keep Sleep locked)
- Exercise routine editor: create routines, add exercises with sets/reps

### Phase 3 — Calendar Integration

- EventKit permission flow
- Calendar source selection in Settings
- Events appear in Today timeline and as checkable tasks
- `CalendarEventLocalState` management (hide, complete, override)

### Phase 4 — Notifications

- Notification reminder list and editor
- All 5 recurrence modes
- Rolling scheduler (pre-compute ~50 fire times on app open)
- Image attachment support
- Permission handling

### Phase 5 — App Lock (Face ID + PIN)

- Optional app lock setup
- Face ID + PIN fallback
- Lock timing options
- Lock screen UI
- Forget PIN → reset flow with "reset" confirmation

### Phase 6 — Import / Export

- `.hprgm` export (ZIP with manifest + JSON files)
- `.hprgm` import with preview and validation
- CSV backlog export
- CSV history export with date range presets
- Backlog text import
- Backlog CSV import with preview

### Phase 7 — Stats Charts

- Charts screen with daily completion visualization
- Weekly/monthly summaries
- Completion rate trend

### Phase 8 — Full Calendar Screen

- Month/week/day/agenda views using EventKit data
- Deferred from v1; Today screen shows events only

### Phase 9 — Real Game Integration

- Replace `GameContainerView` stub with real game engine
- Connect `GameSaveMetadata` to game engine save system

### Phase 10 — Production Audit

- Owner provides Cat Corner photos
- Final review of all screens
- Performance profiling on real device
- Accessibility audit
- Privacy manifest review

---

## 21. Required Tests

All tests use an in-memory `ModelContainer` from `makeTestModelContainer()`. Services are tested without any SwiftData dependency.

### RecurrenceEngine Tests (`RecurrenceEngineTests.swift`)

- `everyDay`: fires on any given date
- `weekdays`: fires Mon–Fri, does not fire Sat/Sun
- `weekends`: fires Sat/Sun, does not fire Mon–Fri
- `selectedWeekdays`: fires only on specified days, not others
- `everyNDays`: fires on correct interval days, not on off-interval days
- `everyNWeeks`: fires on correct week/weekday combination, not on wrong weeks
- `everyOtherDay`: fires every 2nd day from anchor
- `fourDaySplit`: fires on days 0/1/2 of cycle, not day 3 (rest)
- `startDate` bound: does not fire before startDate
- `endDate` bound: does not fire after endDate
- `occurrenceLimit`: stops firing after N occurrences; fires correctly before limit
- Multiple frequencies combined with bounds

### DailyPageGenerator Tests (`DailyPageGeneratorTests.swift`)

- Matching weekday: recurring template fires on matching day
- Non-matching weekday: recurring template does not fire on wrong day
- Inactive template: not included even if rule matches
- Backlog item with matching date and status `.backlog`: included
- Backlog item with non-matching date: not included
- Backlog item with status `.done`: not included
- Combined input: recurring + backlog tasks in correct sort order
- Schedule template selection: custom date range overrides weekday
- Schedule template selection: disabled template produces no blocks
- `refresh()`: manual tasks survive; recurring task removed when template deactivated; new recurring task added when template added

### CompletionService Tests (`CoreServicesTests.swift`)

- All tasks complete, non-empty list: `isComplete == true`
- All tasks complete, single task: `isComplete == true`
- One task incomplete: `isComplete == false`
- Empty task list: `isComplete == false`
- `recalculate()` updates `page.dayComplete` correctly

### StreakCalculator Tests (`CoreServicesTests.swift`)

- No pages: all stats are 0
- Single complete day (today): currentStreak=1, longestStreak=1
- Single incomplete day (today): currentStreak=0
- Multi-day consecutive run: correct currentStreak value
- Gap in streak breaks the current streak
- Future pages excluded from all calculations
- `totalTrackedDays` counts all pages up to today
- `totalCompleteDays` counts only complete pages

### GameAccessService Tests (`GameBridgeTests.swift`)

- Nil page: `canAccessGame == false`; `lockReason` mentions "No daily page"
- Page exists, `dayComplete == false`: `canAccessGame == false`; `lockReason` mentions "not marked complete"
- Page exists, `dayComplete == true`, page date is today: `canAccessGame == true`
- Page exists, `dayComplete == true`, page date is yesterday: `canAccessGame == false`; `lockReason` mentions date mismatch
- `lockReason` returns "Access granted" when access is granted

### EasterEggGateService Tests (`GameBridgeTests.swift`)

- Nil page: `shouldRevealGate == false`
- Page incomplete: `shouldRevealGate == false`
- Page complete, date is today: `shouldRevealGate == true`
- Page complete, date is yesterday: `shouldRevealGate == false`

### Past Page Snapshot Tests (`PastPageSnapshotTests.swift`)

- Past page with `isPastLocked == true`: template changes do not add or remove tasks on refresh
- Past page: `dayComplete` is preserved, not recomputed from new task state
- Manual tasks survive page refresh on today/future pages
- Manual tasks are not affected by recurring template changes
- Today/future page refresh: task removed when template deactivated
- Today/future page refresh: task added when new matching template added
- Orphaned recurring task (no sourceId): removed during refresh

### BacklogMaintenanceService Tests (`CoreServicesTests.swift`)

- Item with `assignedDate < today` and `status == .backlog`: `assignedDate` cleared
- Item with `assignedDate == today`: not cleared
- Item with `assignedDate > today`: not cleared
- Item with `status == .done`: not touched even if overdue
- `syncCompletion()` on current/future page with matching date: marks item `.done`
- `syncCompletion()` on past page: returns nil, no change to item
- `syncCompletion()` when dates don't match: returns nil
- `syncUncompletion()` on current/future page: restores item to `.backlog`
- `syncUncompletion()` on past page: returns nil

---

*End of document.*
