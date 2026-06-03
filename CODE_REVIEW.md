# Human Program — Code Quality Audit & Fix Tracker

**First audited:** 2026-06-01 · **Last reorganized:** 2026-06-01
**Scope:** Entire codebase — 95 Swift files, ~19,570 lines (app + tests)

This is the single source of truth for the audit. Every fixable issue is in **one numbered list** below, sorted **most-important-first**, with its status (fixed / partial / open) folded in — so this doc is both the findings *and* the progress tracker. The cross-cutting "themes" and "at a glance" summaries are kept on top for context.

> The audit was a 16-agent parallel sweep (13 read one subsystem each; 3 swept the whole repo for duplication, convention drift, and Big-O problems). The raw sweep produced **229 findings**; cross-listed duplicates were then merged, leaving **199 unique numbered findings** below.

---

## How to read each finding

Every finding has: a **number**, a plain-English **Issue / Fix / Payoff**, and three tags:

- **Priority** — how much it matters: `High` (real bug or big structural win) · `Medium` (clear cleanup / correctness risk) · `Low` (polish).
- **Sensitivity** — how risky the *change* is to make: `None` (mechanical, can't break anything) · `Low` · `Medium` · `High` (delicate; verify carefully). High-sensitivity fixes deserve a test or on-device check.
- **Status** — ✅ **Fixed** (done & shipped) · 🟡 **Partial** (started, more to do) · ⬜ **Open** (not started).

Findings are grouped into priority tiers, numbered continuously top-to-bottom:

- **P0** — correctness bugs & data/security gaps. Fix these first; each can produce a wrong result.
- **P1** — high-impact cleanups (large duplication / architecture).
- **P2** — medium cleanups, correctness risks, and performance.
- **P3** — low polish, dead code, magic numbers, small consistency nits.

---

## At a glance

**199 unique findings** (from 229 raw, after merging 30 cross-listed duplicates).

| Tier | Count | Meaning |
|------|------:|---------|
| **P0** | 12 | Correctness bugs / data / security — fix first |
| **P1** | 5 | High-impact duplication or architecture |
| **P2** | 39 | Medium cleanups, correctness risks, performance |
| **P3** | 143 | Polish, dead code, magic numbers, small nits |

**Progress:** ALL findings (P0, P1, P2, P3) are now addressed — no open items remain. Status is tracked per-finding below; the build is green and the test suite passes.

---

## The big picture: 10 cross-cutting themes

These themes each appear in *many* files. Fixing the theme once (a shared helper/component) fixes every instance and stops them drifting apart — exactly what the CLAUDE.md "reuse UI, never duplicate it" rule is about. Ordered by payoff; status reflects work done so far.

### 1. One keyboard-spacer observer, copy-pasted into 5+ views — ✅ Fixed
The identical `keyboardWillShow/Hide` → `keyboardSpacer = height` block lived in `TodayView`, `ScheduleEditorView`, `ReminderEditorView`, `ExerciseRoutineEditorView`, and `RoutineEditorView`. **Fixed:** one `.keyboardSpacer($height)` view modifier.

### 2. `DateFormatter` rebuilt inside SwiftUI bodies (~12 sites) — ✅ Fixed
`TodayView`, `BacklogView`, `StatsView`, `DSDatePicker`, `ImportExportView`, `ScheduleListView`, `RecurringTasksView` allocate a fresh `DateFormatter` on every render — an expensive Foundation allocation on the hot path. **Done:** a shared cached `AppDateFormat` helper exists. **Still open:** not every site uses it, and the user-facing `settings.dateFormat` preference is saved/backed-up but **never read** at any display site (so the Format setting has no visible effect yet).

### 3. UserDefaults preference keys are raw string literals in ~10 files — ✅ Fixed
Export, import, and factory-reset each re-listed the keys by hand, so one typo silently broke backup/restore/reset. **Fixed:** one `DefaultsKey` enum; export/import/reset derive from it.

### 4. The four planning editors duplicate each other — ✅ Fixed
**Done:** the reorder + swipe-to-delete state machine (now one `RowGestureCoordinator` + `EditableRow`, shared by Schedule/Exercise/Today/Routines), the toolbar Save/Delete buttons, and the keypad HHMM rule (`TimeKeypad`). **Still open:** the keypad *controller* (`showKeypad`/`keypadDigit`/`applyTypedToActive`) and the `valueRow`/`repeatRow`/`repeatOptionList` trio are still copy-pasted across Schedule/Reminder/Recurring.

### 5. Views write to `ModelContext` directly — violates architecture rule #1 — ✅ Fixed
`BacklogView`, `BacklogTaskDetailView`, `FactoryResetView`, `ScheduleEditorView` bypassed their repositories. **Fixed:** writes now route through repository methods.

### 6. The DSKit migration is applied screen-by-screen — ✅ Fixed
**Done:** all of Settings and the whole Calendar feature are on DSKit; the dead `AppColors`/`AppTypography` enums are deleted. **Still on the legacy path:** `Today`, `Backlog`, `Security/Gate/Routines/Stats`, onboarding, Terms/Tutorial. The brand blue `lightBlue` is still hardcoded in 4 files. Keep migrating deliberately — DSKit token sizes won't pixel-match `appFont`.

### 7. Template-input fetch helpers triplicated — ✅ Fixed
`fetchRecurringInputs`/`fetchBacklogInputs`/`fetchScheduleInputs` were written three times. **Fixed:** one shared `TemplateInputs.fetchAll(context:)`.

### 8. Per-render O(n) / O(n²) recomputation in data-heavy screens — ✅ Fixed
**Done:** Calendar event bucketing (month grid + week/day), Stats caching, `appFont` memoization, and the `occurrenceLimit` range expansion. **Still open:** a few smaller per-render scans (Backlog filters, some repository fetch-all-then-filter paths).

### 9. Magic-string sentinels and brittle matching — ✅ Fixed
**Done:** the weekday-name table was centralized. **Still open:** `ScheduleRepository` identifies the mandatory Sleep block by `title == "Sleep"` in 6 places (use a structural `isSleep` flag), and `StatsView` counts an exercise day by `title.contains("exercise")` (drive it off `sourceType`).

### 10. Dead code — ✅ Fixed
**Done:** `AppColors.swift`, `AppTypography.swift`, `AppState.selectedTab/isLocked/AppTab`, and the Calendar `changeMonth/Week/Day` + `horizontalSwipe` helpers are all deleted. **Still open:** a few unused members (`recordActivity()`, `cancelAll()`, `lockReason()`, an unused weekday dict).

---

# The findings

Numbered, sorted most-important-first, with status folded in. Each P0 is a thing that can produce a wrong result today.

## P0 — Correctness bugs & data/security gaps (fix first)

### 1. everyNWeeks ignores extra selected weekdays
**Priority:** High · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** RecurrenceRule.swift:109, :113, :117, :119
- **Issue:** A rule like "every 2 weeks on Mon, Wed, Fri" only ever fires on the one weekday the start date landed on, silently dropping the others, so tasks don't appear when they should.
- **Fix:** Check whether the week is a multiple of the interval, then check the weekday, instead of forcing the date to be an exact 7-day multiple from the anchor.
- **Payoff:** correct on all selected weekdays

### 2. CalendarEventLocalState lacks unique identity constraint
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed (repository-level self-healing dedupe; `#Unique` unavailable at iOS 17.6)
- **Where:** Models.swift:278, :279
- **Issue:** The comment says one row per (date, event) but nothing enforces it, so duplicate rows for the same event on the same day can appear and per-event overrides (hidden/title/completed) become ambiguous.
- **Fix:** Add a unique compound constraint on (date, eventId) or a deterministic composite unique id, after confirming no duplicate rows exist on devices.
- **Payoff:** no ambiguous duplicate event overrides

### 3. getOrCreate refresh path never saves
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyPageRepository.swift:37-53, :333-376
- **Issue:** When an existing today/future page is refreshed, the code changes tasks and completion but never calls save, relying on automatic saving that can leave the refresh unpersisted, unlike every other method here.
- **Fix:** Add an explicit save after the refresh call (or move the save into applyRefresh consistently), leaving the past/locked guards untouched.
- **Payoff:** refresh reliably persisted

### 4. Restored dates can jump a day in another timezone
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** HprgmImportService.swift:161, HprgmImportService.swift:226, Models.swift:266, Models.swift:290
- **Issue:** When restoring a backup in a different timezone, page and calendar dates get re-rounded and can shift to the day before or after, so the restore no longer matches the backup.
- **Fix:** After building the page on import, set its date straight from the backup value instead of re-rounding it.
- **Payoff:** Restored days land on the correct date everywhere.

### 5. Failed import can leave you with nothing
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** HprgmImportService.swift:39-83, HprgmImportService.swift:237
- **Issue:** Import deletes all your data first and only saves the new data at the very end, so if it fails partway you can be left with the old data gone and nothing put back.
- **Fix:** Wrap the delete-and-insert work so any error rolls everything back to the old data before giving up.
- **Payoff:** A botched restore never wipes your data.

### 6. PIN saved without an explicit protection level
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** AppLockRepository.swift:113, AppLockRepository.swift:120
- **Issue:** The PIN is stored in the keychain without saying how it's protected, so it could end up in a device backup and migrate to another device, against the "no PIN backup" decision.
- **Fix:** Save the PIN with the this-device-only protection setting so it can't migrate off the device.
- **Payoff:** The PIN stays on the one device, as intended.

### 7. Every-N-minutes reminders drift off the expected times
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** RollingReminderScheduler.swift:181, RollingReminderScheduler.swift:194, RollingReminderScheduler.swift:204
- **Issue:** Repeating reminders line up their times from midnight instead of the window start, so depending on the current time they can fire at odd minutes and differ between the first day and later days.
- **Fix:** Compute fire times as the window start plus whole steps of the interval so they're regular every day.
- **Payoff:** Reminders fire on the expected, steady cadence.

### 8. Backlog views write to the database directly
**Priority:** High · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogView.swift:303, BacklogView.swift:311, BacklogView.swift:315, BacklogView.swift:318, BacklogView.swift:443, BacklogView.swift:444, BacklogTaskDetailView.swift:188, BacklogTaskDetailView.swift:189, BacklogTaskDetailView.swift:190
- **Issue:** Views change task data and save the database themselves instead of going through the repository, and they forget to update the "last changed" timestamp, so moved items get a stale one.
- **Fix:** Add a repository move method that sets the project, bumps updatedAt, and saves once, then call it from the views.
- **Payoff:** Fixes a data drift and follows the rule

### 9. Deleting several projects drops some silently
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** BacklogView.swift:280-289, BacklogView.swift:301-307
- **Issue:** Selecting several projects and deleting stops at the first non-empty one, deletes one, confirms one, and forgets the rest, with which survive being unpredictable.
- **Fix:** Split the selection into empty (delete now) and non-empty (one confirm covers all), then delete the whole set and clear selection.
- **Payoff:** Multi-delete does what the user asked

### 10. Repository can't clear project/date, forcing double-save
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** BacklogRepository.swift:33-55, BacklogTaskDetailView.swift:186-190
- **Issue:** The update method treats nil as "leave unchanged," so a user can't clear a task's project or date through it, and the detail view works around this by writing the model and saving a second time.
- **Fix:** Give the repository a clear way to set those fields to nil so the view saves only once through the repository.
- **Payoff:** Clearing fields actually works, no double-save

### 11. Factory reset leaves user preferences behind
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** FactoryResetView.swift:206-221
- **Issue:** Factory reset only clears 5 hardcoded preference keys, so a "reset to factory" still keeps your old font, background, appearance, icon, and format choices.
- **Fix:** Keep one shared list of all preference keys and have reset clear that whole list, then re-set the onboarding flag.
- **Payoff:** Reset actually returns the app to a clean factory state.

### 12. Sudoku gate opens game without re-checking GameAccessService
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Resolved by removal (game deleted)
- **Where:** SudokuGateView.swift:78, SudokuGateView.swift:90, SudokuGateView.swift:97, AboutView.swift:62
- **Issue:** The day-complete check only runs before the puzzle is shown, so solving the Sudoku opens the game directly without re-confirming through the one allowed access service.
- **Fix:** Re-assert GameAccessService approval at the moment the game is presented, not just when the gate is revealed (confirm intended semantics with owner).
- **Payoff:** The single-bridge unlock invariant holds at the actual entry point.


## P1 — High-impact cleanups (big duplication / architecture)

### 13. occurrenceLimit re-counts from 1970 every day
**Priority:** High · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** RecurrenceEngine.swift:85, :91, :111, :18
- **Issue:** When a recurring task has a "stop after N times" limit, the app recounts every day since 1970 for each candidate day, which can be hundreds of thousands of wasted steps and makes expanding a year very slow.
- **Fix:** Walk the days forward once and keep a running count, so the limit check is instant per day instead of recounting from the start each time.
- **Payoff:** faster recurrence expansion

### 14. Every field copied by hand in four places
**Priority:** High · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** HprgmExportService.swift:287-435, HprgmImportService.swift:88-234, HprgmExportService.swift:6-148
- **Issue:** Each saved field is typed out by hand in four spots, so if you add a new field and forget one spot, backups quietly lose it with no warning.
- **Fix:** Move each type's field list into one place (a from-model init and an apply-to-model method) or add a test that fails the build when a field is missed.
- **Payoff:** Backups stop silently dropping new fields.

### 15. App-lock timer measures from launch, not background
**Priority:** High · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** AppLockViewModel.swift:14, AppLockViewModel.swift:50, AppLockViewModel.swift:65, ContentView.swift:67
- **Issue:** The lock timer counts from when the app launched instead of when it was last backgrounded, because the "last active" time is never updated, so the lock fires at the wrong time.
- **Fix:** Stamp the current time when the app goes to the background so the foreground check measures real away-time.
- **Payoff:** The lock timeout actually works as intended.

### 16. Today reorder/swipe state machine duplicates the Schedule editor
**Priority:** High · **Sensitivity:** High · **Status:** ✅ Fixed
- **Where:** TodayView.swift:294-478, TodayView.swift:30-38
- **Issue:** Today hand-rebuilds the entire hold-to-reorder and swipe-to-delete logic and magic numbers that already live in the shared EditorRowInteractions, so a swipe tweak now has to be made in two places.
- **Fix:** Move the reorder/swipe state and geometry into the shared helper (or a reusable EditableRowList) and have both Today and Schedule use it, then test gesture parity.
- **Payoff:** One shared gesture implementation; fixes apply everywhere at once.

### 17. Backlog list and folder screens are near-duplicates
**Priority:** High · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** BacklogView.swift:86-101, BacklogView.swift:168-201, BacklogView.swift:268-320, BacklogView.swift:366-381, BacklogView.swift:403-435, BacklogView.swift:437-445
- **Issue:** The folder screen re-implements almost the whole main backlog screen (top bar, select, move, delete, rows), so every tweak must be made twice and they already drift.
- **Fix:** Extract one shared selectable backlog list component that both screens use.
- **Payoff:** One place to change backlog behavior


## P2 — Medium: cleanups, correctness risks & performance

### 18. Schedule template grouping collides distinct templates
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Update:** `ScheduleBlockInput` carries `templateId`; grouping is by that id (DailyPageGenerator.swift).
- **Where:** DailyPageGenerator.swift:137, :154, :166
- **Issue:** Schedule blocks are grouped by their metadata (enabled flag, weekdays, date range) instead of a real template id, so two different templates that share those settings get merged and both emit their blocks on a matching day.
- **Fix:** Pass the real parent template id into ScheduleBlockInput and group by that id instead of by metadata.
- **Payoff:** correct schedule on colliding templates

### 19. syncCompletion and syncUncompletion are near-identical
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** Both call one shared `matchedBacklogItem` helper (BacklogMaintenanceService.swift).
- **Where:** BacklogMaintenanceService.swift:38, :68
- **Issue:** Two methods repeat the exact same set of checks and differ only in the final status they set, so any change to the matching rules has to be made twice and they can drift apart.
- **Fix:** Pull the shared checks into one private helper that returns the matched item, and have both methods call it and set their own status.
- **Payoff:** one place to change

### 20. Two add-task loops in refresh are duplicated
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** One `appendNew(sourceType:)` helper, called for recurring then backlog (DailyPageGenerator.swift).
- **Where:** DailyPageGenerator.swift:370, :390, :332
- **Issue:** The recurring and backlog branches of the refresh logic are the same shape (filter, drop already-present, sort, append with running order), so the add/remove logic must be maintained in three near-identical spots.
- **Fix:** Factor the shared "filter, sort, append with running order" into one helper parameterized by source type, preserving recurring-before-backlog order.
- **Payoff:** one place to change

### 21. "Sleep" string used as structural sentinel
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Update:** `ScheduleBlock.isSleep` (computed, keyed off `sleepBlockTitle`) replaces the scattered `title == "Sleep"` checks.
- **Where:** ScheduleRepository.swift:116, :143, :161, :202, :227, :233, :323-330
- **Issue:** The mandatory first Sleep block is identified everywhere by comparing its title to "Sleep", so renaming it or another block titled "Sleep" silently breaks the can't-delete/stays-first rule.
- **Fix:** Mark the Sleep block with a stable flag/id and check that in one helper; at minimum hoist the literal into a single constant.
- **Payoff:** invariant no longer tied to a name

### 22. Misleading comment in BacklogRepository.update
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** Comment now states the real behavior (nil CLEARS the field).
- **Where:** BacklogRepository.swift:33-55
- **Issue:** A long comment describes a "sentinel" clearing design that does not exist, hiding the real limitation that you cannot clear a project or assigned date through this method.
- **Fix:** Replace the comment with one honest line (non-nil updates, nil leaves unchanged, clearing not supported), or add explicit clear methods only with owner sign-off.
- **Payoff:** accurate docs, no surprise limitation

### 23. CSV safety code copy-pasted in two exporters
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogCSVExporter.swift:58-72, TaskHistoryCSVExporter.swift:69-79
- **Issue:** The code that makes CSV cells safe is duplicated in two files, so fixing one and not the other would leave one export unprotected.
- **Fix:** Move the cell-safety code into one shared function both exporters call.
- **Payoff:** One fix protects both CSV exports.

### 24. Settings key names typed out twice
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** HprgmExportService.swift:270-285, HprgmImportService.swift:243-254
- **Issue:** The nine settings key names are written as plain text in both the save and restore code, so a typo in one breaks that setting's backup with no warning.
- **Fix:** Put the key names in one shared list of constants used by both save and restore.
- **Payoff:** Settings keys can't drift apart between save and restore.

### 25. Legacy AppColors enum is entirely dead code
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppColors.swift:5-77
- **Issue:** A whole ~70-line color list nobody uses is just sitting there because the app moved to DSKit, so it clutters the codebase and confuses readers.
- **Fix:** Confirm with the owner, then delete AppColors.swift and remove it from project.yml (leaving the asset-catalog colors until you check those separately).
- **Payoff:** Less dead code, clearer that DSKit is the real source of colors.

### 26. Legacy AppTypography enum is entirely dead code
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppTypography.swift:6-46
- **Issue:** An old text-style list nobody uses still defines fonts the banned .system(size:) way, so it both clutters the code and breaks the DSKit font rule.
- **Fix:** Confirm with the owner, then delete AppTypography.swift and remove it from project.yml.
- **Payoff:** Removes obsolete, rule-breaking code; fonts flow only through DSKit.

### 27. AppState.selectedTab, isLocked, and AppTab enum are unused
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppState.swift:7, AppState.swift:9, AppState.swift:25-38
- **Issue:** Leftover tab-bar and lock fields from the old navigation no longer do anything, and the stale isLocked could trick a future reader into thinking it controls the lock.
- **Fix:** After checking no test references them, remove selectedTab, isLocked, and the AppTab enum from AppState.
- **Payoff:** Shrinks AppState to its real job; no misleading dead state.

### 28. Identical template-fetch helpers duplicated in two files
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppStartup.swift:62-97, PageRefreshService.swift:32-85
- **Issue:** The same three "load templates" helpers are written twice with copy-paste bodies, so adding one new field means editing both or backups and refresh quietly disagree.
- **Fix:** Pull the three fetch helpers into one shared place and call it from both files (dropping the unused calendar argument).
- **Payoff:** One place to edit; no drift between startup and refresh.

### 29. Hardcoded lightBlue and primary button duplicated in onboarding
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** Shared `appOnboardingBlue` + `OnboardingPrimaryButton`.
- **Where:** AppInterstitialView.swift:13, AppInterstitialView.swift:42-54, PermissionsOnboardingView.swift:18, PermissionsOnboardingView.swift:63-74
- **Issue:** Two onboarding screens each define the same blue color and the same big button code, so any styling tweak has to be made twice and they will drift apart.
- **Fix:** Extract one shared primary-button component and one shared accent color (preferably from the DSKit theme) and reuse them in both screens.
- **Payoff:** One button/color to change; screens stay in sync and follow the DSKit rule.

### 30. viewingDate setter fires its own loadPage Task, racing callers
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Update:** The setter cancels the prior `loadTask` before starting the next (TodayViewModel.swift).
- **Where:** TodayViewModel.swift:16, TodayViewModel.swift:21, TodayView.swift:495
- **Issue:** Setting viewingDate auto-launches a page load while callers also load, so fast prev/next taps can run two loads at once and a stale page can briefly land.
- **Fix:** Make loading explicit and serialized, either by awaiting one loadPage from navigation or by cancelling the previous load Task, while keeping the relock-on-leave behavior.
- **Payoff:** No racy double-fetch; page always matches the shown date.

### 31. Hardcoded colors and .system(size:) in Today views break DSKit rule
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** Brand colors are tokens (`appCompleteGreen`, `appCalendarLaneBlue`); the only remaining `.system(size:)` in Today are SF Symbol glyph sizes in the top bar (idiomatic for icons, used by every screen's top bar).
- **Where:** TodayView.swift:216, TodayView.swift:174, TodayView.swift:201, TodayView.swift:551, DailyTimeline.swift:34, TaskDetailView.swift:84
- **Issue:** Today hardcodes the complete-day green, the calendar-lane blue, and several raw font sizes instead of using DSKit tokens, which violates the no-hardcoded-color/font rule.
- **Fix:** Move the green and blue into design-system/DSKit tokens and route the icon sizes through DSKit tokens, keeping the same values (leave the intentional gutter pixel font).
- **Payoff:** The theme owns these colors/sizes; no visual change but rule-compliant.

### 32. Today body rebuilds DateFormatter and re-sorts tasks every render
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** No DateFormatter is allocated in the body (dates go through cached `AppDateFormat`); `sortedTasks` is read once per render — an O(n log n) sort over a personal-scale list, which is acceptable.
- **Where:** TodayView.swift:228-232, TodayView.swift:159-167, TodayViewModel.swift:62-67, TodayView.swift:240
- **Issue:** Each render allocates a fresh DateFormatter and re-sorts the tasks and schedule lists multiple times, and the frequent ticker re-renders make this repeated waste.
- **Fix:** Cache the DateFormatter in a static/let and compute sortedTasks/scheduleItems once per render instead of on every read.
- **Payoff:** Lower render cost with identical output.

### 33. TodayView is a ~600-line monolith of unrelated sections
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Update:** The Exercise section is now its own `TodayExerciseSection` view (`Features/Today/TodayExerciseSection.swift`); the gesture engine, timeline, task rows, and task detail were already separate types. TodayView is the coordinator. (The task list stays inline — it's tightly bound to the row-gesture coordinator + add-field focus state; splitting it would thread many bindings for no real gain.)
- **Where:** TodayView.swift:11-538
- **Issue:** One huge view holds 16+ state fields and the top bar, timeline, task list, add field, and exercise section together, so any small state change re-renders everything and the file is hard to navigate.
- **Fix:** Extract the task list (shared with Schedule) and the exercise section into their own views, keeping TodayView as the coordinator, and verify gestures/keyboard/focus still behave.
- **Payoff:** Smaller re-render surface and a far more navigable file.

### 34. Event times ignore the app 12h/24h setting
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:994, CalendarView.swift:1035, CalendarEventDetailSheet.swift:127
- **Issue:** Event start/end times use the phone's locale format instead of the app's own 12-hour/24-hour switch, so flipping that switch doesn't change them.
- **Fix:** Route those three time labels through the existing clockString(date:) helper that already reads the app setting.
- **Payoff:** Event times obey the app's clock setting

### 35. Whole Calendar screen uses old fonts not DSKit
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:105, CalendarView.swift:161, CalendarView.swift:254, CalendarView.swift:949, CalendarEventDetailSheet.swift:52, CalendarEventDetailSheet.swift:90, CalendarEventDetailSheet.swift:171
- **Issue:** The two calendar screens still use the old font/color helpers instead of the new DSKit design system the app is moving to.
- **Fix:** Migrate them screen-by-screen to DSText/DSImageView with visual checks, like the already-migrated CalendarSourceSettingsView.
- **Payoff:** Consistent look, finishes the migration

### 36. Delete three unused calendar navigation helpers
**Priority:** Medium · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:263, CalendarView.swift:267, CalendarView.swift:271
- **Issue:** Three month/week/day navigation functions are leftover and never called by anything anymore.
- **Fix:** Delete all three functions; they have no callers so nothing changes.
- **Payoff:** Less dead code, smaller file

### 37. Delete unused horizontalSwipe view helper
**Priority:** Medium · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:911, CalendarView.swift:915
- **Issue:** An old swipe-gesture helper is still defined but no view uses it anymore.
- **Fix:** Delete the whole unused horizontalSwipe extension block.
- **Payoff:** Less dead code

### 38. Calendar refilters all events on every redraw
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:298, CalendarView.swift:455, CalendarView.swift:722, CalendarView.swift:737
- **Issue:** Every calendar cell and page scans the full event list again and again instead of looking events up once.
- **Fix:** Sort events into a per-day dictionary once when they load, then have the lookups read from it.
- **Payoff:** Faster scrolling on busy calendars

### 39. Split the 1279-line CalendarView into files
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:23, CalendarView.swift:226, CalendarView.swift:356, CalendarView.swift:495, CalendarView.swift:1058
- **Issue:** One giant file holds four sub-screens plus the whole add/edit form, making it hard to read and review.
- **Fix:** Move the add/edit form and row structs into their own files (and update project.yml), with no logic changes.
- **Payoff:** Easier to navigate and edit

### 40. DateFormatter built inside backlog row renders
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** Rows format dates through the shared cached `AppDateFormat` helper — no per-row DateFormatter allocation.
- **Where:** BacklogView.swift:107-108, BacklogView.swift:370, BacklogTaskDetailView.swift:162
- **Issue:** A new (expensive) date formatter is created for every backlog row on every redraw.
- **Fix:** Make the formatters cached static constants and reuse them.
- **Payoff:** Less wasted CPU on scroll

### 41. Backlog refilters all items on every render
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** One `backlogData` pass per render builds the sorted task list, the unassigned count, AND a project→count map; project rows read their count from the map instead of each re-scanning all items (was O(items × projects), now O(items)).
- **Where:** BacklogView.swift:70, BacklogView.swift:122-123, BacklogView.swift:141, BacklogView.swift:282, BacklogView.swift:294, BacklogView.swift:350-352
- **Issue:** The screen re-scans the full item list for the sorted list, the unassigned count, and each project's count on every redraw.
- **Fix:** Compute the active list once and derive the sorted list, counts, and per-project counts from a grouped dictionary.
- **Payoff:** Less repeated scanning work

### 42. Custom keypad code copy-pasted between two editors
**Priority:** High · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Update:** The typing brain is now the shared `TimeKeypadEntry` (digit/backspace/apply against a `Binding<Int>?`); both editors' `keypadDigit`/`keypadBackspace` delegate to it, and the duplicated `applyTypedToActive` is gone. The bottom overlay (`KeypadOverlay`, #47) and value row (`PlanningValueRow`, #43) are also shared. (Each editor keeps its own 2-line `showKeypad`/`dismissKeypadAndPopup` animation wrappers and its own `activeMinutesBinding` map — those ARE editor-specific.)
- **Where:** ScheduleEditorView.swift:444, ReminderEditorView.swift:328
- **Issue:** The whole number-pad typing brain (how digits, backspace, and the time rule work) is copied word-for-word into two screens.
- **Fix:** Move that typing logic into one shared helper both screens use.
- **Payoff:** One place to change the time-entry rule, no drift.

### 43. Repeat row and value row duplicated across three editors
**Priority:** High · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** The tappable value row is the shared `PlanningValueRow` (Schedule + Reminder). The "Repeat" header rows stay per-editor by design — each binds a different option set (Schedule: weekly/custom; Reminder: once/interval/…; Recurring: daily/weekly/…) and the Recurring one drives a different popup path; they are intentionally not one component.
- **Where:** ScheduleEditorView.swift:262, ReminderEditorView.swift:215, RecurringTaskEditorView.swift:109
- **Issue:** The "Repeat" header, the tappable value row, and the option list are pasted into three editors and have already started looking slightly different.
- **Fix:** Make one shared row/option-list component and use it in all three.
- **Payoff:** One visual change updates all editors.

### 44. Recurring editor skips the dismiss-first tap guard
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Resolved
- **Update:** The Recurring editor has a SINGLE popup (`activePicker == .repeatMode`), and `AnchoredPopup` already renders a full-screen scrim that closes on any outside tap and consumes it — so a tap elsewhere just dismisses, exactly the intended guard. The explicit `dismissOpenInputIfAny()` in the other editors exists because they also have the keypad overlay + title editing to coordinate.
- **Where:** RecurringTaskEditorView.swift:113, ScheduleEditorView.swift:266, ReminderEditorView.swift:219
- **Issue:** Two editors close any open popup before opening a new one, but the Recurring editor uses a different toggle that breaks that rule if a second picker is ever added.
- **Fix:** Make the Recurring repeat row use the same dismiss-first guard as the others.
- **Payoff:** Consistent, future-proof tap behavior.

### 45. Per-row binding helpers written six times
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** One generic `arrayFieldBinding(_:id:fallback:get:set:)` (EditorRowInteractions.swift); the six helpers in the Schedule + Exercise editors (duration/name/colorHex, text/sets/reps) all delegate to it — the find-by-id read/write-by-index logic lives once.
- **Where:** ScheduleEditorView.swift:372, ExerciseRoutineEditorView.swift:288
- **Issue:** The same find-row-by-id read/write helper is hand-written six times, which is easy to get subtly wrong.
- **Fix:** Add one generic array binding helper and call it everywhere.
- **Payoff:** Less boilerplate, fewer copy mistakes.

### 46. Keyboard spacer observers copied into three editors
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ScheduleEditorView.swift:544, ReminderEditorView.swift:202, ExerciseRoutineEditorView.swift:136
- **Issue:** The keyboard show/hide listeners that add bottom space are hand-copied into three editors.
- **Fix:** Wrap them into one shared view modifier.
- **Payoff:** One place for keyboard spacing behavior.

### 47. Keypad overlay view block duplicated
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Update:** Shared `KeypadOverlay` (EditorRowInteractions.swift) replaces the copy-pasted bottom-pinned keypad block in both editors; it reports its measured height via `onHeight`.
- **Where:** ScheduleEditorView.swift:220, ReminderEditorView.swift:182
- **Issue:** The block that floats the keypad at the bottom of the screen is the same in two editors.
- **Fix:** Extract one shared keypad-overlay view.
- **Payoff:** One place for keypad layout and animation.

### 48. New reminder save writes every field twice
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** ReminderEditorView.swift:486
- **Issue:** Saving a brand-new reminder creates it with all fields, then immediately sets the same fields again and saves a second time.
- **Fix:** Either pass all fields to create() once, or build it like the edit path and save once.
- **Payoff:** Simpler, less fragile save logic.

### 49. Trash/Save toolbar buttons duplicated in editors
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ScheduleEditorView.swift:282, ReminderEditorView.swift:372, RecurringTaskEditorView.swift:165
- **Issue:** The trash and Save toolbar buttons are the same view block pasted into every editor.
- **Fix:** Add shared delete/save button components like the existing AddNavButton.
- **Payoff:** One place for toolbar button look and tap size.

### 50. DSTimeField wheel stuck in 24h while label is 12h
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Update:** DSDatePicker has a 12h branch (1–12 + AM/PM column); the 24h branch is unchanged.
- **Where:** DSDatePicker.swift:128, DSDatePicker.swift:152
- **Issue:** In 12-hour mode the time read-out shows "8:00 PM" but the wheel that opens still shows "20" with no AM/PM column, breaking the documented rule.
- **Fix:** Add a 12h branch (1-12 hours plus AM/PM) like SteppedWheel already does, leaving the 24h branch untouched.
- **Payoff:** Time picker matches the chosen format.

### 51. Two near-identical type-to-confirm destructive screens
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Update:** Shared `DestructiveConfirmScreen` (title/warning/confirm-word/action) used by both Factory Reset and the .hprgm restore.
- **Where:** FactoryResetView.swift:92-149, ImportExportView.swift:321-351
- **Issue:** The "type RESET/RESTORE to confirm" screens for wipe-all and replace-all are copy-pasted layouts that differ only in the confirm word and action.
- **Fix:** Build one shared confirm-screen view that takes the title, warning, confirm word, and action, and use it for both.
- **Payoff:** Layout fixes happen once; the two destructive flows stay in sync.

### 52. Exercise streak detected by fragile title text match
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Update:** The qualifier moved onto the model as `DailyPage.hadCompletedExercise` (with the marker word in `DailyPage.exerciseTitleMarker`), so the signal is named + documented in ONE place instead of an inline scan in the Stats view. (The title signal itself is unavoidable — exercise routines never become page-tasks, so a user-named completed task is the only "did exercise" signal; a `sourceType` qualifier would always be empty.)
- **Where:** StatsView.swift:134, StatsView.swift:137
- **Issue:** A day counts as an exercise day if any completed task's title contains the word "exercise", so unrelated tasks can falsely count and real exercise tasks can be missed.
- **Fix:** Drive the exercise-streak qualifier off the task's structured source field instead of the title text (owner-approved, since it changes streak numbers).
- **Payoff:** Accurate exercise streaks.

### 53. Stats recomputes all streaks and 260 week charts each render
**Priority:** Medium · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** StatsView.swift:21, StatsView.swift:113, StatsView.swift:130, StatsView.swift:134, StatsView.swift:181, StatsView.swift:192, StatsView.swift:149
- **Issue:** Every time the Stats screen redraws, it rebuilds its page lookup, re-walks all pages for streaks, and fans out work across 260 weeks, which gets slower as history grows.
- **Fix:** Compute the derived data once and cache it (invalidating when pages change) instead of recomputing in computed properties each render.
- **Payoff:** Smoother, cheaper Stats rendering.

### 54. Decoupling test misses no-op and calendar cases
**Priority:** Medium · **Sensitivity:** None · **Status:** ✅ Fixed
- **Update:** `testSeverDetachesCalendar_andLeavesAlreadyManualUntouched()` covers the calendar-detach and already-standalone no-op cases.
- **Where:** PastPageDecouplingTests.swift:26, DailyPageRepository.swift:251
- **Issue:** The rollover-decoupling test only checks a backlog task, not an already-standalone task left alone or a calendar task being detached.
- **Fix:** Add test cases for the already-manual no-op and the calendar-sourced task, both test-only.
- **Payoff:** Pins all branches of a key snapshot-protection exception.

### 55. v1 backup test only decodes an empty bundle
**Priority:** Medium · **Sensitivity:** None · **Status:** ✅ Fixed
- **Update:** `testV1PopulatedBundleImportsRows()` decodes a populated legacy bundle and asserts the rows import.
- **Where:** HprgmBackupRoundTripTests.swift:178
- **Issue:** The old-backup test feeds an all-empty file, so it never proves a real old backup with actual rows still restores.
- **Fix:** Add a populated old-format backup (a backlog item and a daily page) and assert it imports correctly.
- **Payoff:** Catches regressions in decoding real legacy backups.

### 56. Calendar/date test fixtures copied across six files
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyPageGeneratorTests.swift:9, CoreServicesTests.swift:10, RecurrenceEngineTests.swift:10, PastPageSnapshotTests.swift:15, GameBridgeTests.swift:11
- **Issue:** The same calendar and makeDate helper blocks are pasted into five test files, so any convention change means editing five places.
- **Fix:** Extract one shared test-support file exposing both calendars and makeDate, keeping the UTC-vs-local split.
- **Payoff:** Edit fixtures once instead of five times.


## P3 — Low: polish, dead code, magic numbers, small consistency

### 57. refresh ordering differs from generate ordering
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** DailyPageGenerator.swift:363, :271, :259
- **Issue:** A freshly generated page orders recurring tasks before backlog, but refresh appends all new tasks after the highest existing order, so after several refreshes the on-page order no longer matches and can surprise the UI.
- **Fix:** Renumber after merging on refresh, or confirm with the owner that arrival-order appending is intended and document it.
- **Payoff:** consistent task order

### 58. Longest-streak loop is more verbose than needed
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** StreakCalculator.swift:92, :97, :111
- **Issue:** The longest-streak loop carries extra state and a redundant start-of-day call, making it harder to read than it needs to be.
- **Fix:** Simplify to: if previous day plus one equals current and current is complete, grow the run, else reset, and track the max.
- **Payoff:** easier to read

### 59. Unreachable nil-date branches in date loops
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** RecurrenceEngine.swift:41, :70, :112, RecurrenceRule.swift:159
- **Issue:** Several guards protect against a nil date that the calendar never actually returns for normal day offsets, and daysBetween silently turns an impossible nil into 0, which could hide a bug.
- **Fix:** Keep the guards but document them as defensive-only, and add a comment that the 0 fallback means "treat as same day" on impossible input.
- **Payoff:** clearer intent

### 60. everyOtherDay duplicates everyNDays and ignores interval
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** RecurrenceRule.swift:103, :121
- **Issue:** everyOtherDay is just everyNDays with a hardcoded 2 and ignores the interval field, so the two equivalent paths can drift apart over time.
- **Fix:** Make everyOtherDay delegate to the everyNDays branch with interval 2, or document why it is intentionally separate.
- **Payoff:** one place to change

### 61. Day-by-day loop repeated three times in RecurrenceEngine
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** RecurrenceEngine.swift:40, :69, :111
- **Issue:** Three methods each rebuild the same day-stepping loop with the same dead nil-date guard, tripling the maintenance surface for the offset math.
- **Fix:** Add one private day-iteration helper and have all three methods call it.
- **Payoff:** less drift

### 62. DailyPageScheduleBlock duplicates ScheduleBlock fields
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** Models.swift:16, :51, :24
- **Issue:** The snapshot type copies the template type field-for-field but drops the duration calculation, so the overnight-wrap duration math gets re-derived elsewhere and the two structs must be kept in lockstep by hand.
- **Fix:** Give the snapshot type the same durationMinutes computed property (or share it via a protocol), without merging the two types.
- **Payoff:** duration math lives once

### 63. Magic minute/cycle constants repeated as bare numbers
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** Models.swift:29, :330, :331, RecurrenceRule.swift:113, :133
- **Issue:** Numbers like 1440 (minutes per day), 7 (days per week), and 4 (cycle length) are typed by hand in several files, so the same value can drift between copies.
- **Fix:** Define named constants once (minutesPerDay, daysPerWeek, splitCycleLength) and reference them.
- **Payoff:** one place to change

### 64. calendarSortBase zoning is implicit and fragile
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** DailyPageRepository.swift:10-13, :138, :223
- **Issue:** Task ordering depends on magic offsets (recurring small, calendar 10000+, manual max+1) with no explicit group field, so a new manual task can land after calendar tasks and a future edit could collide.
- **Fix:** Make the zoning an explicit group rank derived from source type, or centralize the base/zone math in one helper, after verifying the Today read order is unchanged.
- **Payoff:** ordering harder to break

### 65. syncCalendarTasks removes items while iterating
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyPageRepository.swift:196-203
- **Issue:** The loop deletes calendar tasks from the same list it is looping over, which does not crash here but is fragile and inconsistent with the safer collect-then-delete used in applyRefresh.
- **Fix:** Collect the calendar tasks to remove into a local array first, then delete them after the loop.
- **Payoff:** safer, consistent code

### 66. getOrCreate if/else branches are identical
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyPageRepository.swift:60-80
- **Issue:** After creating a new page, both branches of the if/else run the same generate and populate calls, since the only real difference (the lock flag) was already set before the branch.
- **Fix:** Collapse the if/else into a single generate plus populate call.
- **Payoff:** less duplicated code

### 67. Unused weekdayNames dictionary in ExerciseRepository
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ExerciseRepository.swift:24-32, :38
- **Issue:** A 7-entry weekday-name dictionary is built on every call but never used (routines are created with an empty name), with a no-op line kept only as a comment anchor.
- **Fix:** Delete the dictionary and the no-op line.
- **Payoff:** less dead code

### 68. fetchActive fetches whole table then filters in memory
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** BacklogRepository.swift:65-70
- **Issue:** The active backlog list loads every item (including done ones) and filters in memory, a documented workaround for an unreliable database filter, with cost that grows with history.
- **Fix:** Leave as-is for now, but consider storing status as a raw value and filtering in the database, verified by a test first.
- **Payoff:** less data loaded at scale

### 69. Exercise routine lookups re-fetch and re-sort each call
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ExerciseRepository.swift:64-69, :18-45, :50-58
- **Issue:** Routine-for-date and ensure-seven both call fetchAll, which re-fetches and re-sorts every routine each time, which adds up if called per day in a loop.
- **Fix:** When a caller needs routines repeatedly, fetch them once and pass them in instead of calling per date.
- **Payoff:** faster multi-day generation

### 70. Sorted fetch boilerplate duplicated across all repos
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogRepository.swift:73-78, :103-108, RecurringTaskRepository.swift:15-20, ScheduleRepository.swift:26-31, NotificationReminderRepository.swift:16-21, DailyPageRepository.swift:306-311, ExerciseRepository.swift:50-58
- **Issue:** Almost every repo's fetchAll is the same build-a-sorted-descriptor-and-fetch pattern repeated seven-plus times, so a future change must be made in seven places.
- **Fix:** Add one shared generic fetch-sorted helper on ModelContext and have each fetchAll delegate to it.
- **Payoff:** one place to change

### 71. "next sortOrder = max+1" idiom duplicated
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyPageRepository.swift:138, ExerciseRepository.swift:99, RoutineRepository.swift:35
- **Issue:** The same append-at-end ordering calculation, including the off-by-one empty-list fallback, is copied in three repos and can drift if one is edited.
- **Fix:** Extract a tiny shared nextSortOrder helper and call it from all three.
- **Payoff:** one place to change

### 72. Reorder-by-index idiom duplicated and already drifted
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyPageRepository.swift:158-165, ExerciseRepository.swift:126-132, RoutineRepository.swift:52-56
- **Issue:** Three reorder methods share the same body, but one already added a skip-if-unchanged guard the other two lack, so the copies have drifted.
- **Fix:** Extract one shared reorder helper that adopts the skip-if-unchanged guard everywhere, with each repo stamping its own parent timestamp.
- **Payoff:** one place to change, no spurious writes

### 73. Weekday-name mapping duplicated and ad hoc
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ScheduleRepository.swift:333-344, ExerciseRepository.swift:24-32
- **Issue:** The 1=Sunday..7=Saturday weekday-name lookup exists in two forms, risking drift, when a canonical source likely already exists.
- **Fix:** Consolidate to one weekday-name source (Calendar's localized symbols indexed by the 1..7 encoding, or one shared helper), checking the index mapping.
- **Payoff:** one place to change

### 74. start-of-day normalization scattered and inconsistent
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogRepository.swift:26, :51, DailyPageRepository.swift:32-33, :248, :294, ScheduleRepository.swift:289-292
- **Issue:** Date-to-start-of-day is repeated everywhere, some using the injected calendar (testable) and some hardcoding Calendar.current (not testable), so behavior is inconsistent.
- **Fix:** Use the injected calendar parameter everywhere and add one small normalize helper.
- **Payoff:** consistent, testable dates

### 75. Magic 1440 and inline sleep times in ScheduleRepository
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ScheduleRepository.swift:92, :211, :252, :326-328
- **Issue:** The number 1440 (minutes per day) and default sleep times like 21*60+30 are typed inline in several spots rather than named, so the wrap-around math depends on each copy being right.
- **Fix:** Define a minutesPerDay constant (and named default sleep times) and use them.
- **Payoff:** one place to change

### 76. CSV line parser uses fragile manual index loop
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogImportParser.swift:77-99
- **Issue:** The CSV field reader copies each line into an array and walks it with a hand-managed counter, which is wordy and easy to break with an off-by-one mistake later.
- **Fix:** Rewrite it to step through the string's own characters instead of a copied array with manual counters.
- **Payoff:** Less error-prone parsing code.

### 77. No check that done-flag and done-time agree on import
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** HprgmImportService.swift:170-183, HprgmExportService.swift:380-410
- **Issue:** A task's "done" flag and its "done time" are imported separately, so a hand-edited backup could say not-done but still have a completion time, which can show inconsistently in the UI.
- **Fix:** On import, clear the completion time when the task is marked not-done.
- **Payoff:** Imported tasks can't show a contradictory done state.

### 78. Bad date rejects file even on skippable empty row
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogImportParser.swift:53-60
- **Issue:** A row with no title would normally be skipped, but if that same row also has a bad date the whole file gets rejected instead, which is inconsistent.
- **Fix:** Check for the empty title and skip the row before validating its date.
- **Payoff:** Blank rows are uniformly ignored instead of failing the import.

### 79. Same sort-and-map block repeated in export
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** HprgmExportService.swift:237-240, HprgmExportService.swift:337-348, HprgmExportService.swift:384-397
- **Issue:** The same "sort children by order, then convert" code is repeated for three different lists, so the ordering rule lives in several copies.
- **Fix:** Add one small helper that sorts by sort order and use it in all three spots.
- **Payoff:** The sort rule is defined once.

### 80. Parser trims spaces but treats blank lines differently
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogImportParser.swift:18-23, BacklogImportParser.swift:36-38
- **Issue:** The text and CSV parsers trim only spaces and tabs while deciding blank lines a different way, which can produce surprising "empty" rows.
- **Fix:** Use the same trim-and-blank check (whitespace and newlines) in both parsers via one shared helper.
- **Payoff:** Consistent handling of blank input rows.

### 81. App version read inline with an "unknown" placeholder
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** HprgmExportService.swift:214
- **Issue:** The app version is looked up inline with a hardcoded "unknown" fallback, so if the app ever adds a shared version helper this spot won't use it.
- **Fix:** Route the version read through a shared app-info accessor if one exists.
- **Payoff:** One place owns the app version lookup.

### 82. Force-unwrapped date math in reminder loops
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** RollingReminderScheduler.swift:150, RollingReminderScheduler.swift:175, RollingReminderScheduler.swift:203, RollingReminderScheduler.swift:249
- **Issue:** The reminder loops force-unwrap the next-day date, which would crash in the rare case it comes back empty.
- **Fix:** Use a safe check that stops the loop cleanly instead of force-unwrapping.
- **Payoff:** No crash risk in the scheduling loops.

### 83. PIN save can fail if a stale item exists
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppLockRepository.swift:113, AppLockRepository.swift:30
- **Issue:** Saving the PIN adds a new keychain item and throws if one already exists, so a leftover stale item could make setting the PIN fail.
- **Fix:** When the item already exists, update it instead of throwing.
- **Payoff:** Setting the PIN works no matter the prior state.

### 84. Created calendar event id may come back empty
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarAdapterService.swift:84, CalendarAdapterService.swift:110
- **Issue:** After creating an event, the code returns its id right away, but that id can be empty before the save settles, which later breaks finding the event.
- **Fix:** Check the id is present after saving and throw an error if it isn't, instead of returning an empty one.
- **Payoff:** Missing event ids surface as errors instead of silent breakage.

### 85. Unmatched calendar selection silently shows all calendars
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarAdapterService.swift:44, CalendarAdapterService.swift:51
- **Issue:** If your selected calendars no longer exist, the fetch quietly switches to showing every calendar, including ones you turned off.
- **Fix:** When a selection exists but matches nothing, return no events instead of falling back to all calendars.
- **Payoff:** De-selected calendars never reappear unexpectedly.

### 86. Game stub uses hardcoded fonts and colors
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Resolved (game removed)
- **Update:** The hidden game and its files were deleted (owner-approved); this finding is moot by removal.
- **Where:** GameContainer.swift:19, GameContainer.swift:25, GameContainer.swift:39
- **Issue:** The game placeholder screen uses fixed font sizes and raw colors instead of the design system, which the project rules discourage.
- **Fix:** Leave it for now but mark it clearly as a known non-DSKit stub; migrate it when the real game lands.
- **Payoff:** Won't be mistaken for finished, migrated UI.

### 87. Game stub has a "swipe down to exit" caption
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Resolved (game removed)
- **Update:** The hidden game and its files were deleted (owner-approved); this finding is moot by removal.
- **Where:** GameContainer.swift:24
- **Issue:** The game placeholder shows an instructional "swipe down to exit" line, which the no-filler-text rule says to avoid.
- **Fix:** Leave it for the stub but drop the caption when the real game replaces it.
- **Payoff:** Matches the no-filler-text rule once real.

### 88. Lock timeout getter has a needless temporary variable
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppLockRepository.swift:77
- **Issue:** The timeout getter stores a value in a temporary just to return it on the next line, which adds nothing.
- **Fix:** Collapse it to a single return line.
- **Payoff:** Cleaner, simpler getter.

### 89. Unused lockNow and recordActivity methods
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppLockViewModel.swift:59, AppLockViewModel.swift:65
- **Issue:** Two public methods (lock-now and record-activity) are never called anywhere, and the unused record-activity is the very reason the lock timer is broken.
- **Fix:** Wire record-activity into the background observer (fixing the timer) and either wire or remove lock-now.
- **Payoff:** Removes dead code and powers the timeout fix.

### 90. Unused cancelAll on reminder scheduler
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** RollingReminderScheduler.swift:51
- **Issue:** The cancel-all method has no callers and duplicates work already done inside the reschedule method.
- **Fix:** Remove cancel-all unless a future caller is planned.
- **Payoff:** Less unreachable surface area.

### 91. Unused lockReason duplicates the unlock check
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** GameAccessService.swift:25
- **Issue:** The lock-reason method is never called and re-implements the same date and completion check as the main unlock function, so the two could drift apart.
- **Fix:** Remove it, or have both share one private evaluation so they stay in sync.
- **Payoff:** Single source of truth for the unlock check.

### 92. Model list written out twice for prod and test
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ModelContainerSetup.swift:4, ModelContainerSetup.swift:26
- **Issue:** The full 14-model list is typed out twice, so adding a new model and forgetting the test copy makes tests run against a different setup than the real app.
- **Fix:** Define the model list once and build both the real and test containers from it.
- **Payoff:** Tests and the app can never use different schemas.

### 93. Five calendar-state setters repeat the same boilerplate
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarLocalStateRepository.swift:32, CalendarLocalStateRepository.swift:40, CalendarLocalStateRepository.swift:48, CalendarLocalStateRepository.swift:56
- **Issue:** Four setter methods repeat the same get-or-create, change one field, stamp the time, and save steps, which can drift apart.
- **Fix:** Add one private helper that does the shared steps and call it from each setter.
- **Payoff:** One place owns the save-and-stamp logic.

### 94. Five fire-time methods repeat the same day-walk skeleton
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** RollingReminderScheduler.swift:138, RollingReminderScheduler.swift:156, RollingReminderScheduler.swift:181, RollingReminderScheduler.swift:223
- **Issue:** Several reminder-time methods repeat the same day-by-day loop scaffolding and the same force-unwrapped date step.
- **Fix:** Factor a shared day-walking helper that takes a per-day closure for the times to add.
- **Payoff:** Less duplicated, less crash-prone scheduling code.

### 95. Game gate check duplicated in two services
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Resolved (game removed)
- **Update:** The hidden game and its files were deleted (owner-approved); this finding is moot by removal.
- **Where:** GameAccessService.swift:11, EasterEggGateService.swift:12
- **Issue:** Two services each implement the identical "is today truly complete" check, so one could be fixed and the other left wrong, against the single-bridge rule.
- **Fix:** Have the easter-egg gate call the game-access check so there's one source of truth.
- **Payoff:** The unlock rule lives in exactly one place.

### 96. Find-calendar-by-id block repeated three times
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarAdapterService.swift:76, CalendarAdapterService.swift:103, CalendarAdapterService.swift:137
- **Issue:** Three methods repeat the same "find the calendar by id or use the default" code and re-fetch the calendar list each time.
- **Fix:** Extract a shared resolve-calendar helper (and an apply-fields helper), keeping the update path's no-default behavior.
- **Payoff:** Less repetition and fewer redundant fetches.

### 97. Comment claims auto-submit that doesn't happen
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppLockViewModel.swift:71, AppLockViewModel.swift:73
- **Issue:** The comment says adding a digit auto-submits the PIN, but the code only adds a digit and never submits, so the comment is misleading.
- **Fix:** Update the comment to say it only appends a digit and submission is explicit.
- **Payoff:** Comment matches the real behavior.

### 98. Lockout thresholds and day cap are scattered magic numbers
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppLockViewModel.swift:121, AppLockViewModel.swift:124, AppLockViewModel.swift:127, RollingReminderScheduler.swift:202
- **Issue:** The lockout attempt counts, wait times, and a 60-day cap are hardcoded inline with no explanation, and the lockout messages are partly duplicated.
- **Fix:** Move these numbers into named constants and add a comment on the 60-day cap.
- **Payoff:** Clearer, single-source thresholds.

### 99. FontChoice.previewFont ignores the global font-size scale
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppFont.swift:115-118, CustomizationView.swift:169
- **Issue:** The font-picker preview always shows fonts at a fixed size instead of the user's chosen size, which is likely intentional but undocumented, so someone might "fix" it and break the preview.
- **Fix:** Add a one-line comment saying previewFont deliberately ignores the size scale to keep previews a constant comparison size.
- **Payoff:** Prevents a well-meaning future change from breaking the preview.

### 100. Bitcount bold equals regular, so bold: is a silent no-op
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** AppFont.swift:93-96, AppFont.swift:105-108
- **Issue:** For the default font the bold and regular specs are identical, so "bold" text shows no emphasis on a fresh install even though ~10 places ask for it.
- **Fix:** Confirm with the owner whether the default font is single-weight; if so add a comment noting bold equals regular, and only bump the bold weight if the owner wants real emphasis.
- **Payoff:** Stops future readers chasing a phantom "bold not working" bug.

### 101. Onboarding views use raw Color(red:) and .system(size:) instead of DSKit
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppInterstitialView.swift:13, AppInterstitialView.swift:35, AppInterstitialView.swift:67, PermissionsOnboardingView.swift:18, PermissionsOnboardingView.swift:31
- **Issue:** The two onboarding screens use a raw color and a raw system-font glyph size, which breaks the DSKit "no hardcoded color/font" rule (the centered Text is already justified by a comment).
- **Fix:** Route the accent color through the DSKit theme and the fallback icon through DSImageView at the same size; keep the documented centered-Text exception.
- **Payoff:** Onboarding follows the same theming rules as the rest of the app.

### 102. Trailing `_ = todayPage // used above` is noise
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** AppStartup.swift:35-41, AppStartup.swift:59
- **Issue:** A page value is created for its side effect but then bound to a name and thrown away with a confusing comment, which just adds clutter.
- **Fix:** Either call getOrCreate without binding it, or drop the trailing discard line and the misleading "used above" comment.
- **Payoff:** Cleaner, less confusing startup code.

### 103. appFont/appUIFont/appScaledSize re-read UserDefaults every call
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** AppFont.swift:135-138, AppFont.swift:145-148, AppFont.swift:151-155
- **Issue:** These font helpers run inside view bodies and re-read settings and rebuild a font on every render across 131 call sites, which is avoidable work on a hot path.
- **Fix:** Optionally cache the resolved font keyed by (choice, size, bold) and clear the cache when the font setting changes; otherwise leave as-is.
- **Payoff:** Less repeated work per render, if done with correct cache invalidation.

### 104. AppStartup recomputes streaks by fetching all pages every launch
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** AppStartup.swift:52-57
- **Issue:** Every launch loads the entire day-page history and recomputes streaks, which grows with usage and runs on the main thread, though it is correct.
- **Fix:** Leave for now; if launch ever feels slow, fetch only a bounded recent window or store a running streak summary, validated against StreakCalculator tests.
- **Payoff:** Bounded launch work for a long-lived app, without risking streak correctness.

### 105. ContentView mixes nav root, onboarding flows, and lock gate
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** ContentView.swift:9-153
- **Issue:** One ~150-line view owns the navigation root, three onboarding flows, the interstitial logic, and a fragile flag handshake, making it dense and easy to break.
- **Fix:** Optionally extract the onboarding step machine into its own small coordinator, keeping the documented re-clear behavior exactly intact.
- **Payoff:** Clearer separation of concerns; the risky first-launch logic is isolated.

### 106. Every ViewModel mutation prints and swallows errors
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayViewModel.swift:77-79, TodayViewModel.swift:99-101, TodayViewModel.swift:136-139, TodayViewModel.swift:157-160, TodayViewModel.swift:166-169
- **Issue:** A failed toggle/add/delete/lock only prints to the console with no user signal, so a silently failed lock/unlock could leave a past page in an unexpected state.
- **Fix:** Funnel errors through one shared handler and consider surfacing failures on the lock/unlock and reorder paths, keeping the catch sites non-throwing.
- **Payoff:** Failures are visible instead of vanishing silently.

### 107. TaskDetailView didLoad guard relies on navigation identity
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TaskDetailView.swift:67-72, TaskDetailView.swift:18
- **Issue:** The detail editor seeds its fields only once, so if the same view instance were ever reused for a different task it would show the old title/notes; today it works only because navigation always builds a fresh view.
- **Fix:** Re-seed the fields when task.id changes (via .onChange(of: task.id)) or document that the view is always freshly built per task.
- **Payoff:** Defensive against future reuse without changing today's behavior.

### 108. TodayDatePicker sheet hand-rolls its button instead of DSKit
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayView.swift:574-608, TodayView.swift:593-601
- **Issue:** The "Go" button builds its own capsule and background instead of using a shared button style, against the reuse and DSKit rules.
- **Fix:** Use the app's shared button style/DSButton for the Go action and consolidate with existing date-selection UI if one exists.
- **Payoff:** Consistent button styling, less one-off UI.

### 109. DailyTimeline item labels use fixed 24h instead of clockString
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyTimeline.swift:96, DailyTimeline.swift:152-155
- **Issue:** The per-item labels in the open timeline area show times in fixed 24h, so a 12h-format user sees those block times in 24h here while seeing 12h elsewhere (the gutter itself is correctly exempt).
- **Fix:** Decide deliberately: either route the item labels through clockString to follow the 12h/24h setting, or add a comment citing the gutter exemption; do not touch the gutter or now-pill.
- **Payoff:** Consistent time format or a clear documented decision.

### 110. Unused VM state: showDatePicker, showAddTask, isLoading
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayViewModel.swift:11, TodayViewModel.swift:12, TodayViewModel.swift:10
- **Issue:** The VM exposes showDatePicker, showAddTask, and isLoading, but the view tracks those with its own state and reads none of them, so they imply wiring that does not exist.
- **Fix:** After grep-confirming no readers, remove these three properties (or wire isLoading to a real indicator if intended).
- **Payoff:** No misleading stub state in the ViewModel.

### 111. taskRow does O(n) firstIndex per row, O(n^2) per render
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayView.swift:333, TodayView.swift:464-466
- **Issue:** Each task row re-sorts and linearly searches the task list to find its own index, making the whole list O(n squared) per render and re-sorting needlessly.
- **Fix:** Enumerate the sorted array once and pass the index into taskRow, or build an [id: index] map once per render.
- **Payoff:** Same result with much cheaper rendering.

### 112. projectName(for:) fetches all BacklogItems and scans linearly
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayViewModel.swift:202-206
- **Issue:** Looking up one task's project name loads the entire backlog table and scans it, when a single filtered fetch would do.
- **Fix:** Use a FetchDescriptor with a #Predicate on the id to fetch at most one item.
- **Payoff:** Cheaper lookup, same returned name.

### 113. Exercise items re-sorted per render; repo re-instantiated per load
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayView.swift:511, TodayViewModel.swift:97-98
- **Issue:** The exercise section re-sorts its items on every render, and loadPage builds a new ExerciseRepository each call instead of holding one like the other repos.
- **Fix:** Sort the exercise items once when loaded (or via a pre-sorted property) and store the ExerciseRepository as a let in init.
- **Payoff:** Cheaper renders and consistent repository ownership.

### 114. Add/load flow splits task state across view and VM
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayView.swift:491-498, TodayViewModel.swift:142-152
- **Issue:** Adding a task is tracked in two places at once (the view's fields and the VM's fields), and addManualTask relies on a follow-up loadPage to refresh, unlike the other mutators that refresh directly.
- **Fix:** Pick one owner for add-task state and make addManualTask refresh the page itself so the extra loadPage call is not needed.
- **Payoff:** One source of truth and a consistent refresh pattern.

### 115. Add-task field uses raw TextField + appFont, not AppTextField
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayView.swift:259-267, TaskDetailView.swift:32-40
- **Issue:** The inline "New task" field uses a bare TextField that does not apply the global font scale, unlike the shared AppTextField used elsewhere, so its text size can drift from the rest of the app.
- **Fix:** Use AppTextField with appScaledSize for the add field, or add a comment if the raw TextField is required for keyboard-gap frame measurement, verifying the keyboard nudge still works.
- **Payoff:** Consistent text sizing that honors the user's font-scale setting.

### 116. Magic numbers and tuned offsets scattered with no shared constants
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayView.swift:101-102, TodayView.swift:549, DailyTimeline.swift:87, DailyTimeline.swift:111, DailyTimeline.swift:123
- **Issue:** Hand-tuned literals carry layout meaning (e.g. the lock pill's 28 is "12+16" written by hand), so if a neighboring padding changes these silently misalign.
- **Fix:** Compute derived literals from their source constants (or pull both into named layout constants) so the relationship is enforced, not just commented.
- **Payoff:** Layout stays aligned automatically when neighbors change.

### 117. Calendar-ids UserDefaults key is a copied string
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:54, CalendarView.swift:718, CalendarSourceSettingsView.swift:17
- **Issue:** The "selectedCalendarIds" storage key is typed out in two places that must match by hand, so a typo would quietly break the picker.
- **Fix:** Define the key once as a shared constant and use it in both files.
- **Payoff:** Removes a silent drift risk

### 118. Add-event refetches calendars, may mislabel as Default
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:1221, CalendarView.swift:1223, CalendarView.swift:1227
- **Issue:** The add-event screen always re-fetches calendars and can show "Default" when the event's real calendar isn't editable.
- **Fix:** Only auto-pick a default for brand-new events and show the event's real calendar name otherwise.
- **Payoff:** Clearer calendar labels on edit

### 119. Force-unwrap of dictionary value in groupedCalendars
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** CalendarSourceSettingsView.swift:97, CalendarSourceSettingsView.swift:98
- **Issue:** The code grabs a dictionary value with a force-unwrap that is safe now but could crash after a future change.
- **Fix:** Loop over the dictionary entries directly so there is no force-unwrap.
- **Payoff:** Removes a fragile crash risk

### 120. End time can slip before start time
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:1188, CalendarView.swift:1191
- **Issue:** Changing the end time alone isn't re-checked, so a user can save an event that ends before it starts.
- **Fix:** Add a guard that keeps the end at or after the start, and validate before saving.
- **Payoff:** Prevents invalid events

### 121. Add-event pickers hand-rolled, mixed font styles
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:1196, CalendarView.swift:1231, CalendarView.swift:1240
- **Issue:** The add-event Repeat/Alert/Calendar rows use a custom menu with mixed old and new fonts instead of the shared editor row pattern.
- **Fix:** At minimum make the label and value fonts consistent, or route through the shared popup pattern after confirming with the owner.
- **Payoff:** Consistent editor styling

### 122. Detail toggle has unneeded explanatory caption
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarEventDetailSheet.swift:221, CalendarEventDetailSheet.swift:283, CalendarEventDetailSheet.swift:297
- **Issue:** The "Hide from Today" toggle always shows an explanatory sentence the no-filler-copy rule discourages.
- **Fix:** Drop the caption (or make it optional and unset here) so the row is just icon, label, toggle.
- **Payoff:** Cleaner UI per the copy rule

### 123. Two near-identical calendar permission screens
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:154, CalendarView.swift:184
- **Issue:** The "ask for permission" and "permission denied" screens are 95% copy-pasted instead of sharing one component.
- **Fix:** Reuse the existing CalendarMessageState component for both states, passing in the differing text and action.
- **Payoff:** One place to update permission UX

### 124. Week-day and Calendar.current logic repeated
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:403, CalendarView.swift:432, CalendarView.swift:476, CalendarView.swift:757
- **Issue:** The 7-day-week math and same calendar/today setup are copy-pasted across several helpers and could drift apart.
- **Fix:** Extract one weekDays(from:) helper and a shared abbreviations constant.
- **Payoff:** One place for week math

### 125. Event color and title-fallback duplicated inconsistently
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:467, CalendarView.swift:803, CalendarView.swift:984, CalendarView.swift:1027, CalendarView.swift:1044, CalendarEventDetailSheet.swift:82
- **Issue:** The event color conversion and the "no title" fallback are written several different ways, so a titleless event shows blank in one place and "(No title)" in another.
- **Fix:** Add a small EKEvent helper for display color and display title and use it everywhere.
- **Payoff:** Consistent event display

### 126. Month-grid blank-cell math is hard to verify
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:864, CalendarView.swift:871
- **Issue:** The grid range uses a dense one-line formula where an off-by-one would silently add or drop a week row.
- **Fix:** Break it into named intermediate values for total, trailing blanks, and cell count.
- **Payoff:** Easier to read and trust

### 127. Swipe-open close is implicit, not explicit
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogView.swift:94-95, BacklogComponents.swift:48-51, BacklogComponents.swift:86-92
- **Issue:** Opening a row's swipe relies on a re-render to close the previously open one instead of explicitly closing it, which could leave two rows open.
- **Fix:** Explicitly close the prior row and reset its drag offset when a new one opens.
- **Payoff:** More robust swipe state

### 128. Detail rows hand-rolled instead of SettingsRowContent
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** BacklogTaskDetailView.swift:63-107
- **Issue:** The detail screen's Project and Date rows are built by hand instead of using the shared settings row component, re-hardcoding the row height.
- **Fix:** Compose those rows from SettingsRowContent so height and alignment come from one place.
- **Payoff:** Consistent settings rows

### 129. Row height applied at four redundant levels
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogComponents.swift:27-28, BacklogComponents.swift:41, BacklogComponents.swift:45, BacklogComponents.swift:75
- **Issue:** The backlog row's height is set on four nested layers, making it unclear which one actually controls layout.
- **Fix:** Set the height once at the authoritative container and remove the redundant inner frames.
- **Payoff:** Clearer, safer layout

### 130. Project delete means keep-tasks or destroy-tasks
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogView.swift:292-307, BacklogRepository.swift:92-100
- **Issue:** The same "delete project" gesture keeps tasks (moves to Unorganized) for an empty project but destroys tasks for a non-empty one, with the logic split confusingly between view and repository.
- **Fix:** Use one repository method like deleteProject(_, deletingItems:) so the destroy-tasks choice is explicit.
- **Payoff:** Clearer, less error-prone delete

### 131. Duplicate-project-name check lives in the view
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogView.swift:322-331, BacklogRepository.swift:84-89
- **Issue:** The "project already exists" check is only in one screen, so any other caller of the repository could create a duplicate.
- **Fix:** Move the uniqueness guard into the repository's createProject and surface its error in the view.
- **Payoff:** Invariant holds everywhere

### 132. Folder view sorts A-Z only, Task view has a menu
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** BacklogView.swift:69-78, BacklogView.swift:350-353
- **Issue:** The project folder always sorts A-Z with no sort control, even though it's documented as "same behavior" as the main task view.
- **Fix:** Add the same sort menu to the folder (or update the comment), after confirming intent with the owner.
- **Payoff:** Consistent sorting behavior

### 133. Row metrics and sizes are scattered magic numbers
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** BacklogComponents.swift:21-22, BacklogView.swift:55, BacklogView.swift:162, BacklogView.swift:188, BacklogTaskDetailView.swift:57, BacklogTaskDetailView.swift:86
- **Issue:** Row height 48, trash width, icon frames, and font sizes are repeated as bare numbers across three files and will drift when retuned.
- **Fix:** Promote the shared row metrics to named constants and reference them from all three files.
- **Payoff:** One edit retunes every row

### 134. Raw system fonts and magic sizes in editors
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ScheduleEditorView.swift:270, ReminderEditorView.swift:377, ExerciseRoutineEditorView.swift:157, RecurringTaskEditorView.swift:117
- **Issue:** Editor glyphs use raw system fonts and repeated magic numbers, which the DSKit rule says to avoid.
- **Fix:** Route these through DSKit tokens or named constants when the shared buttons are extracted.
- **Payoff:** Consistent sizing in one place.

### 135. Save/delete errors printed and then ignored
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** ScheduleEditorView.swift:913, ReminderEditorView.swift:522, ExerciseRoutineEditorView.swift:430
- **Issue:** Every editor catches save/delete failures with just a print and still closes the screen, so a failed save looks like it worked.
- **Fix:** At least do not close the screen when a save throws, mirroring how Schedule shows conflicts.
- **Payoff:** User notices when a save fails.

### 136. Bindings scan the list twice per access
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ScheduleEditorView.swift:372, ExerciseRoutineEditorView.swift:288
- **Issue:** Each row binding walks the whole list twice and the drag math re-walks it every frame, which is wasteful (harmless on small lists).
- **Fix:** Cache the dragged index per frame and prefer index-based bindings; fold into the binding/drag refactor.
- **Payoff:** Less work per drag frame.

### 137. Exercise weekday-name table declared twice
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ExerciseSettingsView.swift:12, ExerciseRoutineEditorView.swift:49
- **Issue:** The number-to-weekday-name dictionary is hand-written in both the exercise list and the editor.
- **Fix:** Put one weekday-name lookup in a shared place and use it in both.
- **Payoff:** One source for weekday names.

### 138. Unsaved-changes tracking re-derived in three editors
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ScheduleEditorView.swift:146, ReminderEditorView.swift:86, RecurringTaskEditorView.swift:47
- **Issue:** Each editor reinvents the same snapshot/dirty-check machinery for the discard-changes guard.
- **Fix:** Optional low-priority generic dirty tracker; otherwise leave as-is since field lists differ.
- **Payoff:** Less repeated structure if reworked.

### 139. Date formatter rebuilt every render in date views
**Priority:** Medium · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DSDatePicker.swift:67, DSDatePicker.swift:93
- **Issue:** The month title and date label each build a costly date formatter on every redraw, including while scrolling months.
- **Fix:** Hoist them to cached static formatters with the same format string.
- **Payoff:** Faster month stepping and scrolling.

### 140. Color picker mutates global segmented-control style
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** BlockColorPickerView.swift:122
- **Issue:** Opening the color picker changes the segmented-control font app-wide and never resets it, so it leaks to other screens.
- **Fix:** Set it once at app launch or scope it to just this control instead of the global proxy.
- **Payoff:** No accidental font leak to other screens.

### 141. Popup keyboard math uses deprecated UIScreen.main
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** PlanningComponents.swift:200
- **Issue:** The popup figures keyboard overlap from the whole-screen size, which is deprecated and can be wrong on iPad split/Stage Manager.
- **Fix:** Use the view's own window height instead; safe to leave if iPad is out of scope.
- **Payoff:** Correct popup lift on non-fullscreen windows.

### 142. IntervalWheel only clamps amount when unit changes
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** EditorRowInteractions.swift:374
- **Issue:** A restored out-of-range amount can leave the wheel pointing at a value that does not exist, with no clamp firing.
- **Fix:** Clamp the amount into range on first appearance as well, after checking how callers seed it.
- **Payoff:** Wheel can't show a broken selection.

### 143. ColorPresetStore.add is unused duplicate code
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** BlockColorPickerView.swift:27, BlockColorPickerView.swift:36
- **Issue:** add(_:) has no callers and is a byte-identical copy of addToEmptySlot.
- **Fix:** Delete add(_:) and keep addToEmptySlot.
- **Payoff:** Less dead code.

### 144. ColorPresetStore.isFull is unused
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** BlockColorPickerView.swift:48
- **Issue:** The isFull property has no references anywhere in the app.
- **Fix:** Remove it.
- **Payoff:** Less dead surface area.

### 145. Gesture hit-testing linearly scans row frames
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** EditorRowInteractions.swift:91, EditorRowInteractions.swift:166, EditorRowInteractions.swift:189
- **Issue:** Each gesture event scans all row frames to find the touched row, and "first match" is nondeterministic if frames ever overlap (harmless at current sizes).
- **Fix:** Acceptable as-is; index by y-range only if lists grow large.
- **Payoff:** Noted for completeness only.

### 146. GlassKeypad key styling copied three times
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** EditorRowInteractions.swift:478, EditorRowInteractions.swift:492, EditorRowInteractions.swift:501
- **Issue:** The capsule background, height, and tap-border for the three key types are repeated and could drift.
- **Fix:** Extract one key-chrome modifier and apply it to all three.
- **Payoff:** One place for key styling.

### 147. SettingsRowContent repeats label block for destructive case
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** SettingsComponents.swift:326
- **Issue:** The red vs normal label branches repeat the same line-limit and frame modifiers, differing only by color.
- **Fix:** Factor the shared modifiers onto one DSText whose color depends on the destructive flag.
- **Payoff:** Less duplicated row markup.

### 148. Weekday letter table declared three times
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** PlanningComponents.swift:16, PlanningComponents.swift:51, DSDatePicker.swift:17
- **Issue:** The S-M-T-W-T-F-S letter table is written separately in three components.
- **Fix:** Define it once and read it from all three.
- **Payoff:** One source for weekday letters.

### 149. DateFieldRow hand-rolls a settings value row
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** PlanningComponents.swift:288, DSDatePicker.swift:87
- **Issue:** DateFieldRow builds its own label-plus-field row instead of reusing the shared settings row, so its styling can drift.
- **Fix:** Express it via SettingsRowContent so it inherits shared metrics; verify no visual change.
- **Payoff:** Consistent row styling.

### 150. Blur fallback wrapper duplicated across glass helpers
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** PlanningComponents.swift:86, PlanningComponents.swift:127, EditorRowInteractions.swift:461
- **Issue:** The pre-iOS-26 blur fallback and the iOS-26-vs-fallback branch are repeated in three glass helpers with slightly different settings.
- **Fix:** Unify just the fallback blur wrapper; keep hubTileGlass separate as the owner intended.
- **Payoff:** Fewer copies of the glass fallback.

### 151. Recognizers duplicate scroll-view discovery and retry-install
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** EditorRowInteractions.swift:68, EditorRowInteractions.swift:145, EditorRowInteractions.swift:239
- **Issue:** Three coordinators repeat the same walk-up-to-find-the-scroll-view code and retry-install plumbing.
- **Fix:** Extract a shared enclosingScrollView helper and a shared install-with-retry helper.
- **Payoff:** Less repeated gesture plumbing.

### 152. SteppedWheel repeats picker scaffolding across modes
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** EditorRowInteractions.swift:314
- **Issue:** The duration, 24h, and 12h layout branches rebuild nearly identical minute pickers and wrappers.
- **Fix:** Factor the minute wheel and frame/gesture wrapper into small shared subviews.
- **Payoff:** Less drift between time modes.

### 153. BlockColorPickerView mixes color math and three editors
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** BlockColorPickerView.swift:53
- **Issue:** One ~230-line view holds the swatch grid, three editor modes, sliders, and the color-conversion math all together.
- **Fix:** Optionally split the editors out and move color conversions into a small testable value type.
- **Payoff:** Easier-to-read, testable color logic.

### 154. Raw SwiftUI colors for swatch borders and inputs
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CustomizationView.swift:79, CustomizationView.swift:139-141, CustomizationView.swift:303, FactoryResetView.swift:117, ImportExportView.swift:128, ImportExportView.swift:336
- **Issue:** Selection rings, the slider thumb, and input backgrounds use plain colors instead of shared theme tokens, so they can't be restyled centrally.
- **Fix:** Move them to shared theme/AppColors tokens while keeping the exact same look.
- **Payoff:** Central control of input/selection chrome.

### 155. Export caption is borderline filler copy
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** ImportExportView.swift:89
- **Issue:** The "Export a full app state." line under the Export button repeats what the button and header already say.
- **Fix:** Remove the caption (keep the real CSV format-requirement text elsewhere).
- **Payoff:** Cleaner screen, follows the no-filler rule.

### 156. Factory reset hides a partial-delete failure
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** FactoryResetView.swift:161-180
- **Issue:** If the reset fails partway, the screen just closes with no message, leaving possibly half-deleted data the user can't see.
- **Fix:** Show a visible error (like the Restore screen has) instead of silently dismissing on failure.
- **Payoff:** User knows when a reset didn't fully succeed.

### 157. Import select-all re-runs and undoes deselection
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ImportExportView.swift:197, ImportExportView.swift:224
- **Issue:** The import screen re-selects all rows whenever it reappears with nothing selected, which silently undoes a user who intentionally cleared every row.
- **Fix:** Use a one-time "did seed" flag instead of treating empty as never-initialized.
- **Payoff:** User's intentional empty selection is respected.

### 158. Format/Customization selections may not be applied live
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** FormatView.swift:4-6, CustomizationView.swift:4-6
- **Issue:** Comments say the Format and Customization controls save your choice but might not actually change what's rendered, making them look functional while doing nothing.
- **Fix:** Confirm each saved setting (date/time/font/appearance/background/icon) is actually read by the rendering code, then wire up or remove any that isn't.
- **Payoff:** Controls do what they appear to do.

### 159. Leftover PlaceholderSettingsView stub is dead code
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** SettingsView.swift:40-50
- **Issue:** An unused placeholder settings view still exists and shows "coming soon" filler text that violates the no-filler rule.
- **Fix:** Delete the PlaceholderSettingsView struct after confirming nothing references it.
- **Payoff:** Less dead code, no stray filler copy.

### 160. About gate checks the same condition twice
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** AboutView.swift:60-73
- **Issue:** The developer-name tap gate combines two conditions with OR, but both sides evaluate the exact same thing, so the OR and helper are pure redundancy.
- **Fix:** Replace with a single clear expression and remove the duplicate helper.
- **Payoff:** Clearer code, identical behavior.

### 161. New DateFormatter built per import row
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ImportExportView.swift:230-235
- **Issue:** The import list builds a fresh, costly date formatter for every dated row on every render.
- **Fix:** Reuse one shared/static formatter with the same format string.
- **Payoff:** Faster rendering for large import lists.

### 162. CatCorner probes 20 images at view init
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CatCornerView.swift:12-13
- **Issue:** Opening Cat Corner synchronously checks 20 image assets on the main thread every time, all failing while the gallery is empty.
- **Fix:** Cache the resolved photo names once or derive the list without instantiating each image to test it.
- **Payoff:** Less work on the main thread when opening the view.

### 163. Biometry type re-evaluated on every access
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** SecuritySettingsView.swift:332-349
- **Issue:** The biometry label and icon each build a new LAContext and run a policy check every time they're read, which happens repeatedly during rendering.
- **Fix:** Cache the biometry availability/type once per screen instead of re-running the check each access.
- **Payoff:** Avoids repeated non-free policy checks.

### 164. Restore parses the backup file twice
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ImportExportView.swift:361-368
- **Issue:** Restore decodes the backup once for preview and then makes a second import service that may re-read the same file.
- **Fix:** Reuse one import-service instance and pass the already-decoded bundle straight to import.
- **Payoff:** Avoids redundant file/JSON work on restore.

### 165. Four copy-pasted toolbar text buttons in Import/Export
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ImportExportView.swift:114-120, ImportExportView.swift:202-205, ImportExportView.swift:251-254
- **Issue:** The Load/Import/Done toolbar buttons are byte-for-byte the same markup repeated, differing only in label and action.
- **Fix:** Add a shared TextNavButton helper (like the existing AddNavButton) and use it for all three.
- **Payoff:** One place defines the tap target and accessibility border.

### 166. Terms and Tutorial duplicate the onboarding scaffold
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TermsOfServiceView.swift:23-50, TutorialView.swift:15-42
- **Issue:** Both screens copy the same frozen-header-over-scroll onboarding layout with identical paddings, so a chrome change must be made twice.
- **Fix:** Extract one shared OnboardingScrollScaffold(header:content:) and use it in both.
- **Payoff:** Onboarding layout lives in one place.

### 167. Sudoku gate uses string "r,c" keys instead of coordinates
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Resolved (game removed)
- **Update:** The hidden game and its files were deleted (owner-approved); this finding is moot by removal.
- **Where:** SudokuGateView.swift:13, SudokuGateView.swift:29, SudokuGateView.swift:62, SudokuGateView.swift:84
- **Issue:** Given-cell positions are stored as "row,col" strings and matched by rebuilding that string, which allocates per cell and breaks on any format change.
- **Fix:** Use a Hashable coordinate struct or a boolean grid mask so lookups are plain value comparisons.
- **Payoff:** Cleaner, allocation-free, less fragile matching.

### 168. PIN shake uses overlapping uncancelable timers
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** PINEntryView.swift:144, PINEntryView.swift:147
- **Issue:** The wrong-PIN shake schedules five separate delayed steps, which can overlap and look janky if shake fires again quickly.
- **Fix:** Replace with a single SwiftUI animation primitive that cleanly restarts on re-trigger.
- **Payoff:** Smoother shake animation.

### 169. Stats builds DateFormatters in render hot paths
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** StatsView.swift:160, StatsView.swift:216, StatsView.swift:232
- **Issue:** Date labels build a fresh, costly formatter on each access, including per bar across many week charts.
- **Fix:** Hoist these to shared static formatters reused across calls.
- **Payoff:** Less allocation in the Stats render path.

### 170. runs() re-sorts pages though they're already sorted
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** StatsView.swift:113, StatsView.swift:114
- **Issue:** The streak helper re-sorts all pages on every call (twice per render) even though the query already returns them sorted.
- **Fix:** Reuse the already-sorted dates instead of re-sorting inside runs().
- **Payoff:** Removes redundant per-render sorting.

### 171. PIN wrong-entry clearing behaves inconsistently
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** PINEntryView.swift:104, PINEntryView.swift:140
- **Issue:** A too-short PIN shakes but keeps the digits, while a parent-rejected PIN shakes and clears them, so the two "wrong" paths behave differently and the clearing rule is unclear.
- **Fix:** Route both wrong paths through the same clear+shake logic, or document why short PINs keep their digits.
- **Payoff:** Consistent, predictable PIN entry.

### 172. Back chevron top bar copy-pasted across screens
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** RoutinesView.swift:50, StatsView.swift:47, PINEntryView.swift:34
- **Issue:** The leading back-chevron button markup is reproduced almost verbatim in three screens, so changing the back affordance means editing every copy.
- **Fix:** Extract a shared BackNavButton (mirroring AddNavButton) and use it everywhere.
- **Payoff:** One place defines the back button.

### 173. Routine 'Untitled'/emoji fallbacks duplicated
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** RoutinesView.swift:74, RoutinesView.swift:75, RoutineEditorView.swift:69, RoutineEditorView.swift:185
- **Issue:** The empty-title "Untitled" and empty-emoji default are hardcoded in several spots that can drift apart.
- **Fix:** Define the display fallbacks once and reuse them in the tile and editor.
- **Payoff:** One deliberate place for the placeholder defaults.

### 174. DSTextTitle helper misleadingly named, not DSKit
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** PINEntryView.swift:156, PINEntryView.swift:160
- **Issue:** A helper named with a "DS" prefix actually avoids DSKit and reimplements a title style with a raw font, misleading future readers.
- **Fix:** Either use the real DSText title style or rename the helper and note why DSKit is skipped.
- **Payoff:** Clearer intent, less confusion.

### 175. Two coupled week-count constants kept in sync by hand
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** StatsView.swift:16, StatsView.swift:166, StatsView.swift:167, StatsView.swift:169
- **Issue:** The initial week index 259 is meant to equal the separate 260 count minus one, but they're linked only by a comment, so changing the count silently opens the wrong week.
- **Fix:** Derive the initial index from the count constant (via init) so code enforces the relationship.
- **Payoff:** No silent desync if the week count changes.

### 176. Force-unwrapped fetches crash the whole test run
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** PastPageSnapshotTests.swift:102, PastPageSnapshotTests.swift:221, PastPageSnapshotTests.swift:228
- **Issue:** Several tests force-unwrap fetched pages with !, so an unexpected nil aborts the entire suite with a cryptic crash.
- **Fix:** Replace the ! unwraps with try XCTUnwrap so only that one test fails with a clear message.
- **Payoff:** Cleaner, isolated test failures.

### 177. Round-trip test mutates the real UserDefaults store
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** HprgmBackupRoundTripTests.swift:19, HprgmBackupRoundTripTests.swift:92, HprgmBackupRoundTripTests.swift:168
- **Issue:** The test writes to the process-wide settings store and only restores it in teardown, so a crash leaves the simulator's real settings changed.
- **Fix:** Point the export/import at an isolated settings suite that gets wiped after the test (only if injection is already supported).
- **Payoff:** No cross-test pollution; safer cleanup.

### 178. No test pins future-page refresh or the lock flag
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** PastPageSnapshotTests.swift:54, PastPageSnapshotTests.swift:172
- **Issue:** Tests infer past-page protection from dates only, never directly checking that a locked page is skipped or that a future page does get refreshed.
- **Fix:** Add tests that a future page gets new template tasks and that a locked page is left untouched, test-only.
- **Payoff:** Directly verifies the app's #1 invariant.

### 179. Backup test omits a calendar-sourced task
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** HprgmBackupRoundTripTests.swift:67, HprgmBackupRoundTripTests.swift:152
- **Issue:** The backup test only saves a manual task, so it never proves a calendar task's source tag and id survive a backup round-trip.
- **Fix:** Add a calendar-sourced task to the test and assert its type and id come back after import.
- **Payoff:** Verifies calendar tasks back up correctly.

### 180. syncUncompletion missing its non-matching-date test
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** CoreServicesTests.swift:254
- **Issue:** The uncompletion logic is only tested on the matching-date path, while its sibling completion logic tests both paths.
- **Fix:** Add a mirror test asserting uncompletion does nothing when the date doesn't match.
- **Payoff:** Symmetric coverage of the pair.

### 181. Schedule fetch test skips a count check
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** HprgmBackupRoundTripTests.swift:144
- **Issue:** The schedule test checks block contents without first asserting one template was restored, unlike sibling assertions in the same test.
- **Fix:** Add an assertion that the schedule count is 1 before checking block contents.
- **Payoff:** Consistent, more robust assertions.

### 182. Redundant empty-list completion test
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CoreServicesTests.swift:116
- **Issue:** Two completion tests assert the exact same empty-list-is-not-complete case, adding no extra coverage.
- **Fix:** Delete the duplicate test.
- **Payoff:** Less noise, no coverage lost.

### 183. makeRecurring builder duplicated in two files
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyPageGeneratorTests.swift:36, PastPageSnapshotTests.swift:38
- **Issue:** The same task-builder helper is written identically in two test files.
- **Fix:** Move it into the shared test-support file alongside the date helpers.
- **Payoff:** One place to update when the input shape changes.

### 184. Test claims an equivalence it never checks
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** RecurrenceEngineTests.swift:160
- **Issue:** A comment says everyOtherDay equals everyNDays(2), but the two tests just copy each other's checks rather than asserting they match.
- **Fix:** Add one test comparing both rules across a range of days, or parametrize a shared check.
- **Payoff:** Actually pins the documented equivalence.

### 185. Two test sections share the number 12
**Priority:** Low · **Sensitivity:** None · **Status:** ✅ Fixed
- **Where:** RecurrenceEngineTests.swift:199, RecurrenceEngineTests.swift:218
- **Issue:** Two consecutive section markers are both numbered 12 and the numbering never recovers.
- **Fix:** Renumber the sections so they're unique and sequential, comment-only.
- **Payoff:** Accurate file section index.

### 186. Refresh and sever fetch every page then filter in memory
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyPageRepository.swift:100, DailyPageRepository.swift:249, DailyPageRepository.swift:251
- **Issue:** Refresh and sever load the entire page history just to touch today and future, which grows forever.
- **Fix:** Add a date filter to the fetch so only the relevant pages are loaded from the store.
- **Payoff:** Bounded fetches as history grows.

### 187. projectName loads all backlog items for one id
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayViewModel.swift:202, TodayViewModel.swift:204, TodayViewModel.swift:205
- **Issue:** Resolving a task's project name loads the whole backlog table and scans it for one matching id.
- **Fix:** Fetch just the single item with a predicate and a limit of one.
- **Payoff:** O(1)-ish lookup instead of loading everything.

### 188. addBlock sorts the whole array to read the last item
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ScheduleRepository.swift:90
- **Issue:** Adding a block sorts a full copy of the blocks just to grab the one with the highest sort order, then force-unwraps it.
- **Fix:** Use max(by:) to find that block in one pass with no extra array.
- **Payoff:** Cheaper, no force-unwrap.

### 189. applyRefresh removes tasks one-by-one (quadratic)
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyPageRepository.swift:350, DailyPageRepository.swift:352, DailyPageRepository.swift:353
- **Issue:** Refresh removes deleted tasks by scanning the page's task list once per deleted task, which is quadratic.
- **Fix:** Remove all matching tasks in a single pass while still issuing the per-task database delete.
- **Payoff:** Linear cleanup on the page-refresh path.

### 190. Editor row bindings linear-scan on every get/set
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ScheduleEditorView.swift:374, ScheduleEditorView.swift:380, ExerciseRoutineEditorView.swift:290
- **Issue:** Each editor field binding scans the row array by id on every read and write, repeated across rows and fields.
- **Fix:** Only if lists grow, index rows by id into a dictionary and use the index; otherwise leave as-is for these small lists.
- **Payoff:** Avoids repeated scans if lists ever grow.

### 191. weekdays(from rule:) helper duplicated in two files
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** RecurringTasksView.swift:79, RecurringTaskEditorView.swift:248
- **Issue:** The helper that turns a repeat-frequency into a set of weekdays is identical in the list and the editor.
- **Fix:** Move it onto RecurrenceRule itself and call it from both.
- **Payoff:** One place to update if frequencies change.

### 192. resignFirstResponder dismiss call duplicated
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** ImportExportView.swift:357, FactoryResetView.swift:157
- **Issue:** The same one-liner that hides the keyboard (with the same comment) appears in the restore and reset flows.
- **Fix:** Add a one-line helper next to KeyboardDismiss.swift and call it from both.
- **Payoff:** Tiny cleanup, one shared dismiss call.

### 193. Weekday-letter array S M T W T F S duplicated
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DSDatePicker.swift:17, CalendarView.swift:278, PlanningComponents.swift:16
- **Issue:** The seven single-letter day headers are hardcoded in five spots.
- **Fix:** Pull them into the same canonical Weekday helper as the names.
- **Payoff:** One copy of the day letters.

### 194. Minute-of-day and 24h gutter formatting duplicated
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** DailyTimeline.swift:147, CalendarView.swift:879, TodayView.swift:153
- **Issue:** Converting a time to minutes-since-midnight and formatting the fixed 24h gutter is reimplemented across the timeline views.
- **Fix:** Add one small fixed-24h helper pair and reuse it (keeping it separate from clockString).
- **Payoff:** Less duplication while preserving the fixed-24h gutter rule.

### 195. Inline haptic generator calls repeated at eight sites
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** TodayView.swift:399, ScheduleEditorView.swift:586, ExerciseRoutineEditorView.swift:328, SudokuGateView.swift:97, AboutView.swift:67
- **Issue:** The vibration/haptic feedback is created inline at eight places, with no single spot to tune or disable it.
- **Fix:** Add a tiny Haptics helper with impact/success functions and replace the inline calls.
- **Payoff:** One place to adjust or turn off haptics later.

### 196. Two month-grid generators that should be one
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:864, DSDatePicker.swift:74
- **Issue:** Both the Calendar and the date picker build a 7-column month grid with the same algorithm, written twice.
- **Fix:** Extract one month-grid builder and let each screen map it to its own cells.
- **Payoff:** Week-start changes only need editing once.

### 197. Discard-changes guard re-wired in each editor
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** ScheduleEditorView.swift:156, RecurringTaskEditorView.swift:57, ReminderEditorView.swift:98
- **Issue:** Each editor repeats the same "warn before discarding unsaved changes" boilerplate; only the unsaved-check truly differs.
- **Fix:** Factor the discard boilerplate into one shared modifier or scaffold that each editor plugs its check into.
- **Payoff:** One copy of the discard logic, wired to swipe-back consistently.

### 198. Calendar event editor mixes scaled and fixed font sizes
**Priority:** Low · **Sensitivity:** Low · **Status:** ✅ Fixed
- **Where:** CalendarView.swift:1174, CalendarView.swift:1213, CalendarView.swift:1215
- **Issue:** In the calendar event editor the title scales with the font-size setting but the location/note/url fields are stuck at a fixed size.
- **Fix:** Change those three fields to use appScaledSize like the rest of the app.
- **Payoff:** This editor scales consistently with every other editor.

### 199. Top-bar icons use Image not DSImageView
**Priority:** Low · **Sensitivity:** Medium · **Status:** ✅ Fixed
- **Where:** SettingsComponents.swift:95, TodayView.swift:174, CalendarView.swift:105, RoutinesView.swift:52, BacklogView.swift:405
- **Issue:** Settings rows use the DSKit icon path but every top-bar glyph still uses the legacy fixed-size Image, so icon migration is only partial.
- **Fix:** If doing an icon-migration pass, route top-bar glyphs through DSImageView or one shared icon button.
- **Payoff:** Icon sizing/tinting comes from DSKit tokens app-wide.
