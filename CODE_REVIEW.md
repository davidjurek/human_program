# Human Program — Code Quality Audit

**Date:** 2026-06-01
**Branch:** `dskit-settings-migration`
**Scope:** Entire codebase — 95 Swift files, ~19,570 lines (app + tests)
**Type:** The audit itself was research-only. Fixes have since been applied in committed checkpoints — see the **Progress** section directly below.

This audit was run as a 16-agent parallel sweep: 13 agents each deep-read one subsystem, and 3 more swept the *whole* repo for cross-file duplication, CLAUDE.md-convention drift, and algorithmic (Big-O) problems. Every finding cites real `file:line` locations the agents actually read.

---

## Progress (updated 2026-06-01)

Status legend: ✅ done & pushed · 🟡 partly done · ⬜ not started (deferred). Every ✅ was built green with all tests passing before commit. Test count grew 70 → **78**.

### Pre-plan quick wins — ✅ all done
Done before the "10 big items" plan, as low-risk cleanups:

| Item | Status | Commit |
|------|--------|--------|
| `DefaultsKey` enum (central UserDefaults keys) | ✅ done | `8b17da1` |
| `TemplateInputs.fetchAll()` (de-triplicated fetch helpers) | ✅ done | `31cffdd` |
| `AppDateFormat` + `.keyboardSpacer()` + dead-code delete (`AppColors`/`AppTypography`/stale `AppState`) + shared `CSV`/`Weekday`/test fixtures | ✅ done | `ea75f26` |

### The 4 genuine bugs — ✅ all fixed (commit `d44d4d4`)
| Bug | Status |
|-----|--------|
| `everyNWeeks` only fired the anchor's weekday | ✅ fixed + regression test |
| App-lock timeout measured time-since-launch | ✅ fixed |
| Multi-project delete dropped projects | ✅ fixed |
| New reminders wrote every field twice | ✅ fixed |

### Phase 1 — safe tidy-ups + speed — ✅ all done
| # | Item | Status | Commit |
|---|------|--------|--------|
| #10b | Memoize the font helper (`appFont`/`appUIFont`) | ✅ done | `650330d` |
| #5 | Split the 1,279-line `CalendarView` | ✅ done (→ 894 lines) | `d4fc567` |
| #6 | Bucket calendar events (O(n²) → O(1) lookups) | ✅ done | `d47e51b` |
| #7 | Cache the Stats recomputation | ✅ done | `5e70c10` |

### Phase 2 — correctness & data safety — ✅ all done
| # | Item | Status | Commit |
|---|------|--------|--------|
| #2 | Route view writes through repositories | ✅ done | `4a6844e` |
| #3 | Merge Backlog list/folder twin screens | ✅ done | `865df72` |
| #8 | `occurrenceLimit` expansion O(range×origin) → O(range) | ✅ done + test | `9d852f1` |
| #4 | Backup field-coverage safety net | ✅ done + test | `8a47d97` |

### Phase 3 — the two big, delicate ones — ✅ all done
| # | Item | Status | Notes |
|---|------|--------|-------|
| #1 | Shared editor engine — **toolbar Save/Delete buttons** | ✅ done | `dc1dafa` — pure views |
| #1 | Shared editor engine — **keypad HHMM rule** (`TimeKeypad`) | ✅ done + tests | `0b8d636` — pure logic |
| #1 | Shared editor engine — **drag-reorder + swipe-delete state machine** | ✅ done | One `RowGestureCoordinator` + `EditableRow` + `.rowGestures()` (`EditableRowList.swift`); Schedule, Exercise, Today **and Routines** all consume it (Routines was a 4th hand-rolled copy with no reorder animation + an ungated trash). Tap-tested on device. Fixed: small-swipe-as-tap + accidental-delete-on-pull via deterministic suppression in the coordinator. |
| #9 | Calendar DSKit migration (`CalendarView` + `CalendarEventDetailSheet`) | ✅ done | Migrated the scalable chrome (nav headers, month grid, agenda/day-list rows, detail sheet, add/edit form, permission states → shared `CalendarMessageState`) to `DSText`/`DSImageView`; event times now route through `clockString` (12/24h setting). The pixel-tuned Week/Day timeline (hour gutter, event chips, now-pill, column header, all-day chips) is deliberately kept fixed-size so it doesn't reflow with the font-scale setting — same rule as Today's gutter. Eyeballed on device against a real calendar. |

**To resume the deferred work:** start a session and say *"let's do #1"* or *"let's do #9"* — I tap/eyeball alongside you, piece by piece.

---

## At a glance

**229 findings total.**

| Severity | Count | What it means |
|----------|------:|---------------|
| 🔴 High   | 14  | Real bugs, or large duplication/architecture issues worth scheduling deliberately |
| 🟠 Medium | 67  | Clear cleanups and correctness risks; most are safe, some change behavior |
| 🟢 Low    | 148 | Polish, magic numbers, minor dead code, small consistency nits |

| Category | Count | Plain meaning |
|----------|------:|---------------|
| Near-duplication | 52 | "Almost the same code" that should be merged into one shared piece |
| Efficiency (Big-O) | 34 | Work repeated more than it needs to be — slower than O(n) |
| Bug-risk | 31 | Logic that can produce a wrong result |
| CLAUDE.md inconsistency | 22 | A project rule followed in some files but skipped in others |
| Exact-duplication | 18 | Identical code copy-pasted |
| Dead code | 17 | Defined but never used |
| Best-practice | 16 | Non-idiomatic Swift/SwiftUI/SwiftData |
| Logic-structure | 10 | Tangled or fragile control flow |
| Sloppy | 9 | Magic numbers, copy-paste drift |
| Readability | 9 | Over-long files/functions hard to follow |
| Conciseness | 6 | Verbose where it could be shorter |
| Data-integrity | 5 | A model invariant isn't actually enforced |

**The headline:** the code is fundamentally sound. The pure-logic "brain" (`Core/Services`) is cleanly separated with no SwiftData leaks, the weekday encoding is consistent everywhere, and the test suite is solid. The opportunities are almost entirely **(a) the same code written in several places** (the biggest single theme by far — 70 of 229 findings are duplication) and **(b) per-render recomputation** that's cheap today but grows with your data. A handful of genuine bugs are mixed in and called out below.

---

## The big picture: 10 cross-cutting themes

These themes each appear in *many* files. Fixing the theme once (a shared helper/component) fixes every instance and stops them drifting apart — which is exactly what the CLAUDE.md "reuse UI, never duplicate it" rule is about. They're ordered by payoff.

### 1. One keyboard-spacer observer, copy-pasted into 5+ views
The identical `keyboardWillShow/Hide` → `keyboardSpacer = height` block (same `.easeOut(0.25)` / `.easeOut(0.2)` timings) lives in `TodayView`, `ScheduleEditorView`, `ReminderEditorView`, `ExerciseRoutineEditorView`, and `RoutineEditorView` — plus a *different* variant in `PlanningComponents`. **Fix:** one `.keyboardSpacer($height)` view modifier. Safe, mechanical, removes ~5 copies.

### 2. `DateFormatter` rebuilt inside SwiftUI bodies (~12 sites)
`TodayView`, `BacklogView` (×2), `BacklogTaskDetailView`, `StatsView` (×3), `DSDatePicker` (×2), `ImportExportView`, `ScheduleListView`, `RecurringTasksView` all allocate a fresh `DateFormatter` in a computed property that runs on every render — one of the most expensive Foundation allocations, on the hot path. Two of them (`ScheduleListView` / `RecurringTasksView`) even produce the *identical* "MMM d – MMM d" range string. **Fix:** a shared, cached `dateString(...)` helper mirroring the existing `clockString(...)`, backed by `static let` formatters. **Bonus finding:** the user-facing `settings.dateFormat` preference is saved and backed up but **never read** at any display site (they all hardcode "MMM d, yyyy"), so the Format setting currently has no visible effect.

### 3. UserDefaults preference keys are raw string literals in ~10 files
`"settings.fontChoice"`, `"settings.timeFormat"`, `"selectedCalendarIds"`, the `"hp.lock.*"` keys, etc. are typed by hand everywhere. **This is the highest-risk duplication in the app**: `HprgmExportService`, `HprgmImportService`, *and* `FactoryResetView` each re-list these keys manually, so one typo or forgotten key silently breaks backup, restore, or reset with no compile error — the exact failure CLAUDE.md's `.hprgm` rule warns about, currently guarded only by remembering the literal. **Fix:** one `DefaultsKey` enum of `static let` constants; derive the export/import/reset lists from it.

### 4. The four planning editors duplicate each other (the richest refactor area)
CLAUDE.md says the editors share `EditorRowInteractions` — but only the low-level UIKit recognizers and the `GlassKeypad` *view* are shared. The **SwiftUI glue around them was re-derived and copy-pasted**:
- The entire **keypad controller** (`showKeypad`/`keypadDigit`/`applyTypedToActive` HHMM-parse + snap-to-5/`keypadDone`/`dismissKeypadAndPopup`) is byte-for-byte identical in Schedule and Reminder.
- `valueRow` / `repeatRow` / `repeatOptionList` are triplicated across Schedule/Reminder/Recurring **and have already drifted** (different a11y shapes, different tap idioms, an extra `lineLimit` in one).
- The **reorder + swipe geometry** (`swipeBegan`/`beginReorder`/`projectedIndex`/`shiftOffset`/`swipeOffset` + the `0.2` rubber-band factor) is near-identical in Schedule and Exercise — and `TodayView` re-derives the *whole thing again*.
- Per-id `Binding` factories (×6), the keypad overlay `ZStack`, and the trash/Save toolbar block are each copy-pasted.

**Fix:** promote these to shared pieces (`KeypadController`, `RepeatPickerRow`/`SettingsValueRow`, a generic `EditableRowList<ID>`, `EditorSaveButton`/`EditorDeleteButton`). High payoff, but this is delicate interaction code ("took many iterations" per CLAUDE.md) — extract carefully and verify gesture parity on every editor.

### 5. Views write to `ModelContext` directly — violates architecture rule #1
`BacklogView` (`item.project = …; context.save()`), `BacklogTaskDetailView.save()`, `FactoryResetView` (`context.save()`/`context.delete()`), and `ScheduleEditorView` (`context.insert`/`context.delete`/`context.save`) all bypass their repositories. The root cause for Backlog is real: **`BacklogRepository.update()` can't clear `project`/`assignedDate`** (it treats nil as "no change"), so the detail view works around it by writing the model *and saving a second time*. A side effect of the inline writes: moved items skip the `updatedAt = Date()` bump the repo always does — a quiet data drift between code paths. **Fix:** add repo methods (`move(item:to:)`, `setProject`/`setAssignedDate`) and route all writes through them.

### 6. The DSKit migration is applied screen-by-screen — large patches still on the legacy path
Per CLAUDE.md this is *expected* (phased migration), but it's worth tracking explicitly. Still on `appFont` / `.font(.system(size:))` / raw `Color`: both **Calendar** screens, **Today**, **Backlog**, **Security/Gate/Routines/Stats**, the **onboarding** screens, and **Terms/Tutorial**. The brand blue `Color(red: 0.42, green: 0.69, blue: 0.99)` is hardcoded as a private `lightBlue` in **4 files**, and the full-width primary button is near-duplicated alongside it. Meanwhile the legacy **`AppColors` and `AppTypography` enums are now 100% dead** (zero references). **Fix:** one accent token + one shared primary-button component; delete the two dead legacy enums; keep migrating screens deliberately (don't mechanically swap — DSKit token sizes won't pixel-match `appFont`).

### 7. Template-input fetch helpers triplicated
`fetchRecurringInputs` / `fetchBacklogInputs` / `fetchScheduleInputs` (each mapping a `@Model` to its plain `Input` struct) are written three times — in `AppStartup`, `PageRefreshService`, and `TodayViewModel` — with identical bodies. The 10-field `ScheduleBlockInput` map is repeated verbatim. Add a field to an `Input` struct and you must edit three copies or pages silently diverge between launch, post-edit refresh, and Today's own refresh. **Fix:** one shared `TemplateInputs.fetchAll(context:)`. Low risk, high value.

### 8. Per-render O(n) / O(n²) recomputation in the data-heavy screens
Cheap with today's small data, but they grow:
- **Calendar month grid:** every visible day cell does `events.contains { isDate(inSameDayAs:) }` → O(42 × events) per grid, ×N month pages. **Fix:** precompute a `Set<startOfDay>` once → O(1) per cell.
- **Calendar week/day:** `eventsForDay`/`timedEventsForDay`/`allDayEventsForDay` re-filter and re-sort the whole array per day column (all-day filter runs ~14×/render). **Fix:** bucket into `[Date: [EKEvent]]` once. (Note: all-day events use an *overlap* test, not same-day — needs its own pass.)
- **Stats:** `pageByDate` dictionary rebuilt every render, `runs()` re-sorts `allPages` that `@Query` already sorted, and the week chart eagerly fans out `ForEach(0..<260)`. **Fix:** cache derived values off `allPages`; drop the redundant sort.
- **RecurrenceEngine (High):** with an `occurrenceLimit` set, `countOccurrences` can walk **every day since 1970** (20,000+ iterations) *per candidate day* — effectively quadratic over a range. **Fix:** count incrementally while scanning forward.
- **`appFont`/`appUIFont`** read UserDefaults and build a `UIFont` on *every call*, inside per-hour/per-event timeline loops. **Fix:** memoize by `(fontChoice, size, bold)`.

### 9. Magic-string sentinels and brittle matching
- `ScheduleRepository` identifies the mandatory Sleep block by `title == "Sleep"` in **6 places** — rename it and the "can't delete / must be first" invariant silently breaks.
- `StatsView` counts an exercise day if any task title *contains* "exercise" — "Exercise the dog" counts, a real exercise task without the word doesn't.
- The 1=Sun…7=Sat weekday-name table is redeclared in **4 places** with inconsistent fallbacks.

**Fix:** structural flags (`isSleep`) / a central `Weekday.fullName(_:)` next to `RecurrenceRule`, and drive the exercise streak off `sourceType`, not text.

### 10. Dead code (17 findings)
Whole files: **`AppColors.swift`**, **`AppTypography.swift`** (both zero references). Whole members: `AppState.selectedTab` / `isLocked` / the `AppTab` enum (pre-tab-bar leftovers), `CalendarView.changeMonth/changeWeek/changeDay` + the `horizontalSwipe` extension, an unused weekday dict in `ExerciseRepository`. **Most important:** `recordActivity()` in `AppLockViewModel` is **never called anywhere** — that's not just dead code, it's the cause of bug #2 below.

---

## Genuine bugs found (not just style)

These produce a wrong result today. They're behavior-changes to fix, so verify + test each — but they're real.

1. **`everyNWeeks` ignores all but one weekday** *(High — `RecurrenceRule.swift:109-119`)*. "Every 2 weeks on Mon, Wed, Fri" only ever fires on whichever weekday the anchor lands on. The `remainder == 0` gate forces the date to be an exact 7-day multiple from the anchor, so `weekdays.contains(weekday)` can only pass for the anchor's own weekday. Needs a week-aligned interval test. **Confirm intent with owner — it changes which tasks appear on which days.**

2. **App-lock timeout never measures real background time** *(High — `AppLockViewModel.swift` + `ContentView.swift:67`)*. `lastActiveAt` is only set at init; `recordActivity()` is never called and there's no `didEnterBackground` observer. So the timeout measures *time since launch*, not *time since backgrounded* — the lock can stay open after a long background or lock unexpectedly. (Masked when timeout = 0, the default.) **Fix:** stamp `lastActiveAt` on background.

3. **Multi-project delete silently drops projects** *(Medium — `BacklogView.swift:280-307`)*. Select 3 projects, 2 non-empty, tap trash: it deletes one, asks to confirm one, and *forgets the third*. The loop early-returns on the first non-empty project and never clears selection. Iteration order makes which survive nondeterministic. **Fix:** partition into empty (delete now) vs non-empty (one confirm for all).

4. **Reminder save writes every field twice** *(Medium — `ReminderEditorView.swift:486-526`)*. New reminders call `repo.create(...)` then immediately re-assign the same fields to `target` and call `repo.update(...)` — two repo calls, fragile coupling to `create()`'s defaults for the "multiple" window/interval case.

Plus several latent-but-unenforced integrity gaps: `CalendarEventLocalState` has no uniqueness constraint despite a "composite identity" comment; import re-normalizes dates to the *importing* device's timezone (a cross-timezone restore can shift a page a day); import deletes-then-inserts with no rollback on failure; the keychain PIN item sets no `kSecAttrAccessible` class; `FactoryReset`'s key whitelist misses most preference keys (font/background/appearance/icon/format survive a "factory reset").

---

## Quick wins — safe, mechanical, do-anytime

Low risk, behavior-preserving, high payoff. Good first batch:

- **Delete dead code:** `AppColors.swift`, `AppTypography.swift`, `AppState.selectedTab`/`isLocked`/`AppTab`, `CalendarView.changeMonth/Week/Day` + `horizontalSwipe` (remove from `project.yml`, re-run `xcodegen`).
- **One `DefaultsKey` enum** for all UserDefaults keys (theme 3).
- **One cached `dateString(...)` helper** + static formatters (theme 2).
- **One `.keyboardSpacer($h)` modifier** (theme 1).
- **One shared `csvCell` + the POSIX/ISO formatters** (currently byte-identical in both CSV exporters).
- **One `TemplateInputs.fetchAll(context:)`** (theme 7).
- **Merge `syncCompletion`/`syncUncompletion`** into a shared guard helper (`BacklogMaintenanceService`).
- **Central `Weekday.fullName(_:)` / `RecurrenceRule.resolvedWeekdays`** (themes 9).
- **Test cleanup:** delete the 2 hand-rolled `makeTestModelContainer` copies (use the public one); extract `gregorianUTC`/`localCalendar`/`makeDate` into one test-support file.
- **Shared back/toolbar buttons** + `EditorSaveButton`/`EditorDeleteButton` (keeps the 44×44 + `.contentShape` rule in one place).
- **Generic `Array.binding(for:keyPath:)`** to collapse the 6 per-id binding factories.
- **Drop the redundant `.sorted()`** in `StatsView.runs()` (`@Query` already sorts).

## Needs your sign-off first — these change behavior

Don't apply silently; each alters output or a destructive flow:

- The 4 genuine bugs above (each changes results — fix *with* a new test pinning the intended behavior).
- Wiring `settings.dateFormat` into actual display (theme 2) — currently a no-op setting.
- Making `FactoryReset` clear *all* preference keys (theme 3 / data-integrity).
- The `RecurrenceEngine` `occurrenceLimit` optimization (must match the existing origin/boundary exactly).
- `everyNMinutes` fire-time alignment, the `ScheduleBlockInput` template-key collision, the `CalendarEventLocalState` uniqueness constraint, import timezone handling, keychain accessibility class — all touch persistence/scheduling semantics.
- Re-checking `GameAccessService` at the moment the Sudoku gate opens the game.

---

## Full catalog (every finding, by subsystem)

Below is the complete, exhaustive list — all 229 findings grouped by the subsystem they were found in, ordered High → Medium → Low. Each entry has the location(s), the problem, the suggested fix, the effort, and the breakage risk.


### Contents

1. [Core Brain (pure Services + Models)](#core-brain-pure-services--models) — 13 (2H / 4M / 7L)
2. [Repositories (@MainActor ModelContext owners)](#repositories-mainactor-modelcontext-owners) — 15 (0H / 3M / 12L)
3. [Import/Export (.hprgm + CSV + parser)](#importexport-hprgm--csv--parser) — 11 (1H / 4M / 6L)
4. [Platform Glue (Notifications, Calendar adapter, Persistence, Security, GameBridge)](#platform-glue-notifications-calendar-adapter-persistence-security-gamebridge) — 20 (1H / 2M / 17L)
5. [App entry + DesignSystem tokens](#app-entry--designsystem-tokens) — 12 (0H / 5M / 7L)
6. [Today feature (TodayView, TodayViewModel, DailyTimeline, TaskDetailView)](#today-feature-todayview-todayviewmodel-dailytimeline-taskdetailview) — 16 (1H / 4M / 11L)
7. [Calendar feature (Month/Week/Day/List) — CalendarView.swift, CalendarEventDetailSheet.swift, CalendarSourceSettingsView.swift](#calendar-feature-monthweekdaylist--calendarviewswift-calendareventdetailsheetswift-calendarsourcesettingsviewswift) — 16 (0H / 6M / 10L)
8. [Backlog feature (BacklogView, BacklogComponents, BacklogTaskDetailView)](#backlog-feature-backlogview-backlogcomponents-backlogtaskdetailview) — 15 (2H / 5M / 8L)
9. [Planning Editors (Schedule / Reminder / Exercise / Recurring) + their list screens](#planning-editors-schedule--reminder--exercise--recurring--their-list-screens) — 16 (3H / 7M / 6L)
10. [Settings shared Components](#settings-shared-components) — 17 (0H / 3M / 14L)
11. [Settings misc screens (Customization / Format / Accessibility / Security / Import-Export / FactoryReset / About / Licenses / Terms / Tutorial / CatCorner)](#settings-misc-screens-customization--format--accessibility--security--import-export--factoryreset--about--licenses--terms--tutorial--catcorner) — 17 (0H / 4M / 13L)
12. [Security UI + Gate + Routines + Stats](#security-ui--gate--routines--stats) — 13 (0H / 4M / 9L)
13. [Test suite (HumanProgramTests — 8 files)](#test-suite-humanprogramtests--8-files) — 14 (1H / 3M / 10L)
14. [Cross-file duplication (whole repo: HumanProgram/ + HumanProgramTests/)](#cross-file-duplication-whole-repo-humanprogram--humanprogramtests) — 18 (2H / 7M / 9L)
15. [Cross-cutting CLAUDE.md convention consistency (whole repo)](#cross-cutting-claudemd-convention-consistency-whole-repo) — 5 (1H / 1M / 3L)
16. [Algorithmic complexity & performance (whole repo)](#algorithmic-complexity--performance-whole-repo) — 11 (0H / 5M / 6L)


---

## Core Brain (pure Services + Models)

> The pure-logic brain is well-separated: all five service files (RecurrenceEngine, DailyPageGenerator, CompletionService, BacklogMaintenanceService, StreakCalculator) import only Foundation — no SwiftData leaks — and Models.swift correctly isolates the @Model/SwiftData layer. Weekday encoding (1=Sun..7=Sat) is consistent everywhere. Codable structs are clean. The code is readable and well-commented. However there are real correctness and complexity problems: (1) occurrenceLimit counting is O(days-since-1970) per match when no start/anchor date is set, and matches() is called per-candidate-day, making range expansion potentially O(range × 20000+); (2) everyNWeeks only ever fires on the anchor's own weekday, silently ignoring the other selected weekdays; (3) several near-duplicate blocks (the two backlog sync functions are almost identical; the two add-new-task loops in refresh; the day-counting loops across RecurrenceEngine). Plus minor invariant/readability items. None of these are UI/DSKit findings since this area is logic-only.

### 🔴 HIGH — everyNWeeks only fires on the anchor's own weekday, ignoring other selected weekdays

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Models/RecurrenceRule.swift:109`
  - `HumanProgram/Core/Models/RecurrenceRule.swift:113`
  - `HumanProgram/Core/Models/RecurrenceRule.swift:117`
  - `HumanProgram/Core/Models/RecurrenceRule.swift:119`
- **Problem:** In the .everyNWeeks branch, daysBetween(anchor, date) is required to satisfy `remainder == 0` (line 117), where remainder = days % 7. That is only true when `date` is an exact multiple of 7 days from the anchor — i.e. the same weekday as the anchor. The final check `self.weekdays.contains(weekday)` (line 119) can then only ever pass for the anchor's weekday. So a rule like "every 2 weeks on Mon, Wed, Fri" will only fire on whichever of those weekdays the anchor lands on, silently dropping the others. The intended semantics (per the everyNWeeks factory taking `on weekdays:`) is clearly multiple weekdays within the qualifying weeks. The correct logic is: compute the week index of the date relative to the anchor's week (using week-of-era or floor(days/7) aligned to week starts), require weekIndex % interval == 0, then check weekdays.contains(weekday) — without the remainder==0 gate.
- **Recommendation:** Replace the remainder==0 gate with a week-aligned interval test: determine which week the date falls in relative to the anchor's week and require that week index to be a multiple of interval, then keep the weekdays.contains(weekday) check. Verify against a test that picks an anchor on Monday and asserts the rule also fires on the same week's Wednesday/Friday.
- **Risk if applied:** Medium-high — this changes recurrence output. It may be deliberately constrained today, but it contradicts the factory's `on weekdays:` parameter and the everyNWeeks intent. Must be confirmed with the owner and pinned with new tests before changing; do not apply blindly as it alters which tasks appear on which days.

### 🔴 HIGH — occurrenceLimit counting is O(days-since-1970) per match, recomputed for every candidate day

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:85`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:91`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:111`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:18`
- **Problem:** matches(_:on:) calls countOccurrences(before:) whenever rule.occurrenceLimit is set. countOccurrences' origin falls back to Date(timeIntervalSince1970: 0) when neither startDate nor anchorDate is set (line 97), so the day-by-day loop on lines 111-118 walks every day from 1970 to the target — over 20,000 iterations, each invoking rule.occurs(on:) plus a calendar.date(byAdding:) allocation. Worse, this is recomputed from scratch for EVERY candidate day inside occurrences(of:in:) (line 73) and nextOccurrence (line 44). Expanding a limited rule across a one-year range becomes roughly O(365 × 20000) calendar operations. Even with a startDate set, it is O(daysSinceStart) per candidate, i.e. quadratic over a range. occurrences() over a range could instead count occurrences incrementally as it scans forward.
- **Recommendation:** For range/next expansion, walk forward once and maintain a running occurrence counter so the limit check is O(1) per day instead of re-counting from origin each time. Alternatively, in occurrences(of:in:), iterate days ascending and stop appending once the running count reaches occurrenceLimit, rather than calling matches() (which re-counts) per day. Keep matches() as-is for single-date checks but document its cost. No behavioral change if the running count starts from the same origin the current code uses.
- **Risk if applied:** Medium — this is a real algorithm change to a core service covered by recurrence tests. If done carefully (same origin, same occurs() predicate, count strictly before the target day) results are identical, but it must be validated against RecurrenceEngine tests, especially around startDate/anchorDate origin selection and the &lt; vs &lt;= boundary. Safer to leave matches() untouched and only optimize the range path.

### 🟠 MEDIUM — CalendarEventLocalState has no unique identity attribute despite composite identity comment

- **Category:** data-integrity | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Models/Models.swift:278`
  - `HumanProgram/Core/Models/Models.swift:279`
- **Problem:** The comment (line 279) states 'composite identity: date + eventId', but unlike every other @Model in the file, CalendarEventLocalState declares no @Attribute(.unique) on anything and no compound uniqueness constraint. SwiftData will not enforce one-row-per-(date,eventId); nothing prevents duplicate local-state rows for the same event on the same day, which would make per-event overrides (hidden/titleOverride/completed) ambiguous (last/arbitrary write wins on read). Other models all pin identity with .unique id.
- **Recommendation:** Add a SwiftData #Unique compound constraint on (date, eventId) (iOS 17 supports #Unique on @Model) or synthesize a deterministic composite id with @Attribute(.unique). Confirm the repository's get-or-create already dedupes; if it does, this is defense-in-depth, but the model invariant is currently unenforced.
- **Risk if applied:** Medium — adding a uniqueness constraint changes the schema and could fail migration if duplicate rows already exist on a device. Must be validated against existing data / migration before applying; flagged as a latent integrity gap.

### 🟠 MEDIUM — activeScheduleBlocks reconstructs template groups by hashing metadata, which collides distinct templates

- **Category:** logic-structure | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Services/DailyPageGenerator.swift:137`
  - `HumanProgram/Core/Services/DailyPageGenerator.swift:154`
  - `HumanProgram/Core/Services/DailyPageGenerator.swift:166`
- **Problem:** ScheduleBlockInput has no parent-template id, so the function infers template identity from a TemplateKey of (isEnabled, assignedWeekdays, customDateStart, customDateEnd) (lines 154-176). The inline comment on lines 148-149 admits 'that can collide.' If two distinct enabled templates share the same weekday set / date range / enabled flag, their blocks are merged into one group and both templates' blocks are emitted together for a matching day — a data-correctness hazard driven purely by the input shape lacking a template id. The whole grouping dance also makes the function long and hard to follow.
- **Recommendation:** Add a templateId field to ScheduleBlockInput at the call site (the repository already knows the parent ScheduleTemplate.id) and group by that real identity instead of metadata. If changing the input struct is out of scope, at minimum document the collision precondition loudly. Do not change behavior silently.
- **Risk if applied:** Medium — touches the ScheduleBlockInput contract and its callers in the repository; needs the repo to pass the parent id. Behavior is unchanged for non-colliding templates. Validate with schedule-resolution tests before applying.

### 🟠 MEDIUM — syncCompletion and syncUncompletion are near-identical copies

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Services/BacklogMaintenanceService.swift:38`
  - `HumanProgram/Core/Services/BacklogMaintenanceService.swift:68`
- **Problem:** syncCompletion (lines 38-63) and syncUncompletion (lines 68-93) share the exact same guard sequence: sourceType==.backlog, sourceId present, find item by id, page&gt;=today, assignedDate matches pageDate. They differ only in the final status assigned (.done vs .backlog). This is copy-paste with one-token drift — any change to the matching rules (e.g. how date matching works) must be made in two places and they can silently diverge.
- **Recommendation:** Extract a single private helper that performs the shared guards and returns the matched item (or nil), then have both public methods call it and set the appropriate status. Keeps both public signatures and return shapes identical, so callers are unaffected.
- **Risk if applied:** Low — pure internal refactor with no behavior change if the shared guard logic is byte-for-byte preserved. Covered by past-page decoupling tests.

### 🟠 MEDIUM — Two add-new-task loops in refresh() are structurally duplicated

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Services/DailyPageGenerator.swift:370`
  - `HumanProgram/Core/Services/DailyPageGenerator.swift:390`
  - `HumanProgram/Core/Services/DailyPageGenerator.swift:332`
- **Problem:** The recurring branch (lines 370-387) and the backlog branch (lines 390-407) are the same shape: filter desiredPage.tasks by sourceType, drop those whose sourceId is already covered, sort by localizedCompare, then append GeneratedTasks with an incrementing nextSortOrder. Likewise the existing-task classification switch (lines 332-360) handles .recurring and .backlog with identical structure differing only in which set they touch. This triples the maintenance surface for the add/remove logic.
- **Recommendation:** Factor the 'filter desired tasks of a given sourceType not already present, sort, append with running sortOrder' into one local closure/helper parameterized by sourceType and the existing-source-id set. Same for the classification switch (a helper that takes the desired-id set and the accumulators). No output change.
- **Risk if applied:** Low-to-medium — internal refactor only, but refresh() is the snapshot-refresh path. Must preserve ordering (recurring before backlog) and sortOrder continuation exactly; verify with generation/refresh tests.

### 🟢 LOW — refresh() appends new tasks after max existing sortOrder, which can leave non-contiguous / unstable ordering

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Services/DailyPageGenerator.swift:363`
  - `HumanProgram/Core/Services/DailyPageGenerator.swift:271`
  - `HumanProgram/Core/Services/DailyPageGenerator.swift:259`
- **Problem:** generate() assigns recurring tasks sortOrder 0..n then backlog continuing the index (lines 259, 271), so a freshly generated page interleaves recurring/backlog by sortOrder. But refresh() appends ALL new tasks (recurring AND backlog) after maxExistingSortOrder (line 363-364). After several refreshes, a newly-matching recurring task gets a sortOrder higher than existing backlog tasks, so the on-page order no longer matches the generate() ordering (recurring-before-backlog). The two code paths produce different orderings for the same logical content, which can surprise the UI's sort-by-sortOrder rendering.
- **Recommendation:** If recurring-before-backlog ordering matters on refresh, normalize/renumber after merging, or at least document that refresh intentionally appends in arrival order. Confirm with the owner which ordering is desired before changing, since the UI relies on sortOrder.
- **Risk if applied:** Medium — reordering on refresh is user-visible. Do not change without confirming intended behavior; flagged as a latent inconsistency, not a guaranteed bug.

### 🟢 LOW — StreakCalculator longest-streak inner consecutive check is verbose and could be simplified

- **Category:** conciseness | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Services/StreakCalculator.swift:92`
  - `HumanProgram/Core/Services/StreakCalculator.swift:97`
  - `HumanProgram/Core/Services/StreakCalculator.swift:111`
- **Problem:** The longest-streak loop (92-120) maintains runLength, previousDate, and a nested isConsecutive flag with a double-optional-binding (98-103). Because sortedDates only contains tracked days (gaps for untracked days), the 'consecutive' test correctly compares prev+1 day == date, but the control flow (set isConsecutive, branch, then separately update longestStreak) is more ceremony than needed and re-derives startOfDay(expectedNext) even though prev came from already-normalized keys.
- **Recommendation:** Simplify to: track previousDate; if previousDate+1day == date and current is complete, runLength += 1 else runLength = 1; longestStreak = max(longestStreak, runLength). The extra startOfDay on expectedNext (line 100) is redundant since calendar.date(byAdding:.day,to: normalizedDate) of a start-of-day date is already start-of-day. Purely a readability cleanup.
- **Risk if applied:** Low — must keep the same gap-handling semantics (untracked days break a run because sortedDates skips them). Verify against StreakCalculator tests; behavior should be identical.

### 🟢 LOW — Dead/unreachable nil-date continue branches in date loops

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:41`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:70`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:112`
  - `HumanProgram/Core/Services/RecurrenceRule.swift:159`
- **Problem:** Each `guard let candidate = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }` guards against a nil that calendar.date(byAdding:) does not realistically return for finite day offsets on a Gregorian calendar — the continue branches are effectively unreachable. Similarly daysBetween returns `components.day ?? 0` (RecurrenceRule.swift:159), silently turning an impossible nil into 0, which would mask a malformed-date bug as 'fires on anchor day' rather than surfacing it.
- **Recommendation:** Leave the guards (defensive) but consider documenting them as defensive-only, or collapse via the shared day-iteration helper noted above. For daysBetween, the `?? 0` is acceptable but worth a comment that 0 means 'treat as same day' on impossible input.
- **Risk if applied:** Low — no behavior change; informational.

### 🟢 LOW — everyNDays / everyOtherDay overlap and everyOtherDay ignores interval

- **Category:** logic-structure | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Models/RecurrenceRule.swift:103`
  - `HumanProgram/Core/Models/RecurrenceRule.swift:121`
- **Problem:** .everyOtherDay (121-125) is exactly .everyNDays with interval 2 (days % 2 == 0), but it's a separate frequency that hardcodes 2 and ignores the rule's interval field entirely. Having two code paths that express the same concept means the every-other-day behavior can diverge from the everyNDays behavior (e.g. if everyNDays gains start-date alignment logic, everyOtherDay won't get it). It also means callers must know which of two equivalent encodings to use.
- **Recommendation:** Either treat everyOtherDay as a thin alias delegating to the everyNDays branch with interval 2, or document why it is intentionally distinct. No behavior change if delegated correctly (both currently key off the resolved anchor).
- **Risk if applied:** Low — if refactored to delegate to the identical days%2 logic with the same anchor, output is unchanged; verify the anchor resolution path is identical.

### 🟢 LOW — Day-by-day expansion loop repeated three times across RecurrenceEngine

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:40`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:69`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:111`
- **Problem:** nextOccurrence (40-47), occurrences (69-76) and countOccurrences (111-118) each build the same loop: startOfDay anchor, calendar.date(byAdding:.day,value:offset), guard-continue on nil, then a predicate. The 'continue on nil date' branch is also effectively dead (calendar.date(byAdding:.day) never returns nil for valid Gregorian offsets) but is copied three times.
- **Recommendation:** Add one private helper like `forEachDay(from:count:_ body:(Date)-&gt;Void)` (or a lazy day sequence) and have all three call it. Reduces drift and centralizes the offset math.
- **Risk if applied:** Low — mechanical extraction with identical semantics.

### 🟢 LOW — DailyPageScheduleBlock duplicates ScheduleBlock field-for-field including durationMinutes loss

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Models/Models.swift:16`
  - `HumanProgram/Core/Models/Models.swift:51`
  - `HumanProgram/Core/Models/Models.swift:24`
- **Problem:** ScheduleBlock (16-48) and DailyPageScheduleBlock (51-74) declare the same six stored properties and the same initializer with default colorHex. The snapshot type is a near-clone; the only meaningful difference is that the snapshot omits the durationMinutes computed property (lines 24-31), so any duration display logic re-derives that math elsewhere (the overnight 1440-wrap formula) instead of reusing it. Two structs that must stay in lockstep are a drift risk: adding a field to one (already happened with colorHex [#20]) requires remembering the other.
- **Recommendation:** Consider giving DailyPageScheduleBlock the same durationMinutes computed property (so the overnight-wrap math lives once), or have it conform to a shared protocol carrying the duration computation. Do not merge the two types (snapshot vs template separation is intentional), just share the derived math.
- **Risk if applied:** Low — adding a computed property is additive and non-breaking; verify nothing redefines durationMinutes for the snapshot already.

### 🟢 LOW — Magic minute/cycle constants repeated without named symbols

- **Category:** sloppy | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Models/Models.swift:29`
  - `HumanProgram/Core/Models/Models.swift:330`
  - `HumanProgram/Core/Models/Models.swift:331`
  - `HumanProgram/Core/Models/RecurrenceRule.swift:113`
  - `HumanProgram/Core/Models/RecurrenceRule.swift:133`
- **Problem:** 1440 (minutes/day) appears in the overnight duration math (Models.swift:29) and as the default windowEndMinute via 1200 with the comment '20:00' (line 331), 480 with '08:00' (line 330); 7 (days/week) and 4 (split-cycle length) are bare literals in RecurrenceRule (113, 133). These are well-commented but uncentralized, so the same domain constant is re-typed in multiple files and can drift.
- **Recommendation:** Introduce named constants (e.g. minutesPerDay = 1440, daysPerWeek = 7, splitCycleLength = 4) in one place and reference them. Purely cosmetic; no behavior change.
- **Risk if applied:** Low — no behavior change, just naming.


---

## Repositories (@MainActor ModelContext owners)

> The seven repositories are generally clean, idiomatic @MainActor SwiftData owners that correctly centralize ModelContext access, respect the isPastLocked snapshot rule in the three places it matters (getOrCreate skips refresh on past pages, refreshTodayAndFuture double-guards, syncCalendarTasks early-returns), and use plain-data Service structs. The most important correctness concern is an inconsistent save path in DailyPageRepository.getOrCreate (the existing-today/future refresh branch never calls context.save(), unlike every other mutation), which relies on implicit autosave and can desync from other explicit-save paths. There is also a recurring duplicated pattern across all seven repos — sorted FetchDescriptor + try context.fetch, the "next sortOrder = max+1" idiom, the reorder-by-enumerated-index idiom, and per-item updatedAt stamping — that could be factored into shared helpers. Other issues are smaller: full-table fetches followed by in-memory filtering, fetch-in-effect O(n) scans driven by weekday-name dictionaries rebuilt per call, dead code (an unused weekdayNames dictionary), a confusing/contradictory comment block in BacklogRepository.update, magic numbers (1440, calendarSortBase semantics, default sleep times), and string-literal "Sleep" used as a structural sentinel throughout ScheduleRepository. No view-layer ModelContext writes occur inside these files, but note (outside this area) several Views/ViewModels do fetch/write ModelContext directly, which is the broader convention being eroded.

### 🟠 MEDIUM — String literal "Sleep" used as a structural sentinel throughout ScheduleRepository

- **Category:** best-practice | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:116`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:143`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:161`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:202`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:227`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:233`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:323-330`
- **Problem:** The mandatory-first Sleep block is identified everywhere by comparing `title == "Sleep"`. The Sleep-first invariant — the single most structural rule in this repo — hinges on a raw string compared in at least six places. If a user renames the Sleep block, or a future caller creates a block titled 'Sleep', the invariant (can't delete, must stay at index 0, managed only via updateSleepBlock) silently breaks or misfires. The same literal is also the default block's title (defaultSleepBlock), so the sentinel and the user-facing name are conflated.
- **Recommendation:** Represent the Sleep block by a stable, non-title flag (e.g. a `kind`/`isSleep` field on ScheduleBlock, or a reserved id) rather than its title string, and centralize the check in one helper (e.g. `isSleepBlock(_:)`). Then the title becomes free-form. This is a model change, so gate behind owner approval; at minimum, hoist the literal into a single `private static let sleepTitle` constant used everywhere to remove the scattered magic string.
- **Risk if applied:** Medium. Hoisting to one constant is safe (pure refactor). Switching the sentinel to a flag touches the model and migration/import (HprgmBundle) and must preserve the 'Sleep is mandatory first block' invariant and all tests — needs owner approval and care.

### 🟠 MEDIUM — getOrCreate refresh-of-existing-page path never calls context.save()

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:37-53`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:333-376`
- **Problem:** In getOrCreate, when an existing today/future page is found and refreshed, it calls applyRefresh(...) and then returns `existing` at line 52. applyRefresh deliberately does NOT save (header comment: 'Apply a refresh diff to an existing page (no save).'). So this branch mutates the page (deletes/inserts tasks, replaces scheduleBlocks, recalculates completion) but never persists with try context.save(). Every other mutating method in this repo (toggleTask, addManualTask, deleteTask, syncCalendarTasks, etc.) ends with try context.save(), and the new-page branch saves at line 83. This branch silently relies on SwiftData implicit autosave to eventually flush — inconsistent with the rest of the file and fragile (autosave timing/turn-off can leave the refresh unpersisted, and dayComplete/task changes can briefly disagree with what the next explicit-save path sees).
- **Recommendation:** Have the existing-today/future branch persist explicitly: after the applyRefresh call (around line 51), add `try context.save()` before returning, OR move the save into applyRefresh and out of its callers consistently. Match the explicit-save convention used by every other method. Do not change which pages are refreshed (the isPast / isPastLocked guards must stay).
- **Risk if applied:** Low. Adding an explicit save only guarantees persistence that the code already intends; the guards that protect past/locked pages are untouched. Slight extra disk write per Today open, but getOrCreate already saves on the create path.

### 🟠 MEDIUM — Contradictory/confusing comment block in BacklogRepository.update about clearing fields

- **Category:** readability | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/BacklogRepository.swift:33-55`
- **Problem:** The update(...) method has a 7-line comment (lines 42-48) that talks about a 'sentinel approach', 'overloaded versions below', and a 'typed variant' for clearing project/assignedDate — none of which exist in the file. The actual behavior is simply 'non-nil overwrites, nil leaves unchanged', so you can never clear project or assignedDate through this method. The comment describes a design that was never implemented, which actively misleads a reader about a real limitation: callers wanting to un-assign a date or remove a project have no API path here. This is also a latent data-integrity gap (clearing is impossible via the repo).
- **Recommendation:** Either (a) reduce the comment to one honest line ('non-nil updates the field; nil leaves it unchanged — clearing is not supported here'), or (b) if clearing is actually needed, add explicit clear methods / a sentinel optional-of-optional parameter. Do not change current overwrite behavior without owner sign-off, since callers depend on nil = no-op.
- **Risk if applied:** Low if only the comment is corrected (no behavior change). Higher if you add clearing semantics — that changes the contract and could let callers null fields that today survive, so gate behind owner approval.

### 🟢 LOW — calendarSortBase coupling is implicit and fragile across syncCalendarTasks and manual append

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:10-13`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:138`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:223`
- **Problem:** sortOrder ordering relies on a layered convention: recurring tasks get small indices, calendar tasks get calendarSortBase (10000) + startMinuteOfDay, and manual tasks get max+1. addManualTask computes max+1 over ALL existing tasks (line 138), so once any calendar task exists, a new manual task lands at ~10000+ rather than truly 'after the calendar group only when intended' — and the recurring/calendar/manual zoning is enforced only by these magic offsets, not by an explicit group field. A startMinuteOfDay &gt;= 1440 (defensive) or a future second sort base could collide. The behavior is currently correct for the documented read order, but the invariant is invisible and easy to break with a future edit.
- **Recommendation:** Document the zoning as an explicit enum-ordered group (sort first by a group rank derived from sourceType, then by intra-group order) so manual/calendar/recurring ordering does not depend on magic numeric bases, or at minimum centralize the base/zone math in one helper. Treat as advisory; do not change current sortOrder values without verifying the Today view's flat sort still reproduces recurring -&gt; calendar(earliest) -&gt; manual.
- **Risk if applied:** Medium. Any change to sortOrder semantics can reorder the Today task list and interacts with user hold-drag reordering and re-sync preservation (lines 205-213). Verify against the documented read order before touching.

### 🟢 LOW — syncCalendarTasks deletes via page.tasks.removeAll while iterating page.tasks

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:196-203`
- **Problem:** The removal loop iterates `for task in page.tasks where task.sourceType == .calendar` and, inside the loop body, mutates the same collection with `page.tasks.removeAll { $0.id == task.id }` plus context.delete(task). Mutating a collection while iterating it is a known footgun; Swift's for-in over an array iterates a copy of the array value so it does not crash here, but the pattern is fragile and easy to misread, and the same shape (filter-then-mutate-in-loop) recurs in applyRefresh where it is done more safely by collecting tasksToDelete first (line 351). Inconsistent handling of the same operation.
- **Recommendation:** Mirror applyRefresh's safer pattern: collect the calendar tasks to remove into a local array first, then remove/delete them after the loop. Behavior is identical but the iterate-while-mutating smell is gone and the two methods read consistently.
- **Risk if applied:** Low. Current code does not crash (array value-type iteration), so this is a robustness/readability improvement; collecting-then-deleting yields the same final state.

### 🟢 LOW — getOrCreate has an if/else where both branches do the identical generate+populate

- **Category:** conciseness | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:60-80`
- **Problem:** After creating a new page, the `if isPast { ... } else { ... }` block runs the exact same generator.generate(...) call with identical arguments and the same populatePage(page, from: generated) in both branches. The only real difference (page.isPastLocked = isPast) was already set at line 57 before the branch. So the if/else adds ~20 lines and two comments to express one code path, obscuring that past and future creation are identical except for the lock flag already applied.
- **Recommendation:** Collapse the if/else into a single generate + populatePage call (the isPastLocked flag is already set above). Removes duplication with no behavior change.
- **Risk if applied:** Low. The two branches are textually identical aside from comments; collapsing them produces the same generated page and the same lock flag.

### 🟢 LOW — Dead code: unused weekdayNames dictionary in ensureSevenWeekdayRoutines

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:24-32`
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:38`
- **Problem:** weekdayNames is a 7-entry [Int:String] dictionary built every call but never used to seed anything — routines are created with name: "" (line 41). Line 38 is a no-op statement `_ = weekdayNames` with the comment '(kept for reference; names are no longer seeded)'. This is leftover scaffolding: a dictionary literal allocated and discarded on every invocation, plus a deliberately-dead assignment kept only as a comment anchor.
- **Recommendation:** Delete the weekdayNames dictionary (lines 24-32) and the `_ = weekdayNames` line (38). The weekday names already live in ScheduleRepository.weekdayName(for:); if a canonical map is wanted, reference that instead of resurrecting a local copy.
- **Risk if applied:** Low. The dictionary is provably unused (the only reference is the no-op `_ =`). Removing it cannot change routine creation, which uses an empty name.

### 🟢 LOW — fetchActive fetches the whole table then filters in memory by enum status

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Repositories/BacklogRepository.swift:65-70`
- **Problem:** fetchActive calls fetchAll() (full BacklogItem table fetch, sorted) and then filters `$0.status == .backlog` in memory. The header comment justifies this ('SwiftData #Predicate enum comparisons are unreliable'), so it is a known workaround, but it still means the DB returns every item (including all done items) on every active-list load, and the cost grows linearly with total history. For a personal app the dataset is small, so impact is minor, but it is worth noting as a scalability smell and a place to revisit if predicate-on-rawValue becomes viable.
- **Recommendation:** Leave as-is for now given the documented SwiftData limitation, but consider storing status as a raw Int/String and using a #Predicate on the raw value, which SwiftData handles reliably, so the DB filters instead of returning the whole table. Verify equivalence with a test before switching.
- **Risk if applied:** Medium. Changing the predicate path risks the exact enum-comparison bug the comment warns about; needs careful testing against real data. Safe to defer.

### 🟢 LOW — fetchRoutine(for:) and ensureSevenWeekdayRoutines do O(n) in-memory scans via fetchAll each call

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:64-69`
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:18-45`
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:50-58`
- **Problem:** fetchRoutine(for:date:) calls fetchAll() (fetch + full in-memory sort by weekday) then linearly scans calling engine.matches on each routine until the first match. ensureSevenWeekdayRoutines also calls fetchAll() and builds a Set of existing weekdays. fetchAll itself always re-fetches and re-sorts. Each of these is fine in isolation (at most 7 routines), but fetchAll is the unconditional building block and is re-sorted on every call; if fetchRoutine is invoked per-day in a loop (e.g. generating multiple pages), it re-fetches and re-sorts the whole routine set each iteration.
- **Recommendation:** Where a caller needs routine-for-date repeatedly (e.g. multi-day generation), fetch routines once and pass them in, rather than calling fetchRoutine per date. No change needed for single-shot UI calls given the 7-row ceiling; flag only as a guideline for hot loops.
- **Risk if applied:** Low. This is advisory; only matters if a caller loops. No change to the repo itself is required.

### 🟢 LOW — Sorted FetchDescriptor + context.fetch boilerplate duplicated across all 7 repos

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Repositories/BacklogRepository.swift:73-78`
  - `HumanProgram/Core/Repositories/BacklogRepository.swift:103-108`
  - `HumanProgram/Core/Repositories/RecurringTaskRepository.swift:15-20`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:26-31`
  - `HumanProgram/Core/Repositories/NotificationReminderRepository.swift:16-21`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:306-311`
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:50-58`
- **Problem:** Nearly every repo's fetchAll is the same shape: build a FetchDescriptor&lt;Model&gt;(sortBy: [SortDescriptor(\.&lt;key&gt;, order: .forward)]) and return try context.fetch(descriptor). The pattern is copy-pasted seven-plus times with only the model type and sort key changing. This is exactly the 'same code written more than once that should be a shared helper' smell, and it means a future change (e.g. adding a default secondary sort, or a fetch-error wrapper) has to be edited in seven places.
- **Recommendation:** Introduce one shared generic helper (e.g. a small extension on ModelContext like `func fetchSorted&lt;T&gt;(_ type: T.Type, by key: KeyPath&lt;T,...&gt;, order:) throws -&gt; [T]`, or a thin base/protocol) and have each repo's fetchAll delegate to it. Pure refactor, no behavior change.
- **Risk if applied:** Low-medium. Generic SortDescriptor helpers over KeyPaths can be awkward to type in Swift/SwiftData; must verify the same sort order and types compile. Behavior identical if the descriptor is built the same way.

### 🟢 LOW — "next sortOrder = (items.map{...max} ?? -1) + 1" idiom duplicated across repos

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:138`
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:99`
  - `HumanProgram/Core/Repositories/RoutineRepository.swift:35`
- **Problem:** The append-at-end ordering computation `(collection.map { $0.sortOrder }.max() ?? -1) + 1` appears verbatim in three repos (page tasks, exercise items, routine items). It is correct but duplicated, and the off-by-one fallback (-1 so an empty list yields 0) is the kind of detail that drifts if one copy is edited.
- **Recommendation:** Extract a tiny shared helper such as `nextSortOrder(after:)` (a free function or protocol extension over types exposing sortOrder) and call it from all three. No behavior change.
- **Risk if applied:** Low. A mechanical extraction; the arithmetic stays identical.

### 🟢 LOW — Reorder-by-enumerated-index idiom duplicated across repos

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:158-165`
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:126-132`
  - `HumanProgram/Core/Repositories/RoutineRepository.swift:52-56`
- **Problem:** Three reorder methods share the same body: enumerate the passed-in array and assign each element's sortOrder to its index, stamp updatedAt, save. DailyPageRepository.reorderTasks adds an `if task.sortOrder != index` guard to avoid no-op writes; the exercise/routine versions write unconditionally. So the logic is duplicated AND has drifted (one version is optimized to skip unchanged writes, two are not) — copy-paste drift.
- **Recommendation:** Extract one shared reorder helper that assigns index-based sortOrder (ideally adopting the `!= index` guard everywhere to avoid spurious writes/dirtying), then have all three delegate. Keep each repo responsible only for stamping its own parent updatedAt.
- **Risk if applied:** Low. Adopting the skip-if-unchanged guard in the exercise/routine paths is safe (it only avoids redundant assignment of the same value); the resulting persisted order is identical.

### 🟢 LOW — weekdayName / weekday-name mapping duplicated and built ad hoc

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:333-344`
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:24-32`
- **Problem:** The 1=Sunday..7=Saturday weekday-name mapping exists in two forms in this area: a switch in ScheduleRepository.weekdayName(for:) and the (now-dead) dictionary in ExerciseRepository. The encoding is correct (matches CLAUDE.md 1=Sun..7=Sat), but it is a shared piece of knowledge expressed twice, and the codebase very likely has a canonical weekday-name source elsewhere (Calendar symbols or a DesignSystem helper). Two copies of the same lookup risk drift (e.g. localization, abbreviations).
- **Recommendation:** Consolidate to one weekday-name source (prefer Calendar's localized symbols indexed via the 1..7 encoding, or a single shared helper) and have conflict messages use it. After consolidation the ExerciseRepository copy is already removable per the dead-code finding.
- **Risk if applied:** Low for ScheduleRepository conflict strings (cosmetic message text). If switching to localized Calendar symbols, verify the index mapping (Calendar weekdaySymbols is 0-based for index 0 = Sunday) to preserve 1=Sun..7=Sat.

### 🟢 LOW — Per-call Calendar.current.startOfDay normalization scattered instead of one helper

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/BacklogRepository.swift:26`
  - `HumanProgram/Core/Repositories/BacklogRepository.swift:51`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:32-33`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:248`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:294`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:289-292`
- **Problem:** Date-to-start-of-day normalization is repeated in many places, sometimes via the injected `calendar` parameter (DailyPageRepository, good for testability) and sometimes via hardcoded `Calendar.current` (BacklogRepository.create/update at lines 26/51, ScheduleRepository.detectConflict at 289-292). The mix means some paths are test-injectable and some are not, and the same normalization idiom is hand-written repeatedly.
- **Recommendation:** Standardize on the injected `calendar` parameter everywhere a repo normalizes dates (BacklogRepository.create/update and ScheduleRepository.detectConflict currently hardcode Calendar.current), and consider a single small normalize helper. Improves testability and consistency.
- **Risk if applied:** Low. Threading the existing calendar parameter through these methods changes nothing for production (default is .current) but makes them testable; verify call sites still compile/pass the default.

### 🟢 LOW — Magic numbers: 1440 (minutes/day) and minute-of-day arithmetic scattered in ScheduleRepository

- **Category:** sloppy | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:92`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:211`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:252`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:326-328`
- **Problem:** The literal 1440 (minutes in a day) appears in three modulo expressions and the default sleep times use `21 * 60 + 30` / `5 * 60 + 30` inline. These are correct but unlabeled magic numbers; the wrap-around-midnight logic depends on 1440 being right in every copy, and the default sleep times (21:30 / 05:30) are encoded as arithmetic with end-of-line comments rather than named constants.
- **Recommendation:** Introduce `private static let minutesPerDay = 1440` (and optionally named default bedtime/wake constants) and use them in the modulo expressions and defaultSleepBlock. Pure readability refactor, identical values.
- **Risk if applied:** Low. Replacing the literal with a same-valued constant cannot change behavior.


---

## Import/Export (.hprgm + CSV + parser)

> The Import/Export area is well-organized and functionally faithful: the export-fetch and import-insert paths are field-symmetric, v2 additions (routines, calendarEventStates, settings) are correctly optional so v1 backups still decode, the import uses a dictionary for bucket lookup (no O(n^2)), and CSV exporters include formula-injection defense. The main code-health problems are (1) a large, fragile per-field encode/decode mapping that must be edited in 4+ places for every new model field — exactly the round-trip-fidelity hazard CLAUDE.md warns about; (2) byte-for-byte duplicated csvCell helpers across the two CSV exporters; (3) duplicated UserDefaults key strings in gather/apply settings; and (4) a few latent fidelity/robustness gaps (date re-normalization on the importing device's timezone, no guard against completedAt/completed desync, deletes-then-inserts with no atomic rollback). None of these are active bugs in normal use, but several are silent-data-loss traps if a future model field is added and one of the parallel sites is missed.

### 🔴 HIGH — Per-field encode/decode mapping duplicated across model, JSON struct, export, and import (4+ touch points per field)

- **Category:** near-duplication | **Effort:** large
- **Locations:**
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:287-435`
  - `HumanProgram/Core/ImportExport/HprgmImportService.swift:88-234`
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:6-148`
- **Problem:** Every @Model field is written out by hand three to four times: once on the @Model, once on the *JSON mirror struct, once in the export fetch-and-map (e.g. fetchBacklogItems lines 290-301), and once in the import insert (lines 99-111). There is no compiler check that these stay in sync. CLAUDE.md's single most important fidelity rule is that adding a new @Model field or preference key MUST be added to bundle + export fetch + import insert or backups silently lose it. This structure makes that omission trivially easy and invisible — the build still passes if a field is dropped from the export map or the import insert. It is also a large amount of repetitive boilerplate (the export service is ~240 lines of near-identical map blocks).
- **Recommendation:** Without changing behavior, reduce the surface area for drift: make each *JSON struct gain a failable/throwing init from its @Model (e.g. BacklogItemJSON(from: BacklogItem)) and an apply(to:) / model-building method, so the field list lives in ONE place per type instead of split between fetch and insert. Alternatively, add a round-trip test that asserts every @Model's Mirror children (minus relationships) appear in its JSON struct, to fail the build when a field is added but not mapped. This is a refactor for maintainability; HprgmBackupRoundTripTests should pin behavior before attempting it.
- **Risk if applied:** Medium if refactored — any reshuffle of the mapping risks dropping a field. Must be guarded by the existing round-trip tests. Zero risk if only a coverage test is added.

### 🟠 MEDIUM — DailyPage and CalendarEventLocalState dates are re-normalized to start-of-day on the importing device's timezone

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/ImportExport/HprgmImportService.swift:161`
  - `HumanProgram/Core/ImportExport/HprgmImportService.swift:226`
  - `HumanProgram/Core/Models/Models.swift:266`
  - `HumanProgram/Core/Models/Models.swift:290`
- **Problem:** Import reconstructs pages via DailyPage(date: json.date, ...) and calendar states via CalendarEventLocalState(date: json.date, ...). Both inits call Calendar.current.startOfDay(for:) again (Models.swift:266, 290). The exported date is the already-normalized start-of-day from the original device, encoded as an absolute instant (.iso8601). If the backup is restored in a different timezone (or the user's timezone changed), startOfDay re-applied to that absolute instant can shift the page to the previous/next calendar day. For a restore that is supposed to 'exactly mirror the backup' (CLAUDE.md), this is a subtle fidelity break tied to timezone, not data.
- **Recommendation:** Do not change the init contract (other call sites rely on normalization). Instead, after constructing the model in import, set page.date = json.date directly (it is already a normalized start-of-day from export) so the stored instant is preserved verbatim. Add a round-trip test that exercises a non-UTC timezone. Verify against DailyPageRepository expectations before applying, since the rest of the app assumes start-of-day.
- **Risk if applied:** Medium — touches how page dates are stored; must confirm downstream date-keyed lookups (getOrCreate, completion) still match. Guard with tests.

### 🟠 MEDIUM — Import deletes everything then inserts with no atomic rollback on failure

- **Category:** data-integrity | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/ImportExport/HprgmImportService.swift:39-83`
  - `HumanProgram/Core/ImportExport/HprgmImportService.swift:237`
- **Problem:** importData deletes ALL pages, backlog, buckets, templates, exercise routines, schedules, notifications, routines, and calendar states (lines 39-83) and only calls context.save() at the very end (line 237). If decode succeeded (preview) but an insert or the final save throws, the in-memory context holds a half-built state, and depending on container autosave settings the user could be left with deleted data and no replacement. There is no try/catch that restores the prior state on failure. The destructive nature ('REPLACES all current data') makes a mid-operation failure especially costly.
- **Recommendation:** Wrap the whole delete+insert sequence so a thrown error rolls back: e.g. catch and call context.rollback() before rethrowing, or perform the work and explicitly verify save() succeeded before considering the old data gone. Do not change the happy path. Confirm the container's autosave behavior first so rollback actually reverts the deletes.
- **Risk if applied:** Low-medium — adding rollback on the error path shouldn't affect the success path, but verify ModelContext.rollback() interacts correctly with the inserts already made.

### 🟠 MEDIUM — csvCell sanitizer is duplicated byte-for-byte in both CSV exporters

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/ImportExport/BacklogCSVExporter.swift:58-72`
  - `HumanProgram/Core/ImportExport/TaskHistoryCSVExporter.swift:69-79`
- **Problem:** The csvCell(_:) helper — injection-prefix check (=, +, -, @), double-quote escaping, and wrapping — is implemented identically in both BacklogCSVExporter and TaskHistoryCSVExporter. The injectionPrefixes array, the escape, and the wrap logic are copy-pasted. If the injection rules are ever tightened (e.g. to also catch a leading tab or to add the carriage-return/0x09 cases), one copy will be fixed and the other will drift, leaving one export path unprotected.
- **Recommendation:** Extract a single shared CSV cell-sanitizing function (e.g. a CSVWriter helper or a static func on a shared CSV utility) and call it from both exporters. Pure-string, no SwiftData, so it can live alongside BacklogImportParser. Behavior is identical, so this is a safe consolidation.
- **Risk if applied:** Very low — pure string function, identical inputs/outputs; covered by exporter unit tests if present.

### 🟠 MEDIUM — UserDefaults preference keys hardcoded as string literals twice (gather vs apply)

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:270-285`
  - `HumanProgram/Core/ImportExport/HprgmImportService.swift:243-254`
- **Problem:** The nine preference keys ("settings.fontChoice", "settings.fontSizeStep", ..., "selectedCalendarIds") are written as bare string literals in gatherSettings (export) and again in applySettings (import). A typo or a renamed key in one site but not the other silently breaks that preference's backup/restore with no compile error — and per CLAUDE.md these preference keys are an explicit part of the bundle contract. There is also no single source of truth shared with the rest of the app that reads/writes these same keys.
- **Recommendation:** Define the nine keys as shared constants (an enum of static lets) used by both gatherSettings and applySettings (ideally the same constants the Settings screens use). This removes the chance of export/import key drift without changing any stored value.
- **Risk if applied:** Very low — constant extraction, same literal values.

### 🟢 LOW — parseCSVLine materializes the whole line into an [Character] array and indexes manually

- **Category:** conciseness | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/ImportExport/BacklogImportParser.swift:77-99`
- **Problem:** The CSV field parser converts each line to Array(line) and walks it with a manual integer index and lookahead (chars[i+1]). It is correct, but the manual index bookkeeping (i += 1 in two places) is the kind of loop that invites off-by-one mistakes on future edits, and it allocates a full Character array per line. For a backlog import this is not a performance concern, but it is more verbose and error-prone than needed.
- **Recommendation:** Optionally rewrite using an index-based iteration over the String's own indices or a small state-machine over line.unicodeScalars, removing the separate array allocation and the dual i += 1 sites. Purely a clarity/robustness cleanup; behavior must match (test the quoted/escaped-quote cases).
- **Risk if applied:** Low — but quoting/escaping edge cases must be re-verified against tests; easy to introduce a parsing regression.

### 🟢 LOW — No invariant guard that completedAt and completed agree on imported tasks

- **Category:** data-integrity | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/ImportExport/HprgmImportService.swift:170-183`
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:380-410`
- **Problem:** DailyPageTask import copies completed and completedAt independently from the bundle (lines 179-180). A hand-edited or older .hprgm could carry completed=false with a non-nil completedAt, or completed=true with completedAt=nil. The CompletionService completion rule keys off completed, but other UI (timeline/checkmark timestamps) may read completedAt, so a desynced pair can render inconsistently. Export faithfully reproduces whatever is stored, so the round trip is faithful, but there is no normalization on import to keep the pair consistent.
- **Recommendation:** Optionally normalize on import (if completed==false set completedAt=nil, and if completed==true and completedAt==nil leave as-is or backfill). Since .hprgm is meant to mirror exactly, prefer only normalizing the clearly invalid case (completedAt set while completed==false). Confirm with the owner whether strict mirroring or normalization is wanted before applying.
- **Risk if applied:** Low — only touches clearly inconsistent imported rows; could in theory alter a deliberately-crafted backup, so confirm intent first.

### 🟢 LOW — parseCSV validates the date before checking for an empty title, rejecting the whole file for a bad date in a title-less (skippable) row

- **Category:** logic-structure | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/ImportExport/BacklogImportParser.swift:53-60`
- **Problem:** In the row loop, the date is parsed and validated (lines 53-59) BEFORE the title-empty skip check (line 60). A row that has no title (and would otherwise be silently skipped and counted) but happens to contain a malformed date string will reject the entire file via .rejected, rather than being skipped. This is inconsistent: a title-less row is otherwise treated as ignorable noise, yet its date field is held to a hard fail-the-whole-file standard.
- **Recommendation:** Move the title.isEmpty skip check above the date parsing, so rows with no title are skipped (and counted) before their date is validated. This makes empty rows uniformly ignorable. Verify against any test expecting the current strict behavior before changing.
- **Risk if applied:** Low — changes which malformed files are rejected vs skipped; check BacklogImportParser tests for an expectation pinning the current order.

### 🟢 LOW — Repeated child-collection sort-and-map blocks across export fetch methods

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:237-240`
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:337-348`
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:384-397`
- **Problem:** The pattern `collection.sorted { $0.sortOrder &lt; $1.sortOrder }.map { ...JSON(...) }` is repeated for Routine.items, ExerciseRoutine.items, and DailyPage.tasks. The sort-by-sortOrder convention is duplicated rather than expressed once. Not a correctness issue, but it is repeated structure that has to be kept consistent (e.g. if a tie-break is ever added).
- **Recommendation:** Optional: add a small helper (e.g. an extension `sortedBySortOrder()` on sequences of the relevant types, or a generic free function) so the ordering rule is defined once. Behavior unchanged.
- **Risk if applied:** Very low — pure refactor of identical sorting.

### 🟢 LOW — parseText and parseCSV trim with .whitespaces only, so leading/trailing tabs survive but other whitespace differs from blank-line filtering

- **Category:** sloppy | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/ImportExport/BacklogImportParser.swift:18-23`
  - `HumanProgram/Core/ImportExport/BacklogImportParser.swift:36-38`
- **Problem:** Titles and fields are trimmed with .whitespaces (space + tab) but newlines are handled separately via split(whereSeparator: \.isNewline). A line that is only tabs/spaces is correctly dropped, but the trimming set is inconsistent with what counts as 'blank' across the two parsers, and .whitespaces excludes some Unicode whitespace. Minor, but it is the kind of subtle inconsistency that produces surprising 'empty' rows.
- **Recommendation:** Use .whitespacesAndNewlines consistently for the emptiness/trim checks, or factor a single isBlank/normalize helper shared by parseText and parseCSV. Low impact; verify no test depends on the current trimming set.
- **Risk if applied:** Very low — minor change to which strings count as blank.

### 🟢 LOW — appVersion fallback magic string "unknown" and inline Info.plist lookup

- **Category:** sloppy | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:214`
- **Problem:** The app version is read inline via Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown". The 'unknown' sentinel and the Info.plist key are inline magic values; if the app ever centralizes a version accessor, this site won't use it. Minor, and it does not affect data fidelity (appVersion is metadata only).
- **Recommendation:** Optional: route through a shared AppInfo.version accessor if one exists or is added, keeping the sentinel in one place. No behavior change.
- **Risk if applied:** Very low — metadata field only.


---

## Platform Glue (Notifications, Calendar adapter, Persistence, Security, GameBridge)

> These platform-glue files are generally clean, well-commented, and follow the project's architecture rules (Services are pure/no-SwiftData; repositories are @MainActor and own ModelContext; GameAccessService is the single planner-game bridge). The biggest real concern is a latent app-lock timeout bug: AppLockViewModel.checkLockOnForeground() compares against lastActiveAt, but lastActiveAt is only ever set at VM init and by recordActivity(), which is never called anywhere, and there is no willResignActive/background observer recording the background time. So the timeout measures elapsed time since launch rather than since the app actually backgrounded, which makes the lock fire (or not fire) at the wrong moment. Secondary issues: the Keychain PIN entry sets no kSecAttrAccessible attribute (default is whenUnlocked, but it's unspecified and not robust across restore/migration), keychainSave doesn't handle errSecDuplicateItem defensively, several dead/unused public APIs (cancelAll, lockNow, recordActivity, GameAccessService.lockReason), heavy structural near-duplication across the five fire-time computation methods and the five CalendarLocalState setters, and GameContainerView violates the DSKit/no-hardcoded-font convention (it's an intentional non-DSKit stub, but uses .font(.system(size:))). The everyNMinutes fire-time math has a subtle correctness gap (interval boundaries are computed relative to window-start within the day but not strictly aligned to midnight, and the first-day cursor can skip the window). None of the recommended changes need to alter behavior except the lock-timeout fix, which is the one genuinely worth doing.

### 🔴 HIGH — App-lock timeout never measures real background time (lastActiveAt is stale)

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Security/AppLockViewModel.swift:14`
  - `HumanProgram/Core/Security/AppLockViewModel.swift:50`
  - `HumanProgram/Core/Security/AppLockViewModel.swift:65`
  - `HumanProgram/App/ContentView.swift:67`
- **Problem:** checkLockOnForeground() locks when Date().timeIntervalSince(lastActiveAt) &gt;= lockTimeoutSeconds. But lastActiveAt is only assigned at VM init (line 14) and inside recordActivity() (line 66), and recordActivity() is never called anywhere in the app (grep across the whole tree finds no caller), nor is there any willResignActive/didEnterBackground observer that stamps the moment the app backgrounds. ContentView only wires willEnterForeground -&gt; checkLockOnForeground (ContentView.swift:67-71). So lastActiveAt stays at app-launch time. The elapsed value therefore reflects time-since-launch (or since the last unlock that reset nothing), not time-since-backgrounded. With a non-zero timeout the app can stay unlocked after a long background period (if it was launched recently) or lock unexpectedly, and the timeout setting is effectively unreliable. (With timeout 0 it still always locks, masking the bug for the default case.)
- **Recommendation:** Record the background timestamp by adding a willResignActive/didEnterBackground observer that sets lastActiveAt = Date() (or call recordActivity() there), so the foreground check measures elapsed-since-background. Keep recordActivity() and lastActiveAt as the single source of truth. This is the one finding that requires a (small) behavior change to actually fix; if behavior must stay frozen, at minimum document that timeout is currently 'since launch' rather than 'since background'.
- **Risk if applied:** Low-to-medium: adding the background observer changes lock timing to the intended semantics. If a screen currently relies on the present (buggy) behavior the timing of the lock screen will shift. The fix itself is small and localized.

### 🟠 MEDIUM — Keychain PIN item sets no accessibility attribute (kSecAttrAccessible)

- **Category:** best-practice | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Security/AppLockRepository.swift:113`
  - `HumanProgram/Core/Security/AppLockRepository.swift:120`
- **Problem:** keychainSave() builds the SecItemAdd query with class/service/account/value only and never sets kSecAttrAccessible (verified by grep: no kSecAttrAccessible anywhere). The default protection class is kSecAttrAccessibleWhenUnlocked, which is acceptable, but leaving it unspecified is fragile: the item can be included in device backups and migrated to a new device, and the protection level is implicit rather than declared. For a security-critical secret (the PIN hash) the accessibility class should be explicit, and the project doc states 'Forgotten PIN = reset app. No recovery... No iCloud backup of the PIN' — kSecAttrAccessibleWhenUnlockedThisDeviceOnly would match that intent (non-migratable).
- **Recommendation:** Add kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly to the keychainSave query to make the protection class explicit and prevent backup/restore migration of the PIN, matching the 'no iCloud backup of the PIN' decision.
- **Risk if applied:** Medium: changing the accessibility attribute on an existing item changes which queries match. Existing installs that saved without the attribute will still load (the load query doesn't filter on accessibility), but to be safe this should be applied as 'on next setupPIN'. Care needed so existing PINs aren't orphaned; safest applied at a reset/setup boundary.

### 🟠 MEDIUM — everyNMinutes fire-time math: interval boundaries not midnight-aligned and first-day cursor can skip the window

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:181`
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:194`
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:204`
- **Problem:** computeFireTimes for everyNMinutes rounds 'up to the next interval boundary' using minutesFromWindow = max(minutesSinceMidnight, windowStart) and then aligns remainder against `interval` (lines 194-198). On day 0 the cursor starts at nextMinute which is computed from now; if now is already past windowEnd, the inner while (minuteCursor &lt;= windowEnd) never runs for day 0 — fine — but the alignment is relative to minutesSinceMidnight, not to windowStart, so fire times within the window are not necessarily multiples of the interval offset from windowStart (e.g. window 480, interval 60 could yield 487, 547... if 'now' lands mid-interval), making the schedule drift from the user's expected on-the-hour cadence. Also nextMinute computed before the loop is reused only for day 0; for subsequent days minuteCursor resets to windowStart (line 204) which is correct, so day 0 and later days can produce inconsistent minute offsets within the window.
- **Recommendation:** Align interval boundaries to windowStart (compute boundary = windowStart + ceil((cursor - windowStart)/interval)*interval) so all fire times are windowStart + k*interval, consistent across day 0 and later days. Verify against a unit test that pins expected fire minutes.
- **Risk if applied:** Medium: this changes the exact fire minutes produced for everyNMinutes reminders. Any existing test asserting current minutes would need updating, and users would see slightly different (more regular) fire times. Behavior-affecting, so only apply with owner sign-off and test coverage.

### 🟢 LOW — Force-unwraps on Calendar.date(byAdding:) in fire-time loops

- **Category:** best-practice | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:150`
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:175`
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:203`
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:249`
- **Problem:** Several `cal.date(byAdding: .day, value: 1, to: ...)!` force-unwraps inside the while loops. cal.date(byAdding:) returns nil only in pathological cases, but a force-unwrap in a loop that runs up to maxPerReminder*60 iterations is a latent crash surface, and the project generally avoids force-unwraps.
- **Recommendation:** Use a guard let ... else { break } (loops already bound by results.count) so an unexpected nil ends the walk gracefully instead of crashing. Behavior-preserving in the normal case.
- **Risk if applied:** Low: in normal Gregorian calendar use these never return nil, so swapping ! for guard/break does not change observed behavior.

### 🟢 LOW — keychainSave does not defensively handle errSecDuplicateItem

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Security/AppLockRepository.swift:113`
  - `HumanProgram/Core/Security/AppLockRepository.swift:30`
- **Problem:** setupPIN() calls try? keychainDelete() before keychainSave() (line 31) to avoid errSecDuplicateItem, and keychainSave throws on any non-success status. This works in the normal flow, but if the prior delete silently fails (it's try?'d) or a stale item exists from another code path, SecItemAdd returns errSecDuplicateItem and setupPIN throws keychainError(-25299) instead of updating. The more robust pattern is SecItemAdd, and on errSecDuplicateItem fall back to SecItemUpdate.
- **Recommendation:** In keychainSave, on errSecDuplicateItem perform a SecItemUpdate of kSecValueData instead of throwing, so PIN setup is idempotent regardless of prior state. Keep the pre-delete as a fast path.
- **Risk if applied:** Low: only changes the error/duplicate branch, not the happy path. Should be covered by verifying setupPIN twice in a row still succeeds.

### 🟢 LOW — createEvent returns event.eventIdentifier which can be nil/empty before save propagation

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/CalendarAdapter/CalendarAdapterService.swift:84`
  - `HumanProgram/Core/CalendarAdapter/CalendarAdapterService.swift:110`
- **Problem:** Both createEvent overloads return event.eventIdentifier immediately after store.save. EKEvent.eventIdentifier is documented as nil until the event has been saved/committed, and for some calendar types the identifier can be momentarily unavailable; the return type is String (non-optional), so a nil bridges to an empty/garbage value rather than signaling failure. Callers then persist this id locally to find the event later.
- **Recommendation:** After save, guard let id = event.eventIdentifier else { throw } so a missing identifier surfaces as an error instead of a silently-empty id that breaks later lookups. Low risk because save just succeeded; mostly defensive.
- **Risk if applied:** Low: in practice eventIdentifier is populated after a successful save; adding a guard only changes the (rare) failure path from returning empty to throwing, which callers already handle via try.

### 🟢 LOW — fetchEvents 'empty ids means all calendars' is overloaded with a fallback that hides misconfiguration

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/CalendarAdapter/CalendarAdapterService.swift:44`
  - `HumanProgram/Core/CalendarAdapter/CalendarAdapterService.swift:51`
- **Problem:** When calendarIds is non-empty but none of them match any current calendar, filtered.isEmpty triggers `calendars = nil`, which means 'all calendars'. So a stale/invalid selected-calendar id silently flips the query from 'these specific calendars' to 'every calendar', showing events the user de-selected. CalendarView.swift:716 even comments 'an empty list means all to fetchEvents', confirming this ambiguity is load-bearing — but the non-empty-but-unmatched case is an unintended path to the same all-calendars behavior.
- **Recommendation:** Distinguish 'no selection (all)' from 'selection that matched nothing (none)': when calendarIds is non-empty but nothing matches, return [] (or query with an empty calendars array) rather than falling back to all calendars. Verify callers (TodayView/CalendarView) expect empty == none in that case.
- **Risk if applied:** Medium: changes results when a selected calendar id no longer resolves (e.g. a calendar was deleted). Could intentionally rely on the current fallback, so confirm with callers/owner before changing — flagging as behavior-affecting.

### 🟢 LOW — GameContainerView uses hardcoded .font(.system(size:)) and raw colors (DSKit convention)

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/GameBridge/GameContainer.swift:19`
  - `HumanProgram/Core/GameBridge/GameContainer.swift:25`
  - `HumanProgram/Core/GameBridge/GameContainer.swift:39`
- **Problem:** CLAUDE.md says views must use DSKit and must not use hardcoded .font(.system(size:)). GameContainerView uses .font(.system(size: 72,...)), .font(.system(size: 11,...)), and .font(.system(size: 14,...)) plus raw Color.black / .white opacities. This is a stub (CLAUDE.md notes the Sudoku gate + GameContainer are stubs, and the Cat Corner viewer is intentionally non-DSKit full-screen black), so it's a borderline case — but it's worth recording as a known DSKit-convention exception so it isn't mistaken for finished, migrated UI.
- **Recommendation:** Leave as-is if it remains an intentional pre-real-game stub, but mark it explicitly as a known non-DSKit stub (a comment already says 'Polished stub'). If it ever becomes real UI it must migrate to DSText/tokens. No change needed now.
- **Risk if applied:** Low: it's a stub. Migrating now would be churn for code slated to be replaced by the real game engine; not migrating preserves behavior.

### 🟢 LOW — GameContainerView also has filler/explanatory copy ('swipe down to exit')

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/GameBridge/GameContainer.swift:24`
- **Problem:** CLAUDE.md says 'No filler/explanatory text' unless genuinely needed. The 'swipe down to exit' caption is instructional copy. It's a stub so low priority, but it's the kind of instructional line the doc asks to avoid.
- **Recommendation:** Acceptable for a temporary stub; flag only. If kept, fine; when the real game lands, drop the instructional caption per the copy rule.
- **Risk if applied:** Low: stub-only; removing text has no functional effect.

### 🟢 LOW — lockTimeoutSeconds getter has a redundant local + comment

- **Category:** conciseness | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Security/AppLockRepository.swift:77`
- **Problem:** The getter assigns `let v = UserDefaults.standard.integer(forKey:)` then immediately returns v, with a comment restating that integer(forKey:) defaults to 0. It could be a one-line return; the temporary adds nothing.
- **Recommendation:** Collapse to `get { UserDefaults.standard.integer(forKey: keyTimeout) }` (keep the comment if helpful). Behavior-preserving.
- **Risk if applied:** Low: identical value returned.

### 🟢 LOW — recordActivity() and lockNow() are dead/unused public API

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Security/AppLockViewModel.swift:59`
  - `HumanProgram/Core/Security/AppLockViewModel.swift:65`
- **Problem:** lockNow() (the 'Lock Now' helper, line 59) and recordActivity() (line 65) have no callers anywhere in the codebase (verified by grep). recordActivity() being unused is also the proximate cause of the timeout bug above. lockNow() suggests a Settings 'Lock Now' button that was never wired.
- **Recommendation:** Either wire them up (recordActivity from the background observer, lockNow from a Settings button) or remove them. Since recordActivity is the intended fix vehicle for the timeout bug, prefer wiring it rather than deleting.
- **Risk if applied:** Low: removing truly-unused symbols is safe; wiring them is the better path and is also low risk.

### 🟢 LOW — RollingReminderScheduler.cancelAll() is unused

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:51`
- **Problem:** cancelAll() (removeAllPendingNotificationRequests) has no callers (verified by grep). reschedule() already calls removeAllPendingNotificationRequests internally at line 37, so the public cancelAll is redundant surface area.
- **Recommendation:** Remove cancelAll() if no future caller is planned, or keep it intentionally as a public utility — but flag it so it doesn't look 'finished' while being unreachable.
- **Risk if applied:** Low: removing an unused public method cannot change runtime behavior. Only risk is if an external module (tests) reference it; grep shows none in app code.

### 🟢 LOW — GameAccessService.lockReason() is unused

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/GameBridge/GameAccessService.swift:25`
- **Problem:** lockReason(todayPage:today:calendar:) builds a human-readable string 'for internal logging only' but has no callers (verified by grep). It also duplicates the date-match / dayComplete logic of canAccessGame above it (lines 11-21 vs 25-42).
- **Recommendation:** Remove it, or if kept for debugging, derive both canAccessGame and lockReason from one shared private evaluation so the two gates can't drift apart.
- **Risk if applied:** Low: it's unreferenced; removal cannot affect behavior. Refactor to share logic is also behavior-preserving if done carefully.

### 🟢 LOW — makeModelContainer and makeTestModelContainer duplicate the entire Schema array

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Persistence/ModelContainerSetup.swift:4`
  - `HumanProgram/Core/Persistence/ModelContainerSetup.swift:26`
- **Problem:** The 14-model Schema([...]) list is written out twice verbatim (lines 5-20 and 27-42). If a new @Model is added (the CLAUDE.md backup rule already calls out the risk of forgetting to register new models), it must be added in both lists; forgetting the test list means tests silently run against a different schema than production.
- **Recommendation:** Define the model list once (e.g. a private let allModels: [any PersistentModel.Type] or a shared makeSchema()) and build both containers from it, so production and test schemas can never diverge.
- **Risk if applied:** Low: behavior-preserving; both containers would use the identical (de-duplicated) schema, which is exactly what they do today.

### 🟢 LOW — Five CalendarLocalState setters are near-identical (get-or-create, set field, stamp updatedAt, save)

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/CalendarAdapter/CalendarLocalStateRepository.swift:32`
  - `HumanProgram/Core/CalendarAdapter/CalendarLocalStateRepository.swift:40`
  - `HumanProgram/Core/CalendarAdapter/CalendarLocalStateRepository.swift:48`
  - `HumanProgram/Core/CalendarAdapter/CalendarLocalStateRepository.swift:56`
- **Problem:** toggleCompletion, setHidden, setTitleOverride, setNotesOverride all repeat the exact pattern: state = try getOrCreate(...); mutate one field; state.updatedAt = Date(); try context.save(). The boilerplate (updatedAt stamp + save) is copy-pasted four times, which is the kind of drift the project's reuse rule warns against.
- **Recommendation:** Extract a private helper like `private func mutate(eventId:date:_ body: (CalendarEventLocalState) -&gt; Void) throws` that does getOrCreate, runs body, stamps updatedAt, and saves once. Each public method becomes a one-liner. Behavior-preserving.
- **Risk if applied:** Low: purely a refactor; the resulting save/updatedAt semantics are identical. Verify each setter still persists and stamps updatedAt.

### 🟢 LOW — Five fire-time methods repeat the same day-cursor walk skeleton

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:138`
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:156`
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:181`
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:223`
- **Problem:** dailyFireTimes, weekdayFireTimes, everyNMinutesFireTimes, hourlyWindowFireTimes share the structure: init cal/now, var results, while results.count &lt; maxPerReminder, advance dayCursor with cal.date(byAdding:.day,value:1,...)!. weekdayFireTimes and hourlyWindowFireTimes are especially similar (walk days, match weekday, append slots), differing mainly by inner-slot step (one slot at fireHour:fireMinute vs hourly slots in window). The repeated `cal.date(byAdding: .day, value: 1, to: ...)!` force-unwrap appears 4 times.
- **Recommendation:** Factor a shared day-walking helper that takes a per-day closure returning the slots to append, capping at maxPerReminder. This removes the repeated loop scaffolding and the repeated force-unwrap. Behavior-preserving if the closures reproduce current slot logic exactly.
- **Risk if applied:** Low-to-medium: a careful refactor is behavior-preserving, but fire-time logic is subtle (timezone/DST around startOfDay + minute addition), so it needs the existing scheduler tests to pass unchanged.

### 🟢 LOW — canAccessGame and shouldRevealGate are byte-identical gate logic in two services

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/GameBridge/GameAccessService.swift:11`
  - `HumanProgram/Core/GameBridge/EasterEggGateService.swift:12`
- **Problem:** GameAccessService.canAccessGame (lines 11-21) and EasterEggGateService.shouldRevealGate (lines 12-22) implement exactly the same check: page non-nil, page.dayComplete, startOfDay(page.date) == startOfDay(today). The CLAUDE.md mandate is that GameAccessService is the ONLY bridge; having EasterEggGateService re-implement the identical unlock predicate risks the two drifting apart (one could be patched and not the other).
- **Recommendation:** Have EasterEggGateService.shouldRevealGate delegate to GameAccessService().canAccessGame(...) so there is a single source of truth for 'is today truly complete', honoring the single-bridge rule. Behavior is identical today, so this is a safe consolidation.
- **Risk if applied:** Low: both functions return the same value for all inputs today, so delegating is behavior-preserving. Worth a quick check that EasterEggGateService isn't intentionally meant to diverge.

### 🟢 LOW — CalendarAdapter repeats 'find calendar by id or default' block three times

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/CalendarAdapter/CalendarAdapterService.swift:76`
  - `HumanProgram/Core/CalendarAdapter/CalendarAdapterService.swift:103`
  - `HumanProgram/Core/CalendarAdapter/CalendarAdapterService.swift:137`
- **Problem:** createEvent(title:...), createEvent(spec:), and updateEvent each contain the same 'if let calendarId, find store.calendars(for:.event).first(where: identifier==calendarId) else defaultCalendarForNewEvents' pattern (with updateEvent only assigning when found). store.calendars(for:.event) is also re-fetched each time, and the create/update field-mapping (title/location/isAllDay/start/end/notes/url/recurrence/alarm) between createEvent(spec) and updateEvent is largely duplicated.
- **Recommendation:** Extract a private `resolveCalendar(_ id: String?) -&gt; EKCalendar?` helper and a private `apply(_ spec: NewEventSpec, to event: EKEvent)` helper used by both create(spec) and update. Behavior-preserving; reduces repeated store.calendars fetches.
- **Risk if applied:** Low-to-medium: the update path intentionally only sets event.calendar when the id resolves (doesn't fall back to default), while create falls back to default — the shared helper must preserve that asymmetry, so the refactor needs care to not change update's fallback behavior.

### 🟢 LOW — appendDigit comment promises auto-submit that doesn't happen

- **Category:** readability | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Security/AppLockViewModel.swift:71`
  - `HumanProgram/Core/Security/AppLockViewModel.swift:73`
- **Problem:** The doc comment says appendDigit 'auto-submits if it looks like the user has finished', but the implementation only appends a digit and never calls submitUnlockPIN — there's no auto-submit logic. The comment is misleading about behavior (variable-length PINs 4-20 can't auto-submit on length anyway).
- **Recommendation:** Update the comment to match reality (just appends a digit; submission is explicit). Pure documentation fix.
- **Risk if applied:** Low: comment-only; no behavior change.

### 🟢 LOW — Magic numbers for lockout thresholds/durations and dayOffset cap

- **Category:** sloppy | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Security/AppLockViewModel.swift:121`
  - `HumanProgram/Core/Security/AppLockViewModel.swift:124`
  - `HumanProgram/Core/Security/AppLockViewModel.swift:127`
  - `HumanProgram/Core/Notifications/RollingReminderScheduler.swift:202`
- **Problem:** submitUnlockPIN hardcodes attempt thresholds (3/5/10) and lockout durations (5/30/60s) inline with duplicated message strings. everyNMinutesFireTimes hardcodes a `dayOffset &lt; 60` safety cap (line 202) with no explanation of why 60 days. These magic numbers are scattered and the lockout copy ('Too many attempts. Wait Ns.') is partly duplicated.
- **Recommendation:** Hoist thresholds/durations into named constants (or a small lockout-policy table) and add a comment on the 60-day cap. Behavior-preserving.
- **Risk if applied:** Low: extracting constants with identical values does not change behavior.


---

## App entry + DesignSystem tokens

> The app-entry layer (ContentView, AppStartup, AppState, PageRefreshService, the interstitial/onboarding views) and the DesignSystem token files are mostly clean, well-commented, and follow the project's architecture rules: startup work is funneled through @MainActor repositories, services are pure, and past-page snapshot protection is delegated correctly to DailyPageRepository (refresh/sever both honor isPastLocked). The most actionable issues are dead code: the entire legacy AppColors enum (0 usages), the legacy AppTypography enum (0 usages), and AppState.selectedTab/isLocked plus the AppTab enum (0 usages) are all unreferenced. There is real near-duplication between AppStartup and PageRefreshService (three identical template-fetch helpers) and between the two onboarding screens (a hardcoded lightBlue color, button styling). A handful of CLAUDE.md/DSKit conventions are violated in the entry views (raw Color(red:...) and appFont(.system-equivalent) usage instead of DSKit tokens, though some are justified by comments). No snapshot-protection, weekday-encoding, or main-thread bugs were found.

### 🟠 MEDIUM — Legacy AppColors enum is entirely dead code

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/DesignSystem/AppColors.swift:5-77`
- **Problem:** A project-wide grep shows ZERO references to AppColors anywhere in the codebase (the only hit is the definition itself). CLAUDE.md marks AppColors as LEGACY and says new/migrated UI must use DSKit. The migration appears complete, so this entire ~70-line enum (background, content, accents, task-state, semantic aliases, separators, section headers, lock tokens) is unused. It also references many asset-catalog colors ("Background", "SurfaceElevated", "Accent", etc.) that may also be dead.
- **Recommendation:** Confirm with the owner, then delete AppColors.swift (and remove the file from project.yml). If kept intentionally as a reference, it should at minimum be flagged in a comment that it is unused, but the cleaner outcome is removal. Do not delete the underlying asset-catalog colors without checking they aren't referenced by Color("...") elsewhere first.
- **Risk if applied:** Low if grep is trusted: nothing references it, so deletion cannot change behavior. The only risk is if a non-Swift reference exists (e.g. storyboard/asset) — none expected here. Asset colors should be checked separately before removal.

### 🟠 MEDIUM — Legacy AppTypography enum is entirely dead code

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/DesignSystem/AppTypography.swift:6-46`
- **Problem:** A project-wide grep finds ZERO references to AppTypography outside its own definition. Every style here is .system(size:) based, which directly violates CLAUDE.md's 'no .font(.system(size:)) in views' rule and the DSKit migration. Since nothing uses it, the whole file is dead.
- **Recommendation:** Confirm with owner, then delete AppTypography.swift and remove it from project.yml. Typography now flows through AppFontTypography/DSKit text styles, so this legacy table is obsolete.
- **Risk if applied:** Low: no references exist, so removal is behavior-neutral.

### 🟠 MEDIUM — AppState.selectedTab, AppState.isLocked, and the AppTab enum are unused

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/App/AppState.swift:7`
  - `HumanProgram/App/AppState.swift:9`
  - `HumanProgram/App/AppState.swift:25-38`
- **Problem:** selectedTab (AppTab) and isLocked are leftover from the pre-DSKit tab-bar navigation model. CLAUDE.md states there is no tab bar (hub-root navigation), and grep confirms 0 usages of selectedTab, 0 usages of AppState.isLocked, and 0 usages of AppTab outside AppState.swift. Lock state is now owned by AppLockViewModel (lockVM in ContentView), so AppState.isLocked is a stale duplicate that could mislead future readers into thinking it is the source of truth.
- **Recommendation:** Remove AppState.selectedTab, AppState.isLocked, and the entire AppTab enum after confirming no UITest or other target references them. This shrinks AppState to its real responsibilities (viewingDate, streakStats, pendingInterstitial).
- **Risk if applied:** Low: removing unreferenced stored properties and an unused enum cannot change runtime behavior. Verify the test target doesn't reference AppTab before deleting.

### 🟠 MEDIUM — Identical template-fetch helpers duplicated across AppStartup and PageRefreshService

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/App/AppStartup.swift:62-97`
  - `HumanProgram/App/PageRefreshService.swift:32-85`
- **Problem:** fetchRecurringInputs, fetchBacklogInputs, and fetchScheduleInputs are defined twice with effectively identical bodies (same FetchDescriptors, same field-for-field mapping into RecurringTaskInput/BacklogTaskInput/ScheduleBlockInput). The only differences are cosmetic (AppStartup uses .flatMap, PageRefreshService uses a nested for-loop; AppStartup passes a Calendar arg it then ignores). This is exactly the kind of drift CLAUDE.md warns about: a field added to ScheduleBlockInput must be edited in two places or backups/refresh diverge.
- **Recommendation:** Extract the three fetch helpers into one shared place (e.g. a small TemplateInputs struct/enum or static funcs) and call it from both AppStartup and PageRefreshService. AppStartup.fetchRecurringInputs also takes a `calendar` parameter that is never used in its body — drop it when consolidating.
- **Risk if applied:** Low-to-medium: the bodies are semantically identical, so a careful extraction is behavior-preserving. Risk is only in transcription; keep the exact field mapping. Must verify HprgmBackupRoundTripTests and refresh tests still pass.

### 🟠 MEDIUM — Hardcoded lightBlue color duplicated and full-width button block near-duplicated across onboarding screens

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/App/AppInterstitialView.swift:13`
  - `HumanProgram/App/AppInterstitialView.swift:42-54`
  - `HumanProgram/App/PermissionsOnboardingView.swift:18`
  - `HumanProgram/App/PermissionsOnboardingView.swift:63-74`
- **Problem:** Both views privately define `let lightBlue = Color(red: 0.42, green: 0.69, blue: 0.99)` and both build a near-identical full-width primary button: Text(appFont(20)).foregroundStyle(.white).frame(maxWidth:.infinity).padding(.vertical,18).background(lightBlue, RoundedRectangle(14)).contentShape(...).buttonStyle(.plain).a11yTapBorder(RoundedRectangle(14)).padding(.horizontal,20).padding(.bottom,40). CLAUDE.md's #1 UI rule is 'reuse UI, never duplicate it' — the same color and the same button chrome appearing in two files is the drift this rule targets. The DSKit rule also forbids hardcoded Color(red:...) in views.
- **Recommendation:** Extract one shared primary-button component (e.g. an OnboardingPrimaryButton or a button style) and one shared accent color token, and reuse them in both screens (and any other interstitial). Prefer a DSKit/AppTheme-sourced accent over a raw Color(red:...).
- **Risk if applied:** Low: a shared button/color that reproduces the exact same modifiers and value is visually identical. Risk only if the extracted component subtly changes padding/contentShape; keep them exact.

### 🟢 LOW — FontChoice.previewFont ignores the global font-size scale (potential, document or accept)

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/DesignSystem/AppFont.swift:115-118`
  - `HumanProgram/Features/Settings/Customization/CustomizationView.swift:169`
- **Problem:** previewFont(size:) builds a Font directly from regularSpec.uiFont(size) with no FontSizeStep scale applied, unlike AppFontTypography.make which multiplies by `scale`. In the Customization picker (CustomizationView:169) the preview row therefore renders each font at a fixed 20pt regardless of the user's chosen font-size step. This is most likely intentional (a stable side-by-side typeface preview), but it is an undocumented divergence from how the same font renders everywhere else, so a reader could mistake it for a bug or 'fix' it and break the preview.
- **Recommendation:** Add a one-line comment on previewFont stating that it deliberately ignores the global size scale so previews stay a constant comparison size. No code change to behavior.
- **Risk if applied:** Low: adding a clarifying comment is behavior-neutral. Actually applying the scale WOULD change the picker's appearance, so that should NOT be done without owner intent.

### 🟢 LOW — Bitcount font regular and bold specs are identical, so `bold:` is a silent no-op for the default font

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/DesignSystem/AppFont.swift:93-96`
  - `HumanProgram/Core/DesignSystem/AppFont.swift:105-108`
- **Problem:** For the default font (.bitcount), regularSpec and boldSpec are byte-for-byte identical (same psName, same variations [AXIS_WGHT: 344], same multiplier). Lilex is similar (both specs WGHT:700). So calls like appFont(20, bold: true) and DSKit's `headline` (bld) render visually identical to regular for the default font. There are ~10 call sites relying on `bold: true` (PINEntryView, CalendarView, DailyTimeline, etc.) that therefore produce no visual emphasis on a fresh install. This may be an accepted property of Bitcount (a single-weight grid font), but it means 'bold' emphasis silently disappears for the default typeface.
- **Recommendation:** Confirm with owner whether Bitcount is intentionally single-weight. If so, add a comment noting bold==regular for bitcount/lilex so future readers don't chase a 'bold not working' bug. If emphasis is desired, bump the wght axis in boldSpec for bitcount. No change without owner intent since it alters the default look.
- **Risk if applied:** Medium if changed: bumping bitcount's bold weight would visibly alter the default font everywhere bold is used. Safe action is documentation only.

### 🟢 LOW — AppInterstitialView and PermissionsOnboardingView use raw Color(red:...) and appFont instead of DSKit tokens

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/App/AppInterstitialView.swift:13`
  - `HumanProgram/App/AppInterstitialView.swift:35`
  - `HumanProgram/App/AppInterstitialView.swift:67`
  - `HumanProgram/App/PermissionsOnboardingView.swift:18`
  - `HumanProgram/App/PermissionsOnboardingView.swift:31`
- **Problem:** CLAUDE.md: 'No hardcoded Color(hex:)/.font(.system(size:)) in views' and 'new or migrated UI must use DSKit'. These two views use raw Color(red:0.42,...) for the button and Image(systemName:).font(.system(size: 90)) in the logo fallback (AppInterstitialView.swift:67). The Text uses appFont(...) — which is justified by the inline comment (DSText renders leading-aligned, so plain Text is needed for centered multi-line), so that specific deviation is documented. The raw color and .system(size: 90) glyph are not justified.
- **Recommendation:** Route the accent color through AppTheme/DSKit appearance and the fallback glyph through DSImageView(size:) so these onboarding screens conform to the same token rules as the rest of the app. The centered-Text deviation can stay (it is documented).
- **Risk if applied:** Low: swapping a hardcoded color for an equivalent theme token and a .system(size:) glyph for DSImageView should be pixel-equivalent if sizes match. Verify the fallback (no PenguinIcon asset) still renders at the same size.

### 🟢 LOW — Trailing `_ = todayPage // used above` is noise

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/App/AppStartup.swift:35-41`
  - `HumanProgram/App/AppStartup.swift:59`
- **Problem:** todayPage is assigned from getOrCreate but its only later use is the side effect of creating the page; the value itself is never read, so the author added `_ = todayPage // used above` to silence the unused-warning. The getOrCreate call already has the needed side effect, so binding it to a name and then discarding it is confusing.
- **Recommendation:** Either call getOrCreate without binding (`_ = try pageRepo.getOrCreate(...)`) or, if the binding aids readability, drop the trailing `_ = todayPage` line and the misleading 'used above' comment. Purely cosmetic.
- **Risk if applied:** Low: removing an unused binding/discard line is behavior-neutral as long as the getOrCreate call is preserved.

### 🟢 LOW — appFont/appUIFont/appScaledSize re-read UserDefaults on every call inside view bodies

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/DesignSystem/AppFont.swift:135-138`
  - `HumanProgram/Core/DesignSystem/AppFont.swift:145-148`
  - `HumanProgram/Core/DesignSystem/AppFont.swift:151-155`
- **Problem:** appFont(_:bold:) is called from 131 call sites, all inside SwiftUI view bodies. Each call does UserDefaults.standard.string(forKey:) plus FontChoice.from(...) and constructs a UIFontDescriptor/UIFont. appScaledSize and appUIFont do the same. Because these run inside body, they re-read UserDefaults and rebuild a UIFont on every render of every affected view. This is intentional (the doc-comment says it re-reads so it updates when the font changes), but UserDefaults reads + UIFont construction on a hot render path are avoidable. The comment even notes that without an @AppStorage the value 'isn't reliably observed', which is why it polls.
- **Recommendation:** No behavior change needed, but consider memoizing the resolved FontChoice/UIFont keyed by (choice, size, bold) so repeated renders reuse cached fonts, while still invalidating when settings.fontChoice changes (e.g. via a small cache cleared on a NotificationCenter/UserDefaults-didChange observer). Low priority given font construction is cheap, but it is the only thing in this area that runs per-render.
- **Risk if applied:** Medium if done carelessly: a cache that fails to invalidate on font/size change would make the font picker appear broken. Safe only with correct invalidation; otherwise leave as-is.

### 🟢 LOW — AppStartup recalculates streaks by fetching ALL pages and mapping every launch

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/App/AppStartup.swift:52-57`
- **Problem:** On every app start, AppStartup fetches every DailyPage (pageRepo.fetchAll()), maps all of them into DailyCompletionSnapshot, and recomputes streaks. This grows linearly with total history (every day the app has been used) and runs unconditionally at launch on the main actor. For a long-lived personal app this set only grows. It is not a correctness bug — StreakCalculator needs the history — but it is unbounded work on the launch path.
- **Recommendation:** Acceptable for now given personal-app scale. If launch latency becomes an issue, consider a bounded fetch (only pages within the longest plausible streak window, or a stored running streak summary) rather than fetching the entire page table. No change required today; flag for future.
- **Risk if applied:** Medium: streak math is invariant-sensitive (CLAUDE.md calls streak/completion a core invariant). Any bounded-fetch optimization must be validated against StreakCalculator tests to avoid wrong streaks; leaving it as-is is safest.

### 🟢 LOW — ContentView body mixes navigation root, three onboarding flows, and lock gate in one ~150-line view

- **Category:** readability | **Effort:** medium
- **Locations:**
  - `HumanProgram/App/ContentView.swift:9-153`
- **Problem:** ContentView owns the NavigationStack, the StartupCover enum + selection logic, the onboarding step machine (welcome→terms→tutorial→permissions), interstitial mapping, and three finish-* callbacks. It is coherent but dense, and the onboarding step state machine (onboardingStep + finishOnboarding/finishPermissions/finishInterstitial) is a self-contained concern that could live in its own type for clarity. The finishInterstitial comment (ContentView.swift:129-132) also documents a fragile cross-write: FactoryResetView writes hp.onboarded in UserDefaults but @AppStorage 'isn't reliably observed', so it is re-cleared here — a coupling that is easy to break.
- **Recommendation:** Optionally extract the onboarding step machine (state + the three finish handlers + onboardingView) into a small OnboardingFlow view/coordinator so ContentView focuses on the nav root and cover selection. Not required for correctness; improves readability and isolates the fragile onboarded-flag handshake. Keep the documented re-clear behavior.
- **Risk if applied:** Medium: this view governs first-launch and post-reset gating, which is high-stakes to refactor. The fragile @AppStorage/UserDefaults handshake must be preserved exactly. Only refactor with thorough manual testing of fresh-install and factory-reset paths.


---

## Today feature (TodayView, TodayViewModel, DailyTimeline, TaskDetailView)

> The Today feature is functionally rich and the gesture/keyboard plumbing is carefully reasoned (the inline comments document hard-won fixes). The biggest health issues are: (1) TodayView is a ~600-line monolith mixing top bar, timeline, task-list reorder/swipe state machine, add-task field, and exercise section — several of these are independent units that should be extracted, and the reorder/swipe machinery is a near-duplicate of the Schedule editor that CLAUDE.md says should be shared via EditorRowInteractions; (2) repeated per-body recomputation of derived collections (sortedTasks, scheduleItems, placedLabels) and per-render allocation of DateFormatter/Calendar; (3) two competing async loadPage paths (the viewingDate setter fires its own Task while callers also await loadPage) that can race and double-fetch; (4) several CLAUDE.md convention drifts — hardcoded Color(red:green:blue:) and .font(.system(size:)) in views, a hand-rolled date-picker sheet button instead of shared DSKit components, and add-task using appFont/TextField rather than the shared input path. None of these are correctness-critical, and most fixes are low-risk refactors, but the duplication and per-render cost are the durable concerns.

### 🔴 HIGH — Reorder + swipe-to-delete state machine duplicates the Schedule editor instead of reusing EditorRowInteractions

- **Category:** near-duplication | **Effort:** large
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:294-478`
  - `HumanProgram/Features/Today/TodayView.swift:30-38`
- **Problem:** TodayView hand-implements the entire hold-to-reorder + swipe-to-delete interaction (dragInfo, reorderRowFrames, swipeOpenId/swipeDragId/swipeDragX, beginReorder/endReorder/swipeBegan/swipeChanged/swipeEnded, projectedIndex/shiftOffset/swipeOffset, plus the clipped trash-lane row layout). CLAUDE.md states these recognizers and patterns 'now live in Features/Settings/Components/EditorRowInteractions.swift (generic over the row's Hashable id) and are SHARED — the Exercise editor reuses them. Build new editable-row editors on these, don't re-derive.' TodayView only reuses the low-level ReorderRecognizer/SwipePanRecognizer/RowFrameKey but re-derives ALL the surrounding state and geometry (the trashWidth=72, taskRowHeight=52 magic numbers, the spring response 0.3/damping 0.82, the -trashWidth/2 snap threshold, the 0.2 rubber-band factor) that the Schedule editor already encodes. This is exactly the drift CLAUDE.md warns about: a tweak to swipe behavior must now be made in two places.
- **Recommendation:** Extract the reorder/swipe state + geometry into the shared EditorRowInteractions helper (or a reusable EditableRowList view) parameterized by row id, height, and the commit closures, and have both Schedule and Today consume it. Verify gesture behavior is pixel/timing identical afterward.
- **Risk if applied:** Medium-high — the gesture choreography is delicate (documented as 'took many iterations'). A faithful extraction is behavior-preserving, but any divergence in thresholds/animations would be user-visible. Worth doing but must be tested against the Schedule editor for parity.

### 🟠 MEDIUM — viewingDate setter fires its own loadPage Task while callers also await loadPage — racy double-load

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Today/TodayViewModel.swift:16`
  - `HumanProgram/Features/Today/TodayViewModel.swift:21`
  - `HumanProgram/Features/Today/TodayView.swift:495`
- **Problem:** The `viewingDate` setter (TodayViewModel.swift:16-23) unconditionally spawns `Task { await loadPage() }` on every assignment. Day-nav methods (goToPreviousDay/goToNextDay/goToToday/jumpTo) all set viewingDate, so each navigation kicks off an unstructured, un-cancellable load. Meanwhile commitAdd (TodayView.swift:495) does `Task { await vm.addManualTask(); await vm.loadPage() }`, and updateTask also calls loadPage internally. Two concurrent loadPage calls can interleave: both set isLoading, both fetch templates and call getOrCreate, and the later-finishing one wins regardless of which navigation it belongs to. With fast taps (prev/next) a stale page can land. Because everything is @MainActor the data won't corrupt, but `page` can briefly desync from `viewingDate` and the redundant fetches are wasted work.
- **Recommendation:** Make loading explicit and serialized: drop the implicit `Task { await loadPage() }` from the setter and have navigation methods await a single loadPage, or store and cancel the previous load Task before starting a new one (keep a `private var loadTask: Task&lt;Void, Never&gt;?`). Do NOT change the relock-on-leave side effect. This is a behavior-preserving structural change but touches the navigation flow, so verify day-switching and add-task still refresh.
- **Risk if applied:** Medium — reorders when loadPage runs; if done carelessly a navigation could stop refreshing. Must keep relockCurrentIfPast firing before the date changes.

### 🟠 MEDIUM — Hardcoded Color(red:green:blue:) and .font(.system(size:)) in views violate the DSKit 'no hardcoded color/font' rule

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:216`
  - `HumanProgram/Features/Today/TodayView.swift:174`
  - `HumanProgram/Features/Today/TodayView.swift:201`
  - `HumanProgram/Features/Today/TodayView.swift:551`
  - `HumanProgram/Features/Today/DailyTimeline.swift:34`
  - `HumanProgram/Features/Today/TaskDetailView.swift:84`
- **Problem:** CLAUDE.md: 'No hardcoded Color(hex:) / .font(.system(size:)) in views.' TodayView.swift:216 uses `Color(red: 0.18, green: 0.62, blue: 0.32)` for the complete-day green; DailyTimeline.swift:34 hardcodes the calendar-lane blue `Color(red: 0.46, green: 0.67, blue: 0.96)`. `.font(.system(size:))` appears at TodayView.swift:174 (chevron 18), :201 (navButton glyph), :551 (PastLockButton icon). TaskDetailView.swift:84 uses `.font(appFont(18))` and DSText elsewhere is mixed with raw Text. These are real, semantic colors/sizes that should be DSKit tokens (or at least named constants in the design system) so the theme owns them.
- **Recommendation:** Move the complete-day green and calendar-lane blue into AppColors/DesignSystem tokens (or DSKit theme) and reference by name; route the icon sizes through the DSKit image/typography tokens where a token exists. Note the timeline uses appFont(13) intentionally for the pixel font in the gutter — leave that. Purely a token swap, no visual change if the token equals the current literal.
- **Risk if applied:** Low if the token resolves to the identical color/size; medium if a token with a slightly different value is substituted (would shift the visuals). Keep exact values.

### 🟠 MEDIUM — TodayView body recomputes sortedTasks / scheduleItems / DateFormatter every render

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:228-232`
  - `HumanProgram/Features/Today/TodayView.swift:159-167`
  - `HumanProgram/Features/Today/TodayViewModel.swift:62-67`
  - `HumanProgram/Features/Today/TodayView.swift:240`
- **Problem:** `longDate` (TodayView.swift:228) allocates a fresh DateFormatter on every access, and it's read in titleRow which is in the body. The 15s ticker (`now`) plus the keyboard-spacer animations re-render the whole body frequently, so the formatter is rebuilt repeatedly — DateFormatter creation is one of the documented hot-path costs to avoid. `scheduleItems` (159-167) sorts and maps `vm.page?.scheduleBlocks` every body pass, and `vm.sortedTasks` (TodayViewModel.swift:62) sorts the tasks relationship every access; sortedTasks is read multiple times per render (taskList ForEach, taskRow's firstIndex lookup, shiftOffset, endReorder). On the timeline side, `scheduleItems + calendarItems` is recomputed and re-sorted inside DailyTimeline (placedLabels sorts again).
- **Recommendation:** Cache the DateFormatter in a static/let (or use Date.FormatStyle). Memoize sortedTasks/scheduleItems off the page rather than recomputing as computed properties read many times per body, or compute them once per body into a local. None of this changes output, only render cost.
- **Risk if applied:** Low — pure memoization; same values produced. Just ensure the cached formatter uses a fixed locale/calendar to match current behavior.

### 🟠 MEDIUM — TodayView is a ~600-line monolith — top bar, timeline, task list, add field, and exercise should be separate views

- **Category:** readability | **Effort:** large
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:11-538`
- **Problem:** TodayView holds 16+ @State/@FocusState properties spanning four unrelated concerns (calendar loading, keyboard spacer, reorder drag state, swipe state, add-task state, date picker) and defines the top bar, title row, schedule section, the full reorder/swipe task list, the add-task field, and the exercise reference section all in one type. The reorder/swipe handlers and geometry alone are ~150 lines. This makes the body's invalidation surface large (any of those states re-renders everything) and the file hard to navigate. CLAUDE.md's reuse rule and the 'overly long views should be split' health goal both point at extraction.
- **Recommendation:** Extract at least: the task list + reorder/swipe state into a reusable EditableTaskList view (shared with Schedule per the other finding), the exercise reference into ExerciseReferenceSection, and the timeline section is already DailyTimeline (good). Keep TodayView as the coordinator. Pure structural refactor.
- **Risk if applied:** Medium — moving @State across view boundaries can change identity/animation timing; must verify gestures, keyboard nudge, and add-task focus still behave identically.

### 🟢 LOW — Error handling is uniformly print-and-swallow across every ViewModel mutation

- **Category:** best-practice | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Today/TodayViewModel.swift:77-79`
  - `HumanProgram/Features/Today/TodayViewModel.swift:99-101`
  - `HumanProgram/Features/Today/TodayViewModel.swift:136-139`
  - `HumanProgram/Features/Today/TodayViewModel.swift:157-160`
  - `HumanProgram/Features/Today/TodayViewModel.swift:166-169`
- **Problem:** Every repository call is wrapped in do/catch that only `print(...)`. A failed toggle/add/delete/reorder/lock leaves the UI showing the pre-mutation state with no signal to the user and no surfaced error — e.g. if toggleTask throws, the checkbox the user tapped stays in its old state silently, or worse the optimistic `page` returned vs not-returned paths diverge. For a snapshot-protection-critical app, a silently-swallowed lock/unlock failure could leave a past page in an unexpected lock state. This is consistent across the VM (so it's a pattern, not a one-off), which is why it's best-practice rather than a single bug.
- **Recommendation:** At minimum funnel errors through one shared handler and consider surfacing user-facing failures for the lock/unlock and reorder paths (which touch the snapshot invariant). No behavior change required to ship; this is a robustness recommendation, so apply cautiously.
- **Risk if applied:** Low to read/diagnose; medium if you add user-facing error UI (new surface). Keep the catch sites non-throwing to avoid changing call signatures.

### 🟢 LOW — didLoad guard in TaskDetailView means an external task change won't refresh the open detail; relies on navigationDestination identity

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TaskDetailView.swift:67-72`
  - `HumanProgram/Features/Today/TaskDetailView.swift:18`
- **Problem:** TaskDetailView seeds title/notes from the task only once via the `didLoad` flag in onAppear. The task is passed as a `let` and the editor mutates local @State, calling onSave on Done. This is fine for the normal flow, but because navigationDestination(item:) is keyed on the DailyPageTask (an @Model), if the same view instance were reused for a different task (identity reuse) the didLoad guard would keep the stale title/notes. Today it works because navTask changes push a fresh view, but the guard couples correctness to navigation identity rather than the task id.
- **Recommendation:** Either key the seeding on task.id (re-seed when the id changes, e.g. via .onChange(of: task.id)) or document that the view is always freshly constructed per task. Low risk; defensive.
- **Risk if applied:** Low — adding an id-based re-seed only changes behavior in the (currently non-occurring) reuse case; the normal flow is unchanged.

### 🟢 LOW — TodayDatePicker sheet hand-rolls its button/background instead of shared DSKit components

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:574-608`
  - `HumanProgram/Features/Today/TodayView.swift:593-601`
- **Problem:** The 'Go' button (593-601) hand-builds a capsule with `Color.primary.opacity(0.08)` background and manual padding rather than using a shared DSButton/button style. CLAUDE.md pushes reuse of one shared component for any repeated visual (button style, sheet layout) and DSKit for new UI. The graphical DatePicker with `.tint(weekdaySelectedColor)` is a one-off styling not shared with the rest of the date-selection UI.
- **Recommendation:** Use the app's shared button style / DSButton for the Go action and, if a shared date-jump picker exists elsewhere (Calendar feature has date selection), consolidate. Low priority and cosmetic-internal.
- **Risk if applied:** Low — visual styling only; verify the button still reads the same.

### 🟢 LOW — Item-label times in DailyTimeline use fixed 24h hhmm — possible inconsistency with clockString rule for displayed times

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/DailyTimeline.swift:96`
  - `HumanProgram/Features/Today/DailyTimeline.swift:152-155`
- **Problem:** CLAUDE.md says every DISPLAYED clock time goes through clockString(...), but explicitly exempts 'the Today timeline gutter'. The hour-column labels (line 83) and now-pill (116) are the gutter and are correctly fixed 24h. However the per-item LABEL on line 96 renders '\(title), \(hhmm(start))–\(hhmm(end))' using the same fixed-24h hhmm — these are displayed event/block clock times sitting in the open label area, not the gutter, so a user with 12h time format set will see schedule/calendar block times in 24h here while seeing them in 12h elsewhere (e.g. Calendar detail). This is a gray area (it's inside the timeline square) but reads as a drift from the clockString convention.
- **Recommendation:** Decide deliberately: if the item labels should follow the 12h/24h setting, route them through clockString(minutesOfDay:) (keeping the gutter on the fixed hhmm); if they're intended to stay 24h to match the gutter visually, add a one-line comment citing the exemption so it doesn't read as an oversight. Do NOT change the gutter labels or now-pill.
- **Risk if applied:** Low — if changed, only the label string format changes; verify against the 12h-format setting and that the label width still fits.

### 🟢 LOW — Dead / unused ViewModel state: showDatePicker, showAddTask, isLoading not consumed by the view

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayViewModel.swift:11`
  - `HumanProgram/Features/Today/TodayViewModel.swift:12`
  - `HumanProgram/Features/Today/TodayViewModel.swift:10`
- **Problem:** TodayViewModel exposes `showDatePicker` (line 11) and the view instead uses its own `@State private var showDatePicker` (TodayView.swift:15) — the VM property is never read by the view. `showAddTask` (line 12) is set inside addManualTask but the view tracks add state with its own `addingTask`/`addFocused`; nothing reads vm.showAddTask. `isLoading` (line 10) is set in loadPage but no view reads it (no loading indicator). These are leftover stubs that imply state that isn't wired.
- **Recommendation:** Remove the unused `showDatePicker`, `showAddTask`, and `isLoading` from the VM (or wire isLoading to a real indicator if intended). Confirm nothing else in the codebase references them before deleting.
- **Risk if applied:** Low — grep-confirm no external readers, then remove; pure cleanup.

### 🟢 LOW — taskRow does an O(n) firstIndex lookup per row → O(n^2) per render

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:333`
  - `HumanProgram/Features/Today/TodayView.swift:464-466`
- **Problem:** Inside `taskRow` (called once per row in the ForEach), line 333 does `vm.sortedTasks.firstIndex(where: { $0.id == task.id })`, which both re-sorts (sortedTasks is a computed sort) and linearly scans. shiftOffset (462-469) does the same firstIndex again. For N tasks this is O(N^2) work per body render, repeated on every ticker tick / keyboard animation frame. Task lists are usually short so impact is small, but it scales badly and re-sorts unnecessarily.
- **Recommendation:** Enumerate the sorted array once (e.g. `ForEach(Array(vm.sortedTasks.enumerated()), ...)`) and pass the index into taskRow, or precompute an `[id: index]` dictionary once per render. Behavior-identical.
- **Risk if applied:** Low — same ordering and indices, just computed once.

### 🟢 LOW — projectName(for:) fetches ALL BacklogItems on every call and scans linearly — repeated SwiftData fetch in a view-driven path

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayViewModel.swift:202-206`
- **Problem:** projectName fetches the entire BacklogItem table (`context.fetch(FetchDescriptor&lt;BacklogItem&gt;())`) and then does `.first(where:)` to find one item by id. It's called from TodayView's navigationDestination when opening TaskDetailView. The fetch is unfiltered (loads every backlog item) when a predicated fetch for the single id would suffice, and the linear scan is O(n). It's only on detail-open so not hot, but it's a wasteful full-table load.
- **Recommendation:** Use a FetchDescriptor with a #Predicate on the sourceId (or fetch by id), returning at most one item. Behavior-identical (still returns the project name or 'None').
- **Risk if applied:** Low — narrower fetch returns the same item; just ensure the predicate matches the id type.

### 🟢 LOW — exerciseRoutine items re-sorted on every render; ExerciseRepository re-instantiated per loadPage

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:511`
  - `HumanProgram/Features/Today/TodayViewModel.swift:97-98`
- **Problem:** exerciseSection sorts `routine.items.sorted { $0.sortOrder &lt; $1.sortOrder }` inside the ForEach in the body (TodayView.swift:511), so it re-sorts on every body pass (ticker, keyboard animations). In loadPage (TodayViewModel.swift:97) a new `ExerciseRepository(context:)` is allocated each call rather than held as a stored property like pageRepo/backlogRepo, which is an inconsistency with how the other repos are owned.
- **Recommendation:** Sort the exercise items once when the routine is loaded (or expose a pre-sorted computed property on the VM), and store the ExerciseRepository as a let in init for consistency with pageRepo/backlogRepo. No behavior change.
- **Risk if applied:** Low — same sorted output, same repository behavior.

### 🟢 LOW — Two independent loadPage triggers + commitAdd's manual loadPage make the add/load flow hard to follow

- **Category:** logic-structure | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:491-498`
  - `HumanProgram/Features/Today/TodayViewModel.swift:142-152`
- **Problem:** addManualTask (VM:142) already clears newTaskTitle and sets showAddTask=false, but the view's commitAdd (TodayView.swift:491) sets vm.newTaskTitle = t, calls addManualTask, then ALSO calls loadPage, and separately clears its own `newTask` and `addingTask`. State is split between the view (newTask, addingTask) and the VM (newTaskTitle, showAddTask) for the same logical 'adding a task', so two sources of truth track the same thing. addManualTask doesn't update `page` itself (it relies on the follow-up loadPage), unlike toggleTask/deleteTask/reorderTasks which return/refresh page directly — an inconsistency in how mutations refresh state.
- **Recommendation:** Pick one owner for add-task UI state (the VM already has newTaskTitle/showAddTask — either use them or remove them and keep it all in the view), and make addManualTask refresh `page` consistently with the other mutators so the explicit loadPage isn't needed. Behavior-preserving cleanup.
- **Risk if applied:** Low-medium — consolidating state could change when the field clears/closes; test the add + tap-out + return flows.

### 🟢 LOW — Add-task field uses raw TextField + appFont instead of the shared AppTextField input path used in TaskDetailView/editors

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:259-267`
  - `HumanProgram/Features/Today/TaskDetailView.swift:32-40`
- **Problem:** The inline 'New task' field (TodayView.swift:259) is a bare SwiftUI `TextField` with `.font(appFont(17))`, while TaskDetailView and the planning editors standardize on `AppTextField(... fontSize: appScaledSize(...))`. CLAUDE.md warns specifically that mixing a raw TextField (does not apply the global font scale) with the scaled DSKit/AppTextField path causes size drift between contexts. The add field also won't pick up the global font-scale setting that AppTextField honors.
- **Recommendation:** Use AppTextField with appScaledSize for the add-task field so it matches the rest of the app's text-size behavior, or document why raw TextField is required here (the CLAUDE.md keyboard-gap note says title fields must be the same TextField type for frame-measurement; if that's the reason, add a comment). Verify font size matches the read-mode task row.
- **Risk if applied:** Low-medium — switching the field type could affect the keyboard-nudge frame measurement the comments rely on; test the keyboard safety-gap still works.

### 🟢 LOW — Magic numbers and tuned offsets scattered with no shared constants (28/-8 pill, -7/-6/-10 timeline, 66x32 pill)

- **Category:** sloppy | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:101-102`
  - `HumanProgram/Features/Today/TodayView.swift:549`
  - `HumanProgram/Features/Today/DailyTimeline.swift:87`
  - `HumanProgram/Features/Today/DailyTimeline.swift:111`
  - `HumanProgram/Features/Today/DailyTimeline.swift:123`
- **Problem:** Many hand-tuned literals carry behavior: the past-lock pill aligns with `.padding(.trailing, 28)` / `.padding(.top, -8)` (TodayView.swift:101-102) explicitly derived from 'outer bar pad 12 + inner group pad 16 = 28', meaning if those paddings change this silently misaligns (the very 'never eyeball positions' trap CLAUDE.md calls out — here the offset is computed from two other literals rather than a shared layout path). DailyTimeline has `y - 7`, `cy - 10`, `x: -6`, the 66x32 capsule, timeColW 52 / laneW 25 with prose explaining each. These are individually justified but not centralized, so they drift when neighbors change.
- **Recommendation:** Where one literal is derived from others (the 28 = 12+16 pill alignment), compute it from the source constants or pull both into named layout constants so the relationship is enforced, not commented. Leave the pixel-font centering offsets as-is but consider grouping them as named constants. No behavior change.
- **Risk if applied:** Low if values are preserved exactly; medium if refactoring the pill alignment changes the effective number — verify the pill still lines up with the calendar button edge.


---

## Calendar feature (Month/Week/Day/List) — CalendarView.swift, CalendarEventDetailSheet.swift, CalendarSourceSettingsView.swift

> CalendarView.swift is a 1279-line monolith holding four full sub-views (Month/Week/Day/List), an event-detail navigation flow, all the date-grid math, and the entire Add/Edit-event form (AddCalendarEventView, lines 1058-1279) in one file. It is functional and the date logic is mostly correct (weekday encoding 1=Sun is respected; the timeline gutters are intentionally fixed-24h per spec). But it carries real code-quality debt: a large block of dead code (three unused changeMonth/changeWeek/changeDay nav helpers and the unused horizontalSwipe extension left over from the pre-TabView paging rebuild), heavy per-render recomputation (events.filter + sort recomputed for every day cell and every page in the ±2yr TabView windows, an O(events) scan per month-grid cell, repeated Calendar.current/weekDays derivations), and pervasive convention violations: the whole file uses appFont(...)/Color.primary/.font(.system(size:)) rather than DSKit (DSText/.dsTextStyle), event clock times use locale .dateTime.hour().minute() instead of the app's clockString(...) helper, and the two permission states plus several header/nav rows are near-duplicated. CalendarSourceSettingsView is the cleanest of the three (proper DSKit + SettingsScreen). CalendarEventDetailSheet is mid: clean structure but legacy fonts/colors and one clock-time convention miss. None of the issues are crashes; the highest-value safe fixes are deleting the dead nav code and centralizing the per-render event lookups.

### 🟠 MEDIUM — Event clock times bypass the app's clockString(...) helper

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:994`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1035`
  - `HumanProgram/Features/Calendar/CalendarEventDetailSheet.swift:127`
- **Problem:** CLAUDE.md requires every DISPLAYED ##:## clock time (which explicitly includes event read-outs, and excludes ONLY the fixed-24h Today/Calendar timeline gutters) to go through clockString(...), which reads settings.timeFormat. These three event-time displays instead use SwiftUI's locale-driven .dateTime.hour().minute(). That follows the device locale, not the app's own 12h/24h setting, so toggling the app setting won't change these labels — the exact desync the helper exists to prevent. A clockString(date:) overload already exists (AppFont.swift:182). Note these are the event ROW/BLOCK/DETAIL times, NOT the hour-gutter labels (hourLabel at line 884 and nowTimeString at 890 are correctly left fixed-24h per spec).
- **Recommendation:** Replace each `Text("\(event.startDate, format: .dateTime.hour().minute()) – ...")` with the existing helper, e.g. `Text("\(clockString(date: event.startDate)) – \(clockString(date: event.endDate))")`, and the single-time DayEventBlock with `Text(clockString(date: event.startDate))`. Do NOT touch hourLabel/nowTimeString (those are the gutters).
- **Risk if applied:** Low — swaps formatter to the project's canonical one; only changes the string when the app's 12h/24h setting differs from device locale, which is the intended behavior. No layout change.

### 🟠 MEDIUM — Entire Calendar feature uses legacy fonts/colors instead of DSKit

- **Category:** claude-md-inconsistency | **Effort:** large
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:105`
  - `HumanProgram/Features/Calendar/CalendarView.swift:161`
  - `HumanProgram/Features/Calendar/CalendarView.swift:254`
  - `HumanProgram/Features/Calendar/CalendarView.swift:949`
  - `HumanProgram/Features/Calendar/CalendarEventDetailSheet.swift:52`
  - `HumanProgram/Features/Calendar/CalendarEventDetailSheet.swift:90`
  - `HumanProgram/Features/Calendar/CalendarEventDetailSheet.swift:171`
- **Problem:** CLAUDE.md: 'new or migrated UI must use DSKit (DSText/.dsTextStyle), not AppColors/AppTypography' and 'No hardcoded .font(.system(size:)) in views'. CalendarView and CalendarEventDetailSheet are pervasively built on appFont(...) (a legacy Font helper), Color.primary/.secondary/.accentColor, and raw .font(.system(size: 18)) (e.g. topBar chevron line 105, the plus button line 113, the metadata icons in the detail sheet). CalendarSourceSettingsView, by contrast, is correctly migrated (DSText/.dsTextStyle/DSImageView). The two calendar screens are still on the legacy path. This is a known-incomplete migration rather than a fresh regression, but it is the single most widespread convention gap in this area.
- **Recommendation:** Track Calendar + CalendarEventDetailSheet as not-yet-DSKit-migrated. When migrated, replace appFont/.font(.system) text with DSText().dsTextStyle(...) and the SF Symbols with DSImageView, matching the CalendarSourceSettingsView pattern. This is a large migration, not a spot fix; flag, don't quietly half-convert.
- **Risk if applied:** Medium if attempted wholesale — DSKit token sizes/colors won't pixel-match appFont, so a careless swap reflows the dense timeline/grid. Should be done deliberately screen-by-screen with visual checks, not as a mechanical replace.

### 🟠 MEDIUM — Dead code: three unused month/week/day nav helpers

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:263`
  - `HumanProgram/Features/Calendar/CalendarView.swift:267`
  - `HumanProgram/Features/Calendar/CalendarView.swift:271`
- **Problem:** changeMonth(_:), changeWeek(_:), and changeDay(_:) are defined but never called anywhere in the file (confirmed by grep — the only matches are the definitions themselves). They are leftovers from the pre-TabView navigation model; paging is now driven entirely by monthPage/weekPage/dayPage TabViews and their onChange handlers. Dead code misleads future readers into thinking month/week navigation flows through these and bloats the already-1279-line file.
- **Recommendation:** Delete all three functions. They have no callers, so removal cannot change behavior.
- **Risk if applied:** None — purely unreferenced private functions; the compiler will confirm there are no callers.

### 🟠 MEDIUM — Dead code: unused horizontalSwipe View extension

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:911`
  - `HumanProgram/Features/Calendar/CalendarView.swift:915`
- **Problem:** The private View extension horizontalSwipe(_:) (lines 911-924) has no call sites (grep shows only its definition). It was the old swipe-paging gesture, superseded by the TabView finger-tracked paging. It carries a full DragGesture implementation and a doc comment, all unreachable.
- **Recommendation:** Delete the entire private extension View { horizontalSwipe ... } block. No view applies this modifier.
- **Risk if applied:** None — unreferenced extension method on View; safe to remove.

### 🟠 MEDIUM — Per-render event filtering/sorting recomputed for every cell and every page

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:298`
  - `HumanProgram/Features/Calendar/CalendarView.swift:722`
  - `HumanProgram/Features/Calendar/CalendarView.swift:737`
  - `HumanProgram/Features/Calendar/CalendarView.swift:455`
- **Problem:** eventsForDay/timedEventsForDay/allDayEventsForDay each do a full O(events) filter (plus a sort) and are called repeatedly inside body-building loops, with no memoization. In monthGrid, every visible day cell runs `events.contains { cal.isDate($0.startDate, inSameDayAs: day) }` (line 298) — ~42 cells × O(events) per grid, and the TabView builds several month pages. In weekTimeline (line 455) timedEventsForDay(day) is called once per day column inside a ForEach. In agendaView the list spans a ±2yr window. Because these are plain methods (not cached), they re-run on every body invalidation (selectedDate change, scroll, etc.). For a heavy calendar this is repeated linear scanning that could be a single Dictionary&lt;DayStartDate, [EKEvent]&gt; bucketed once per loadEvents().
- **Recommendation:** After loadEvents(), bucket events once into [Date: [EKEvent]] keyed by startOfDay (and a second pass for all-day overlap), sorted, stored in @State. Have eventsForDay/timedEventsForDay/allDayEventsForDay and the monthGrid dot check read from that dictionary (O(1) lookup) instead of re-filtering. Keep the same return shapes so callers are unchanged.
- **Risk if applied:** Low-to-medium — behavior identical if the bucketing mirrors the current filter predicates exactly (note allDayEventsForDay uses an OVERLAP test, not same-day, so it needs its own bucketing). Must invalidate the cache in loadEvents(). Logic-equivalent, no UI change.

### 🟠 MEDIUM — CalendarView is a 1279-line monolith mixing four views plus the full add/edit form

- **Category:** readability | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:23`
  - `HumanProgram/Features/Calendar/CalendarView.swift:226`
  - `HumanProgram/Features/Calendar/CalendarView.swift:356`
  - `HumanProgram/Features/Calendar/CalendarView.swift:495`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1058`
- **Problem:** One file holds: the CalendarView container with 14 @State properties and a tangled sheet/navigationDestination/edit-handoff flow (lines 80-101), four full sub-screens (monthView 226, weekView 356, dayView 495, agendaView 624), all the grid/timeline math, three small private row structs (MonthDayCell, EventRowView, DayEventBlock), AND the entire ~220-line AddCalendarEventView add/edit form (1058-1279) with its own nested RepeatRule/AlertOption enums and menuRow helper. This is hard to navigate and review; the add/edit form in particular is an independent screen that has no reason to live in CalendarView.swift.
- **Recommendation:** Split into files without behavior change: move AddCalendarEventView (+ its enums) to AddCalendarEventView.swift; optionally move MonthDayCell/EventRowView/DayEventBlock to a CalendarRows.swift, and the four sub-views to extensions in separate files. Remember to register new files in project.yml and re-run xcodegen. Pure relocation, no logic edits.
- **Risk if applied:** Low — moving types/extensions between files in the same module/target is behavior-neutral, but requires updating project.yml + xcodegen (per CLAUDE.md) or the build breaks. Keep access levels (private structs stay private if kept in-file; if moved out they may need fileprivate→internal).

### 🟢 LOW — selectedCalendarIds re-read from UserDefaults on every access (no shared constant key)

- **Category:** best-practice | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:54`
  - `HumanProgram/Features/Calendar/CalendarView.swift:718`
  - `HumanProgram/Features/Calendar/CalendarSourceSettingsView.swift:17`
- **Problem:** The UserDefaults key string "selectedCalendarIds" is duplicated as a magic string in CalendarView (line 55) and CalendarSourceSettingsView (line 17 defines a local selectedIdsKey constant). They must stay in sync by hand; a typo in one place silently decouples the source picker from what Calendar reads. Also `selectedCalendarIds` is a computed property that hits UserDefaults on every read — it's read inside loadEvents (718) which is fine, but there is no single source of truth for the key.
- **Recommendation:** Define the key once in a shared place (e.g. a static constant alongside the other preference keys) and reference it from both files. No behavioral change; just removes the drift risk between the picker and the reader.
- **Risk if applied:** None — replacing two identical literals with one shared constant of the same value.

### 🟢 LOW — Add-event view re-fetches all calendars on every appear, default-selects silently

- **Category:** best-practice | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:1221`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1223`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1227`
- **Problem:** onAppear calls calendarService.fetchAllCalendars() unconditionally (1222) and, if selectedCalendarId is still nil, picks allCalendars.first (1223). For an edit flow the calendar was already prefilled in init from e.calendar, so this is fine, but selectedCalendarName falls back to the literal "Default" (1228) when no match is found, which can show a misleading 'Default' label if the event's calendar isn't in the fetched list (e.g. a read-only/subscribed calendar). Minor, but the empty/fallback handling is implicit.
- **Recommendation:** Guard the default-selection to only run for the create case (`if !isEditing &amp;&amp; selectedCalendarId == nil`) and consider showing the event's actual calendar title even when it's not in the editable list, rather than 'Default'. Low priority.
- **Risk if applied:** Low — narrowing when the default is applied could change which calendar a brand-new event lands in only if first-calendar selection was being relied on; verify the create path still defaults sensibly.

### 🟢 LOW — Force-unwrap of dictionary value in groupedCalendars

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarSourceSettingsView.swift:97`
  - `HumanProgram/Features/Calendar/CalendarSourceSettingsView.swift:98`
- **Problem:** `map.keys.sorted().map { key in CalendarGroup(source: key, calendars: map[key]!.sorted ...) }` force-unwraps map[key]. It is currently safe (the keys come from the same map), so it won't crash today, but force-unwrap is a fragile idiom the codebase generally avoids; a future refactor that mutates map between building keys and reading values would crash.
- **Recommendation:** Iterate the dictionary directly instead of re-indexing: `map.map { CalendarGroup(source: $0.key, calendars: $0.value.sorted { $0.title &lt; $1.title }) }.sorted { $0.source &lt; $1.source }`. Eliminates the force-unwrap with identical output.
- **Risk if applied:** None — produces the same grouped, sorted result; only removes the `!`.

### 🟢 LOW — Add-event end-date guard can produce an end before start across the all-day boundary

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:1188`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1191`
- **Problem:** When startDate changes, endDate is bumped to start+1h only `if endDate &lt;= new` (line 1188). The Ends DSDateField has minDate: startDate (1191), but DSDateField/DSTimeField changes to endDate are not guarded by an onChange — only the start field is. If the user sets a valid start/end, then edits only the end TIME (not date) earlier than start via DSTimeField, nothing re-validates, and saveEvent() will pass start&gt;end straight to EventKit. EventKit may reject or silently create a zero/negative-duration event. The asymmetric guard (start guarded, end unguarded) is fragile.
- **Recommendation:** Add a symmetric `.onChange(of: endDate)` that clamps endDate to &gt;= startDate (or surfaces a validation message), mirroring the start guard, and/or validate start &lt; end in saveEvent() before calling the service. Verify DSTimeField actually respects minDate for the time component (the minDate only constrains the date picker, likely not the time wheel).
- **Risk if applied:** Low — adding a clamp/validation only prevents an invalid save; it cannot break a currently-valid flow. Confirm the exact DSTimeField behavior before assuming the gap exists in practice.

### 🟢 LOW — AddCalendarEventView hand-rolls menuRow instead of using shared settings/editor components

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:1196`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1231`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1240`
- **Problem:** AddCalendarEventView is a Settings-area editor (built inside SettingsScreen) but the Repeat/Alert/Calendar pickers use a custom private menuRow with a native SwiftUI Menu and appFont(17)/Image(systemName: chevron) rather than the shared anchored-popup/value-row pattern the other planning editors use, and the row label uses DSText().dsTextStyle(.body) while the value uses appFont(17) — a mixed DSKit/legacy row. CLAUDE.md notes the planning editors share one picker path (AnchoredPopup) and that settings rows should be composed from shared components, not hand-rolled. This editor diverges (native Menu, legacy value font).
- **Recommendation:** Where practical, route these dropdowns through the shared value-popup/SettingsRow pattern used by the Recurring/Schedule/Reminder editors, or at minimum make the row label+value typography consistent (both DSText or both appFont). Note this is the Apple-Calendar add form (not a planning template editor), so a native Menu may be an intentional simplification — confirm with owner before unifying.
- **Risk if applied:** Medium — the Apple-event form is a different surface from the recurrence/schedule editors; forcing it onto the AnchoredPopup path could be over-engineering and could regress the working Menu. Safe minimal fix is only the typography consistency.

### 🟢 LOW — Detail sheet caption violates the no-filler-copy rule

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarEventDetailSheet.swift:221`
  - `HumanProgram/Features/Calendar/CalendarEventDetailSheet.swift:283`
  - `HumanProgram/Features/Calendar/CalendarEventDetailSheet.swift:297`
- **Problem:** OverrideToggleRow always renders a caption sentence ("This event won't appear in your task list", passed at line 221). CLAUDE.md says 'No filler/explanatory text … If a screen works without the sentence, leave it out.' A 'Hide from Today' toggle is self-explanatory; the caption is exactly the kind of instructional copy the rule discourages. The component is also a one-off reusable row that bakes in a required caption, encouraging more such copy.
- **Recommendation:** Drop the caption (or make it optional and unset here) so the row is just icon + 'Hide from Today' + toggle, matching the concise-copy convention. Verify the row's reserved height still looks right without the second line.
- **Risk if applied:** Low — removing copy is behavior-neutral, but the row height shrinks (single line), a minor visual change; confirm spacing with the owner since this is a copy/UX decision.

### 🟢 LOW — Near-duplicate permission request / denied views

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:154`
  - `HumanProgram/Features/Calendar/CalendarView.swift:184`
- **Problem:** permissionRequestView (154-182) and permissionDeniedView (184-210) are ~95% identical: same VStack(spacing:20)+Spacer layout, same calendar.badge.exclamationmark icon at size 48, same title/body font treatment, same bordered capsule button styling — differing only in copy and the button action. CalendarSourceSettingsView.swift already solved this exact problem with a reusable CalendarMessageState component (lines 179-208). CalendarView re-hand-rolls both states instead of reusing that shared component, violating the 'reuse UI, never duplicate it' rule.
- **Recommendation:** Reuse the existing CalendarMessageState component (or extract a shared one) for both CalendarView permission states, passing icon/title/message/actionTitle/action. Removes ~55 lines of duplicated markup and keeps the two screens' permission UX in sync.
- **Risk if applied:** Low — CalendarMessageState is DSKit-based while these are appFont-based, so a straight reuse also shifts these two states onto DSKit styling (acceptable/desirable, but a slight visual change). If pixel-identical look must be preserved, extract a legacy-styled shared view instead. Logic unchanged either way.

### 🟢 LOW — Repeated weekDays / Calendar.current / today derivation across sub-views

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:403`
  - `HumanProgram/Features/Calendar/CalendarView.swift:432`
  - `HumanProgram/Features/Calendar/CalendarView.swift:757`
  - `HumanProgram/Features/Calendar/CalendarView.swift:476`
- **Problem:** The same expression `(0..&lt;7).compactMap { cal.date(byAdding: .day, value: $0, to: displayedWeekStart) }` is recomputed in weekDayHeaderRow (403), weekTimeline (432), and weekAllDayBand (757), and `let cal = Calendar.current; let today = cal.startOfDay(for: Date())` is repeated at the top of nearly every helper (e.g. 290-292, 401-402, 431, 625-626). Each is small, but they are copy-pasted and could drift (e.g. if week start logic changes, three call sites must be updated). The abbrevs array ["S","M","T","W","T","F","S"] also appears twice (278 and 404).
- **Recommendation:** Add a small private helper `func weekDays(from start: Date) -&gt; [Date]` and a single `private static let weekdayAbbrevs = [...]`, and consider a computed `today` shortcut. Call sites shrink and the 7-day derivation lives in one place.
- **Risk if applied:** None — pure extraction of an identical expression into one helper; output is byte-identical.

### 🟢 LOW — Repeated calendar-color CGColor conversion and (No title) fallback string

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:467`
  - `HumanProgram/Features/Calendar/CalendarView.swift:803`
  - `HumanProgram/Features/Calendar/CalendarView.swift:984`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1027`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1044`
  - `HumanProgram/Features/Calendar/CalendarEventDetailSheet.swift:82`
- **Problem:** `Color(cgColor: event.calendar.cgColor)` is constructed inline in at least six places (week timeline block 467, all-day chip 803, allDayListPopup 840, EventRowView 984, DayEventBlock 1027/1044, detail sheet 82/96), and the title fallback is written three different ways across the file: "(No title)" (989, 1030, detail 89), event.title ?? "" (463), and e.title ?? "" (797, 842). Inconsistent fallbacks mean a titleless event renders as an empty chip in the timeline but "(No title)" in the row — a small copy-paste drift.
- **Recommendation:** Add a tiny EKEvent extension or local helper (e.g. `var displayColor: Color` and `var displayTitle: String { title?.nilIfEmpty ?? "(No title)" }`) and use it everywhere. Standardizes the fallback and centralizes the CGColor bridge.
- **Risk if applied:** Low — behavior-neutral except it would make the timeline blocks show "(No title)" instead of blank for untitled events, which is arguably a fix; confirm that copy change is wanted before applying to the timeline chips.

### 🟢 LOW — daysInMonthGrid trailing-blank arithmetic is dense and hard to verify

- **Category:** readability | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:864`
  - `HumanProgram/Features/Calendar/CalendarView.swift:871`
- **Problem:** The grid range uses a deeply nested expression: `stride(from: -leadingBlanks, to: monthRange.count + (7 - ((leadingBlanks + monthRange.count) % 7)) % 7, by: 1)`. The trailing-pad term `(7 - (x % 7)) % 7` is correct but unreadable inline, and it's the kind of modular arithmetic where an off-by-one would silently add/drop a week row. It works (weekday 1=Sun honored via firstWeekday-1), but it's a maintenance hazard with no test visible at this layer.
- **Recommendation:** Extract intermediate named values: `let total = leadingBlanks + monthRange.count; let trailingBlanks = (7 - total % 7) % 7; let cellCount = total + trailingBlanks`, then `stride(from: -leadingBlanks, to: monthRange.count + trailingBlanks, by: 1)`. Same output, far clearer; consider a unit test for the grid count.
- **Risk if applied:** None if the extraction preserves the exact arithmetic (it does); purely a readability refactor.


---

## Backlog feature (BacklogView, BacklogComponents, BacklogTaskDetailView)

> The Backlog feature is functionally complete and the shared BacklogRow + popup components are a good reuse foundation. However the area has three recurring health problems. (1) Architecture-rule violations: views write to model relationships (item.project = ...) and call context.save() directly in multiple places, bypassing the @MainActor BacklogRepository that is supposed to own all ModelContext access. (2) BacklogView and BacklogFolderView are near-duplicates — their top bars, select/move/delete handlers, row construction, and DateFormatter-based subtitles are copy-pasted with small tweaks, so any row/selection/toolbar change must be made in 2-3 places and will drift. (3) Efficiency: DateFormatter instances are allocated inside SwiftUI body renders, and several derived lists re-run full .filter scans over allItems on every render (the project list filters every bucket's items on each pass). None of these are crash bugs today, but the architecture and duplication issues directly contradict CLAUDE.md conventions and make the feature fragile to edit. There is also one latent correctness wrinkle in the repository update contract that the detail view papers over with a second save.

### 🔴 HIGH — Views write to ModelContext directly (item.project = ...; context.save()), bypassing the repository

- **Category:** best-practice | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:311`
  - `HumanProgram/Features/Backlog/BacklogView.swift:315`
  - `HumanProgram/Features/Backlog/BacklogView.swift:318`
  - `HumanProgram/Features/Backlog/BacklogView.swift:303`
  - `HumanProgram/Features/Backlog/BacklogView.swift:443`
  - `HumanProgram/Features/Backlog/BacklogView.swift:444`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:188`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:189`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:190`
- **Problem:** CLAUDE.md architecture rule #1 says 'Views never write to ModelContext directly. Views call a ViewModel or Repository.' These views mutate the SwiftData relationship directly (item.project = destination) and call context.save() themselves in moveSelected (both BacklogView and BacklogFolderView), in confirmDeleteProject, and in BacklogTaskDetailView.save(). BacklogRepository already exists and owns the context; this is exactly the access the rule wants centralized. Beyond the convention, the inline writes set item.project but skip item.updatedAt = Date() (the repository's deleteProject/update always bump updatedAt), so moved items get a stale updatedAt — a quiet data-integrity drift between code paths.
- **Recommendation:** Add a repository method such as repo.move(item, to: ProjectBucket?) (and/or moveAll(of project:to:)) that sets item.project, bumps updatedAt, and saves, then call it from moveSelected/confirmDeleteProject. For the detail-view save, see the separate finding about the update() clear-field contract; the goal is to do all project/date writes through the repo so updatedAt stays consistent and no view touches context.save().
- **Risk if applied:** Low-to-medium. Behavior is preserved if the new repo method does exactly what the inline code does plus the updatedAt bump (which only fixes a missing side-effect). Risk is limited to ensuring the new method saves once and the call sites no longer double-save.

### 🔴 HIGH — BacklogView and BacklogFolderView are near-duplicate screens (top bar, select/move/delete, rows)

- **Category:** near-duplication | **Effort:** large
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:168-201`
  - `HumanProgram/Features/Backlog/BacklogView.swift:403-435`
  - `HumanProgram/Features/Backlog/BacklogView.swift:268-320`
  - `HumanProgram/Features/Backlog/BacklogView.swift:437-445`
  - `HumanProgram/Features/Backlog/BacklogView.swift:86-101`
  - `HumanProgram/Features/Backlog/BacklogView.swift:366-381`
- **Problem:** BacklogFolderView reimplements almost everything BacklogView already has: a near-identical top bar (back chevron + select-mode move/trash/Done vs read-mode +/Select), identical select-state handling (selecting/selected/swipeOpen @State, toggle, deleteSelected, moveSelected), and an identical ForEach of BacklogRow with the same closures. The only real differences are the folder filter and the absence of a view-toggle/sort. CLAUDE.md's #1 UI rule: 'When the same visual element appears in more than one place ... it must come from ONE shared component ... If a change to one screen needs the same change on another, that is a sign the markup should have been shared.' This duplication means every toolbar/row/selection tweak must be applied twice and will drift (it already has: BacklogView's top bar uses the iconButton(...) helper, BacklogFolderView re-spells each Button by hand).
- **Recommendation:** Extract a shared SelectableBacklogList (or a BacklogTopBar + a small selection coordinator/observable) that both screens compose, parameterized by the item list, whether a view-toggle/sort is shown, and the destination builder. At minimum, hoist the top-bar select/read button cluster and the deleteSelected/moveSelected/toggle logic into one place reused by both.
- **Risk if applied:** Medium. Pure refactor with no intended behavior change, but it touches the main interaction surface (swipe/select/move/delete) so it needs careful manual re-verification in the simulator before commit.

### 🟠 MEDIUM — deleteSelected in project mode aborts mid-loop, leaving partial deletion and stale select state

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:280-289`
  - `HumanProgram/Features/Backlog/BacklogView.swift:301-307`
- **Problem:** In project select-mode, deleteSelected loops selected projects and, on the FIRST project that still has backlog items, sets showDeleteProjectConfirm and returns early (line 284-285). Any empty projects iterated before it were already deleted, but the remaining selected projects (including the one needing confirmation and any after it) are left untouched, and selecting/selected are NOT cleared (the clear at line 289 is skipped by the early return). After the user confirms, confirmDeleteProject only handles that ONE project (lines 301-307); the rest of the multi-selection is silently dropped. So 'select 3 projects, two non-empty, tap trash' deletes one, confirms one, and forgets the third. Iteration order over the projects array vs the unordered selected Set makes which projects survive nondeterministic.
- **Recommendation:** Handle the whole selection deterministically: partition selected projects into empty (delete immediately) and non-empty (queue for one confirm covering all of them), then on confirm delete the full queued set and clear selecting/selected. Do not rely on early-return inside the loop.
- **Risk if applied:** Medium. This changes multi-delete behavior (intentionally, to fix the drop), so it needs explicit testing of the multi-select project-delete flow; single-selection behavior should remain identical.

### 🟠 MEDIUM — Hardcoded .font(.system(size:)) in views; raw Text/TextField instead of DSKit

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:171`
  - `HumanProgram/Features/Backlog/BacklogView.swift:205`
  - `HumanProgram/Features/Backlog/BacklogView.swift:227`
  - `HumanProgram/Features/Backlog/BacklogView.swift:405`
  - `HumanProgram/Features/Backlog/BacklogComponents.swift:32`
  - `HumanProgram/Features/Backlog/BacklogComponents.swift:109-124`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:76-77`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:137`
- **Problem:** CLAUDE.md design rules: 'No hardcoded ... .font(.system(size:)) in views' and 'new or migrated UI must use DSKit, not [AppColors/AppTypography or raw fonts].' These files use .font(.system(size: 18, weight:)) for the back chevron and toolbar glyphs (BacklogView 171, 205, 227, 405; BacklogComponents 32), and the popups/detail use raw SwiftUI Text(...).font(appFont(18)) and TextField rather than DSText/DSKit fields (NewProjectPopup lines 109-124, detail Project menu label 76-77, Save button 137). Some of this is icon sizing where DSKit has no direct equivalent, but the convention is applied unevenly across the app's migrated screens, and the literal sizes (18/17/13) are repeated magic numbers.
- **Recommendation:** Where DSKit equivalents exist (DSText with .dsTextStyle, DSImageView(systemName:size:.font(...)) for SF Symbols), route through them as other migrated screens do; for the system-symbol toolbar glyphs that must keep a pixel size, centralize the size constants. Do not change visual sizing — match current pt values.
- **Risk if applied:** Low-to-medium visually. Swapping Image/.font for DSImageView can subtly shift glyph metrics, so each toolbar must be eyeballed against the current build before/after. Safe to leave as-is if pixel-parity can't be guaranteed.

### 🟠 MEDIUM — BacklogRepository.update() silently cannot clear project/assignedDate, forcing the detail view to write the model and double-save

- **Category:** data-integrity | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Repositories/BacklogRepository.swift:33-55`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:186-190`
- **Problem:** update() treats nil project/assignedDate as 'no change' (lines 49-52), so a user who removes a task's project or turns off the assigned-date toggle cannot clear those fields through the repository. The detail view works around this by calling repo.update(...) (which saves once), then directly setting existing.project = project and existing.assignedDate = assigned and calling context.save() AGAIN (a second save and a direct model write from a view). The repository's own header comment block (lines 42-48) admits the contract is muddy ('callers should pass an explicit nil via the typed variant' — no such variant exists). This is the root cause of the view-writes-to-context violation in the detail screen and means clearing fields is double-persisted.
- **Recommendation:** Give the repository an unambiguous way to set project/assignedDate to nil — e.g. a dedicated method like repo.setProject(_:on:) / repo.setAssignedDate(_:on:), or change update to take a sentinel/enum for 'clear vs leave'. Then have save() call only the repository (single save, updatedAt bumped, no view-side context.save()). Also delete the stale comment block in update() once the contract is real.
- **Risk if applied:** Medium. The clear-field path is user-visible; the new repo method must replicate startOfDay normalization and updatedAt. Verify that removing project/date in edit mode still persists after the change.

### 🟠 MEDIUM — DateFormatter allocated inside SwiftUI body / row-render hot paths

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:107-108`
  - `HumanProgram/Features/Backlog/BacklogView.swift:370`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:162`
- **Problem:** taskSubtitle(_:) builds 'let f = DateFormatter(); f.dateFormat = "MMM d"' for every backlog row that has a date, and it is called from taskRows inside the ForEach so it re-runs on every list render. BacklogFolderView does the same inline in the subtitle closure (line 370). BacklogTaskDetailView.dateString builds another DateFormatter on each render. DateFormatter creation is one of the most expensive Foundation allocations; CLAUDE.md's efficiency guidance explicitly calls out 'DateFormatter/Calendar built in hot paths.' With many rows this is wasted CPU on every scroll/state change.
- **Recommendation:** Hoist the two formats ('MMM d' and 'MMM d, yyyy') into cached static let DateFormatter constants (e.g. a small enum BacklogDateFormat with monthDay and monthDayYear) and reference them; no behavior change, just reuse the instances.
- **Risk if applied:** Very low. Same format strings, same output; only the allocation site changes. Ensure the cached formatters use the same default locale/calendar the inline ones did (they do by default).

### 🟠 MEDIUM — Repeated full .filter scans over allItems on every render; per-project item filtering

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:70`
  - `HumanProgram/Features/Backlog/BacklogView.swift:122-123`
  - `HumanProgram/Features/Backlog/BacklogView.swift:141`
  - `HumanProgram/Features/Backlog/BacklogView.swift:282`
  - `HumanProgram/Features/Backlog/BacklogView.swift:294`
  - `HumanProgram/Features/Backlog/BacklogView.swift:350-352`
- **Problem:** sortedTasks filters allItems by status then sorts on every body evaluation; unassignedCount filters allItems again on every render; and projectRows calls project.items.filter { $0.status == .backlog }.count for EVERY project row each render (an O(projects x items) pass) just to show a count. deleteSelected/attemptDeleteProject also re-scan project.items. None are cached or memoized, so opening the screen or toggling any @State recomputes all of it. For a personal app with modest data this is not a perf crisis, but it is repeated work on a hot path and the project-count scan grows with both projects and items.
- **Recommendation:** Compute a single status==.backlog active list once and derive sortedTasks, unassignedCount, and per-project counts from it (e.g. group active items by project?.id into a dictionary, then index counts in O(1)). This also removes the duplicated filter predicate scattered across the file.
- **Risk if applied:** Low. Same results if the grouping/counting matches the current predicate exactly. Watch that 'Unorganized' uses project == nil (id nil) consistently.

### 🟢 LOW — swipeOpen close-on-open is implicit, not explicit (fragile single-id state machine)

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:94-95`
  - `HumanProgram/Features/Backlog/BacklogComponents.swift:48-51`
  - `HumanProgram/Features/Backlog/BacklogComponents.swift:86-92`
- **Problem:** swipeOpen is a single optional id, so only one row can be open at a time conceptually — but onOpenSwipe just sets swipeOpen = item.id without first explicitly closing a previously open row, and each BacklogRow keeps its own dragX. CLAUDE.md's editor spec says 'Opening one row's trash ... auto-closes an open one.' Here, opening row B flips swipeOpen to B, which makes row A recompute offset to 0 (since A's swipeOpen prop becomes false) — so it mostly self-corrects — but row A's internal dragX is whatever the spring left it, and there is no explicit close call, so the behavior depends on the parent re-render rather than an intentional close. Any future change that keeps per-row open state, or a missed re-render, leaves two rows open.
- **Recommendation:** Make onOpenSwipe explicit: close the previously open row before assigning the new id, and reset dragX to 0 whenever a row's swipeOpen prop becomes false. No user-visible change expected; this hardens the state machine.
- **Risk if applied:** Low. The single-id model already enforces one-open in practice; this is a robustness tweak. Verify swipe open/close still animates correctly.

### 🟢 LOW — Settings-style detail rows hand-rolled instead of using SettingsRowContent

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:63-107`
- **Problem:** CLAUDE.md: 'Every Settings-area screen is composed from the shared components ... Do NOT hand-roll settings rows.' BacklogTaskDetailView is rendered inside SettingsScreen and uses SettingsGroup/SettingsSectionLabel, but the Project and Assigned-Date rows are built as raw HStack { DSText(...) ; Spacer ; ... }.frame(height: 34) rather than SettingsRowContent. The Today/Settings editors use the shared row component for the same label+trailing-value pattern, so this is the convention applied inconsistently. It also re-hardcodes the 34pt row height that the shared component owns.
- **Recommendation:** Compose the Project and Assigned-Date rows from SettingsRowContent (label + trailing accessory) so the row height, alignment, and trailing inset come from one place, matching the rest of the settings-area editors. Verify the trailing menu/toggle/date-field still align after the swap.
- **Risk if applied:** Medium. SettingsRowContent may apply menu-vs-centered insets differently than the hand-rolled HStack; needs visual check that the trailing controls don't shift. Behavior unchanged.

### 🟢 LOW — BacklogRow applies rowHeight via redundant frames at multiple levels

- **Category:** conciseness | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogComponents.swift:27-28`
  - `HumanProgram/Features/Backlog/BacklogComponents.swift:41`
  - `HumanProgram/Features/Backlog/BacklogComponents.swift:45`
  - `HumanProgram/Features/Backlog/BacklogComponents.swift:75`
- **Problem:** rowHeight is applied as a frame on face (line 28), on the outer HStack (line 41), on the GeometryReader wrapper (line 45), and again inside faceContent (line 75). The repeated .frame(height: rowHeight) layering is redundant and makes it unclear which one actually governs layout; it also risks a future edit changing one and not the others.
- **Recommendation:** Apply the row height once at the authoritative level (the outer container) and let children inherit, removing the redundant inner frames after confirming layout is unchanged.
- **Risk if applied:** Low-to-medium. Frames interact subtly under GeometryReader; remove one at a time and visually confirm the 48pt row and clipped swipe still look identical.

### 🟢 LOW — Inline 'MMM d' subtitle in BacklogFolderView duplicates taskSubtitle's date logic

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:103-111`
  - `HumanProgram/Features/Backlog/BacklogView.swift:368-371`
- **Problem:** The folder row's subtitle closure rebuilds the same 'MMM d' DateFormatter and string that taskSubtitle already produces, just without the project segment. Two copies of the same date-formatting snippet that must stay in sync (and both allocate a formatter per row, per the efficiency finding).
- **Recommendation:** Reuse a single shared subtitle/date helper (or the cached formatter from the efficiency fix) for both the Task view and the Folder view rows.
- **Risk if applied:** Very low. Same output; consolidation only.

### 🟢 LOW — Two project-delete code paths with subtly different semantics (re-assign vs delete tasks)

- **Category:** logic-structure | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:292-307`
  - `HumanProgram/Core/Repositories/BacklogRepository.swift:92-100`
- **Problem:** Deleting a project has two meanings that are easy to confuse: repo.deleteProject re-assigns the project's items to a destination (nullify by default, i.e. items become Unorganized) and keeps them; but confirmDeleteProject (line 301-304) deletes ALL the project's items first, then the project. attemptDeleteProject/deleteSelected call repo.deleteProject directly only when the project is EMPTY, otherwise route to the confirm-then-delete-tasks path. So the same 'delete project' gesture means 'keep tasks (move to Unorganized)' for an empty project and 'destroy tasks' for a non-empty one. The split logic (some in the view, some in the repo, with the repo's moveItemsTo param unused by these callers) is hard to follow and a likely source of future mistakes.
- **Recommendation:** Consolidate the intended semantics in one place: the view should call a single repo method (e.g. deleteProject(_, deletingItems: Bool)) so the 'destroy tasks' decision is explicit and the unused moveItemsTo path doesn't invite a wrong call. No behavior change if the boolean defaults preserve current flows.
- **Risk if applied:** Low-to-medium. Refactor only; must preserve that confirmed delete removes the tasks and empty-project delete leaves no orphan.

### 🟢 LOW — Project duplicate-name guard lives in the view, not the repository

- **Category:** logic-structure | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:322-331`
  - `HumanProgram/Core/Repositories/BacklogRepository.swift:84-89`
- **Problem:** The 'project already exists' validation is done in the view (BacklogView.createProject) by lowercasing names, while repo.createProject has no uniqueness guard at all. Validation that protects a data invariant (no duplicate project names) sits in one UI path; any other caller of repo.createProject can create a duplicate. The view-level check only trims whitespace and lowercases — it won't catch e.g. accent/diacritic differences — so the invariant is weakly enforced and only on this screen.
- **Recommendation:** Move the duplicate-name guard into BacklogRepository.createProject (throw a typed error the view surfaces), so the invariant holds for every caller, and keep the view's user-facing message. No behavior change for this screen if the repo throws and the view maps it to newProjectError.
- **Risk if applied:** Low. Moving the guard down is safe as long as the view still shows the same error; ensure the repo throw doesn't crash any non-UI caller.

### 🟢 LOW — Folder view sorts only A–Z while Task view honors a sort menu — inconsistency vs 'same behavior'

- **Category:** logic-structure | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:350-353`
  - `HumanProgram/Features/Backlog/BacklogView.swift:69-78`
- **Problem:** Opening a project folder always sorts items title A–Z with no sort control, whereas the main Task view offers A–Z/Z–A/Assigned date. CLAUDE.md and the in-code comment describe the folder as 'a project's tasks — same behavior as Task View.' The folder silently drops the sort affordance and any non-A–Z ordering, a mismatch a user moving between the two views would notice. Not a crash, but an inconsistency against the stated 'same behavior' intent and another reason the two screens should share one list component.
- **Recommendation:** If 'same behavior' is intended, surface the same sort menu in the folder (which falls out naturally from a shared-list refactor). If the A–Z-only folder is intentional, update the comment so it no longer claims identical behavior. Flag to the owner rather than changing silently.
- **Risk if applied:** Low if folded into the shared-list refactor; otherwise adding a sort menu is additive. Confirm with owner whether the folder is meant to have sorting.

### 🟢 LOW — Magic-number row metrics and sizes scattered across the three files

- **Category:** sloppy | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogComponents.swift:21-22`
  - `HumanProgram/Features/Backlog/BacklogView.swift:55`
  - `HumanProgram/Features/Backlog/BacklogView.swift:162`
  - `HumanProgram/Features/Backlog/BacklogView.swift:188`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:57`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:86`
- **Problem:** Row height 48 appears as a literal in BacklogRow (rowHeight) AND in projectRowContent.frame(height: 48) — two independent copies of the same value; the matching min-height 34 and the pitch comment '48 + 7 = 55' are repeated; trash width 68, toggle column 78, icon frames 40/44, and font sizes 18/17/13 are all bare literals across the three files. When the owner asks to retune row height or tap-target size (the CLAUDE.md notes say many small UI edits are coming), these must be found and changed in several spots and will drift.
- **Recommendation:** Promote the shared row metrics (row height, trash width, standard icon tap frame) to named constants in BacklogComponents (or a small layout enum) and reference them from all three files so a single edit retunes every row.
- **Risk if applied:** Very low. Pure renaming of literals to constants with identical values.


---

## Planning Editors (Schedule / Reminder / Exercise / Recurring) + their list screens

> The four planning editors are built on a genuinely shared substrate (EditorRowInteractions: ReorderRecognizer/SwipePanRecognizer/KeyboardScrollNudge/GlassKeypad/SteppedWheel/CountWheel/IntervalWheel; PlanningComponents: WeekdayCircleSelector/WeekdayStrip/AnchoredPopup/ConfirmPopup/DateFieldRow/popupGlass; SettingsComponents: SettingsScreen/AddNavButton), and none of them still use the removed inline controls (AppDropdown/WheelHourMinute/numberPad) — that part of the migration is clean. However, a large second tier of "glue" code is copy-pasted between editors rather than shared: the entire custom-keypad lifecycle (typedDigits/showKeypad/keypadDigit/keypadBackspace/applyTypedToActive/keypadDone/dismissKeypadAndPopup), the keyboard-spacer NotificationCenter observers, the keypad overlay block, the swipe/reorder geometry block (swipeOffset/shiftOffset/projectedIndex/swipeBegan/swipeChanged/swipeEnded/beginReorder/endReorder are near-identical between ScheduleEditor and ExerciseRoutineEditor), the valueRow/repeatRow/repeatOptionList trio (verbatim between Schedule and Reminder, with subtle drift), and the per-id Binding factories. There is also a duplicated DateFormatter-per-render summary in both list rows, a triplicated legacy-weekday mapping, two diverging repeat-toggle idioms, and an inconsistent dismiss-guard between editors. The screens are otherwise idiomatic DSKit/SwiftData and respect the architecture rules (repos own ModelContext, no past-page writes). Almost all findings are mechanical extractions that are safe to apply; a few carry behavior-divergence risk and are flagged accordingly.

### 🔴 HIGH — Entire custom-keypad lifecycle is copy-pasted verbatim between Schedule and Reminder editors

- **Category:** exact-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:444-490`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:328-368`
- **Problem:** showKeypad(), keypadDigit(_:), keypadBackspace(), applyTypedToActive(), keypadDone(), dismissKeypadAndPopup(), and dismissOpenInputIfAny() are byte-for-byte identical (or nearly so) in both editors. applyTypedToActive in particular is a non-trivial HHMM parser with snap-to-5 logic duplicated exactly (Schedule:458-465, Reminder:342-349). The supporting @State (keypadVisible, typedDigits, keypadMeasuredHeight, keyboardSpacer) is also declared twice. CLAUDE.md says 'Numeric entry uses a custom keypad (GlassKeypad)' as one shared path; the keypad VIEW is shared but its entire driving controller is not. A future change to the HHMM rule must be made in two places and they will drift.
- **Recommendation:** Extract a small reusable controller — e.g. an observable 'KeypadController' holding typedDigits + the apply/digit/backspace/done logic and a binding it writes to, or a view modifier that owns the keypad overlay + state. Each editor would then hand it the activeMinutesBinding and the dismiss closure. Keep behavior identical (same snap-to-5, same min(23)/min(55) clamps).
- **Risk if applied:** Medium — this is interaction-critical code that took many iterations to get right (per CLAUDE.md). Extraction must preserve the exact animation timings, the typedDigits suffix(4) truncation, and the order of operations in dismissKeypadAndPopup. A regression here is user-visible. Behavior is safe IF the extraction is purely mechanical and covered by manual testing of both editors.

### 🔴 HIGH — valueRow / repeatRow / repeatOptionList are duplicated across Schedule, Reminder, and Recurring editors with silent drift

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:262-279`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:348-370`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:818-832`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:215-250`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:291-314`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:109-163`
- **Problem:** The 'Repeat' header row (label + chevron.up.chevron.down + anchorFrame("repeat")), the reusable valueRow(label:value:anchorId:action:), and the repeatOptionList option list are essentially identical view code pasted into three editors. They have already drifted: Schedule's repeatOptionList uses .a11yTapBorder(cornerRadius: 4) on the outer button (line 275) while Reminder uses .a11yTapBorder(cornerRadius: 4) on repeatRow but Rectangle() on the option buttons (line 311); Recurring adds .lineLimit(1).fixedSize(...) to the option text (line 148) that the other two lack; Recurring's repeatRow uses a toggle idiom (activePicker == .repeatMode ? nil : .repeatMode) while Schedule/Reminder use the dismissOpenInputIfAny() guard. These are exactly the 'copy-paste a chunk of view code and tweak it' the design rules forbid. A repeat-picker visual change must be applied 3×.
- **Recommendation:** Promote valueRow, the Repeat row, and the option list to shared views in PlanningComponents.swift (e.g. SettingsValueRow, RepeatPickerRow, PickerOptionList) parameterized by label/options/binding. Reconcile the drift (pick one a11y shape, one tap idiom, one text-sizing rule) when extracting.
- **Risk if applied:** Low-to-medium — pure view extraction. Risk is choosing one variant where they currently differ (e.g. the lineLimit on options, or the toggle-vs-guard tap behavior); pick the guard idiom + the same a11y shape used by the reference Schedule editor and verify no visual reflow.

### 🔴 HIGH — Reorder + swipe-to-delete geometry block is near-duplicated between Schedule and Exercise editors

- **Category:** near-duplication | **Effort:** large
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:554-602`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:719-752`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:323-406`
- **Problem:** swipeBegan, swipeChanged, swipeEnded, beginReorder, endReorder, projectedIndex, shiftOffset, swipeOffset, closeSwipe, and closeSwipeIfOpen are almost line-for-line identical in ScheduleEditorView and ExerciseRoutineEditorView (differing only in the array name blocks vs items, the rowHeight constant, and Exercise calling persistOrder()). The UIKit recognizers are already shared (ReorderRecognizer/SwipePanRecognizer in EditorRowInteractions), but the SwiftUI-side glue that interprets their callbacks into offsets and array moves is copy-pasted. CLAUDE.md explicitly says 'Build new editable-row editors on these, don't re-derive' — the recognizers are reused but the geometry math was re-derived and copied. The two trashWidth-based swipeOffset functions (Schedule:740-748, Exercise:391-398) are identical including the 0.2 rubber-band factor.
- **Recommendation:** Extract the offset/move math into a generic helper (free functions or a small @Observable 'RowDragModel&lt;ID&gt;' parameterized by rowHeight and the array) that both editors drive from the recognizer callbacks. The animation constants and the rubber-band 0.2 factor should live in one place.
- **Risk if applied:** Medium — drag/swipe is the most fiddly interaction in the app and is state-heavy (dragInfo/swipeOpenId/swipeDragId/swipeDragX). A generic model must preserve the exact projectedIndex rounding and shiftOffset range checks or rows will jump. Safe only with careful manual reorder/swipe testing on both screens.

### 🟠 MEDIUM — dismissOpenInputIfAny diverges between editors (one omits the open-popup guard at the repeat toggle)

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:113`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:266`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:219`
- **Problem:** Schedule and Reminder guard every value/repeat tap with 'if !dismissOpenInputIfAny() { activePicker = ... }' so a tap while another popup/keypad is open just closes it (the documented 'tapping out just dismisses, does not also open' rule in CLAUDE.md). Recurring's repeatRow instead uses 'activePicker = activePicker == .repeatMode ? nil : .repeatMode' (line 113). Recurring has only one picker so this is currently harmless, but it is an inconsistent idiom that violates the documented dismiss-first convention and would misbehave if a second picker were ever added.
- **Recommendation:** Make Recurring's repeat row use the same guard idiom as the other editors (the shared RepeatPickerRow from the near-duplication finding would naturally fix this). Behavior is unchanged today since there is only one picker.
- **Risk if applied:** Low — with a single picker the two idioms are behaviorally equivalent today; switching to the guard cannot regress current behavior and aligns with the convention.

### 🟠 MEDIUM — Per-id Binding factories duplicated across editors and within the same file

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:372-397`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:288-305`
- **Problem:** durationBinding(for:)/nameBinding(for:)/colorHexBinding(for:) in Schedule and textBinding(for:)/setsBinding(for:)/repsBinding(for:) in Exercise all share the identical shape: Binding(get: first(where: id)?.field, set: if let i = firstIndex(where: id) { array[i].field = v }). This get/set-by-id pattern is written six times. Each does an O(n) linear scan twice (once in get, once in set) — see the efficiency finding. The boilerplate is error-prone (easy to mismatch the keyPath between get and set).
- **Recommendation:** Add a generic helper, e.g. extension Array where Element: Identifiable to vend Binding(for id, keyPath:) for a writable key path, returning the get/set with index lookup. All six call sites collapse to one line each and the linear-scan logic lives in one tested place.
- **Risk if applied:** Low — mechanical. The generic must use the same default (?? 0 / ?? "") on the get side that callers rely on; preserve those defaults per call site.

### 🟠 MEDIUM — Legacy-weekday mapping is triplicated and inconsistent with how weekends are stored

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:247-255`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTasksView.swift:78-86`
- **Problem:** The exact same static func weekdays(from rule: RecurrenceRule) -&gt; Set&lt;Int&gt; (mapping .everyDay→1...7, .weekdays→[2,3,4,5,6], .weekends→[1,7], default→Set(rule.weekdays)) is copy-pasted in the Recurring editor and the Recurring list row. It encodes the 1=Sun..7=Sat convention by hand in two places; if the encoding or the legacy-frequency set changes, both must change in lockstep. (It is correct per CLAUDE.md's encoding, but the duplication is a drift risk.)
- **Recommendation:** Move this to a single place — ideally a computed helper on RecurrenceRule (e.g. var resolvedWeekdays: Set&lt;Int&gt;) in Core/Models — and call it from both the editor and the list row. This also removes the hand-rolled weekday constants from the view layer.
- **Risk if applied:** Low — both copies are already identical, so consolidating cannot change behavior. Verify the new helper lives where both files can see it.

### 🟠 MEDIUM — Keyboard-spacer NotificationCenter observers duplicated in three editors

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:544-551`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:202-209`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:136-143`
- **Problem:** The identical pair of .onReceive(keyboardWillShowNotification){ set keyboardSpacer = f.height } / .onReceive(keyboardWillHideNotification){ keyboardSpacer = 0 } with the same easeOut(0.25)/easeOut(0.2) timings appears in all three row-bearing editors, plus the matching @State keyboardSpacer and the trailing Color.clear.frame(height: keyboardSpacer) spacer. CLAUDE.md documents this 'bottom content spacer = keyboard height' pattern as one approach but it is hand-copied per screen.
- **Recommendation:** Wrap into a single ViewModifier (e.g. .keyboardBottomSpacer($keyboardSpacer)) or have SettingsScreen(manualKeyboardAvoidance: true) expose the spacer height, so the show/hide observers and timings live in one place.
- **Risk if applied:** Low — mechanical. Preserve the exact animation durations; the spacer height feeds SwiftUI's avoidance so the value must remain f.height.

### 🟠 MEDIUM — Keypad overlay ZStack block is copy-pasted between Schedule and Reminder

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:220-231`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:182-193`
- **Problem:** The 'if keypadVisible { VStack { Spacer(); GlassKeypad(...).background(GeometryReader preference KeypadHeightKey) }.ignoresSafeArea(edges:.bottom).transition(.move(edge:.bottom)).zIndex(2) }' overlay is identical in both editors, as is the onChange(of: activePicker) that animates keypadVisible=false and the onPreferenceChange(KeypadHeightKey). Same view chunk, two copies.
- **Recommendation:** Extract a 'BottomKeypadOverlay(visible:onDigit:onBackspace:onDone:measuredHeight:)' view (or a modifier) into EditorRowInteractions next to GlassKeypad. Both editors then drop the duplicated overlay and the KeypadHeightKey plumbing.
- **Risk if applied:** Low — view extraction. Keep the zIndex(2), ignoresSafeArea, and transition so layering/animation are unchanged.

### 🟠 MEDIUM — Reminder save() writes target twice and ignores the create() return on the new-item path

- **Category:** logic-structure | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:486-526`
- **Problem:** For a new reminder, repo.create(...) is called with title/message/fireHour/fireMinute/recurrenceMode/weekdays/soundMode, and then the very same fields are immediately re-assigned to target (lines 505-517) and repo.update(target) is called. So on the create path every field is set twice and two repo calls (create + update) run. The window/interval fields are only set when repeatMode == 'multiple', meaning a brand-new 'multiple' reminder relies on create() having sensible defaults for windowStart/End/interval before the conditional block fills them — fragile coupling between create()'s defaults and this method.
- **Recommendation:** Either have create() take all fields (including window/interval) so the post-create re-assignment block is unnecessary, or build the new model the same way the existing-edit path mutates 'target' and call update() once. At minimum, skip the redundant field assignments on the freshly-created object.
- **Risk if applied:** Medium — touches persistence and notification scheduling. Must verify create()'s side effects (id assignment, scheduling) are preserved and that a new 'multiple' reminder still gets its window/interval. Do not change without reading NotificationReminderRepository.create.

### 🟠 MEDIUM — Toolbar trash/Save buttons are an identical view block duplicated across all four editors

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:282-307`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:372-393`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:165-186`
- **Problem:** The editorButtons 'trash (if editing) + Save (disabled until canSave)' block is essentially identical in Schedule, Reminder, and Recurring — same Image(systemName:"trash").font(.system(size:18)).foregroundStyle(.red).frame(44x44).contentShape(Rectangle()).a11yTapBorder(Rectangle()), and the same Save Text with minWidth/minHeight 44 + padding(.horizontal,8) + canSave colouring. The trailing-edge trash circle in the swipe row (Schedule:633-642, Exercise:154-164) is likewise duplicated. AddNavButton was already extracted for the '+' on the lists, but the editor trash/Save toolbar was not.
- **Recommendation:** Add shared 'EditorDeleteButton(action:)' and 'EditorSaveButton(enabled:action:)' (and a 'SwipeTrashButton') alongside AddNavButton in SettingsComponents, matching the documented .contentShape(Rectangle()) on the 44x44 requirement. Each editor's editorButtons collapses to a couple of lines.
- **Risk if applied:** Low — view extraction with identical sources. Preserve the 44x44 frame + contentShape so the documented full-target tappability is unchanged.

### 🟢 LOW — Hardcoded .font(.system(size:)) and magic literals scattered through the editor views

- **Category:** best-practice | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:270`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:287-296`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:359`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:222`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:377-389`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:157-158`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:117`
- **Problem:** CLAUDE.md forbids '.font(.system(size:))' in views (DSKit migration rule). The editor toolbar/chevron glyphs use raw .font(.system(size: 12)) / .font(.system(size: 18)) / .font(.system(size: 20)) / .font(.system(size: 14, weight:)) in many places, and the recurring magic sizes (18 trash, 18 Save, 12 chevron, 17 trash glyph, 40 red circle, 44 frames, trashWidth 72, rowHeight 56/60) are repeated literals copy-pasted across editors. These are the toolbar-icon and trash-circle styles that are themselves duplicated, so the magic numbers compound the duplication.
- **Recommendation:** These glyphs predate full DSKit migration; when the toolbar buttons (trash/Save/+/duplicate) and the swipe trash circle are extracted into shared components (see other findings), route their sizing through DSKit tokens or named constants so the literals exist once. Note this is a known-legacy area, not new code.
- **Risk if applied:** Low for the literal-consolidation part (no behavior change). Migrating .system(size:) to DSKit tokens for icon glyphs could subtly change rendered glyph size, so match the resulting size to the current pixel size and verify no toolbar reflow.

### 🟢 LOW — save()/delete() error handling is print-only and duplicated; failures are swallowed silently

- **Category:** best-practice | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:913-915`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:938-942`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:522-525`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:228-232`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:430-478`
- **Problem:** Every editor's save/delete uses the same 'do { ... } catch { print("[...] error: \(error)") }' shape, and dismiss() runs unconditionally afterward — so if repo.update/create/refresh throws, the user is returned to the list as though it succeeded with no feedback. The Exercise editor additionally peppers 'try? ... ; try? PageRefreshService.refresh' across commitNameIfChanged/commitTitleEditing/commitCounts/addExercise/persistOrder/deleteExercise (lines 430,443,445,451,452,461,467,468,477,478), so a failed persist is fully silent. This is consistent across files but consistently swallows failures.
- **Recommendation:** Out of scope to redesign error UX here, but worth noting: at minimum, on a thrown save error do not dismiss() (so the user notices), mirroring how Schedule already surfaces conflictMessage. Consider a shared logging helper instead of repeated print(...) string-tagging. No behavior change required to fix the dismiss-on-failure case for save().
- **Risk if applied:** Medium — changing dismiss-on-error or adding surfaced errors alters user-visible flow and could mask the 'happy path' the owner relies on. Treat as a deliberate UX decision, not a mechanical fix; do not apply blindly.

### 🟢 LOW — Binding factories do a double O(n) linear scan per get/set; reorder/shift call them every frame

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:372-394`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:728-736`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:288-305`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:352-360`
- **Problem:** Each binding does first(where:) in the getter and firstIndex(where:) in the setter — two linear scans per access. shiftOffset(forIndex:) also calls firstIndex(where:) and projectedIndex on every row, every drag frame; for a block/exercise list this is O(n) per row × n rows = O(n^2) per drag frame. Lists are small (a handful of blocks/exercises) so the real-world cost is negligible, but it is a latent pattern.
- **Recommendation:** Low priority given list sizes. If touched, cache the dragged item's base index once per drag frame instead of recomputing firstIndex in shiftOffset for each row, and prefer index-based bindings where the index is already known (the ForEach already enumerates index).
- **Risk if applied:** Low — but not worth applying alone; fold into the binding-helper or drag-model extraction. No behavior change if done carefully.

### 🟢 LOW — DateFormatter built on every render in both list-row summaries

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleListView.swift:85-92`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTasksView.swift:68-76`
- **Problem:** Both ScheduleRow.summary and RecurringTaskRow.summary allocate a fresh DateFormatter (let f = DateFormatter(); f.dateFormat = "MMM d") inside a computed property that runs on every body evaluation. DateFormatter creation is comparatively expensive, and this is a hot path (every list row re-renders on @Query changes, toggles, scrolling). The two summaries are also near-identical logic (the only difference is custom range vs Weekly fallback).
- **Recommendation:** Hoist a single static cached DateFormatter (e.g. a shared 'MMM d' formatter) and reuse it. Better, extract one shared helper that takes (startDate?, endDate?) -&gt; String since the two summaries are duplicates, eliminating both the duplication and the per-render allocation.
- **Risk if applied:** Low — a cached formatter with a fixed format string produces identical output. Keep the format string and the en-dash/spacing exactly as-is.

### 🟢 LOW — fullWeekdayName dictionary duplicated between Exercise list and Exercise editor

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Exercise/ExerciseSettingsView.swift:12-15`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:49-52`
- **Problem:** The identical static let fullWeekdayName: [Int:String] = [1:"Sunday", ... 7:"Saturday"] is declared in both the list and editor, and both then compute weekdayTitle/weekdayName the same way (routine.recurrenceRule.weekdays.first ?? 0 -&gt; lookup ?? "Exercise"). This is the 1=Sun..7=Sat encoding hand-written twice.
- **Recommendation:** Put a single weekday-name lookup (and a 'name(for routine:)' helper) in one shared place — e.g. alongside the WeekdayStrip/WeekdayCircleSelector in PlanningComponents, or a static on RecurrenceRule — and reference it from both.
- **Risk if applied:** Low — identical data, consolidation cannot change output. Keep the 'Exercise' fallback string.

### 🟢 LOW — currentSnapshot / Snapshot struct / hasUnsavedChanges pattern duplicated across three editors

- **Category:** near-duplication | **Effort:** large
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:146-158`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:978-988`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:86-100`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:529-542`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:47-59`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:258-266`
- **Problem:** Each editor reimplements the same unsaved-changes machinery: a private Equatable XSnapshot struct mirroring the @State fields, an 'original' stored snapshot set in loadIfNeeded's defer, a currentSnapshot computed property rebuilding it, and hasUnsavedChanges = (new ? canSave : current != original) + attemptBack(). The Schedule variant adds the forceNew wrinkle but is otherwise the same shape. This is a recurring structural pattern, not literally identical code, so it can't be trivially merged, but it is worth recognizing as the same idiom re-derived three times.
- **Recommendation:** Optional/low priority: a generic 'DirtyTracker&lt;Snapshot: Equatable&gt;' or a small protocol the editors conform to could centralize attemptBack/hasUnsavedChanges/discard-guard. Given the per-editor field lists differ, a full merge is awkward; flag for awareness rather than urgent extraction.
- **Risk if applied:** Low to leave as-is; medium if merged (the discard guard is wired into SettingsScreen's swipe-back and must keep firing identically). Recommend not refactoring unless the editors are being reworked anyway.


---

## Settings shared Components

> These six files are the shared building blocks for the Settings area and planning editors, and they are mostly well-factored: SettingsScreen/SettingsGroup/SettingsRowContent are clean reusable abstractions, the UIKit reorder/swipe/keypad infrastructure in EditorRowInteractions is genuinely shared and generic, and popupGlass/AnchoredPopup centralize the glass look. The main issues are: (1) a real 12h/24h consistency bug in DSTimeField — it displays via clockString (12h/24h aware) but its picker wheel is hard-coded 24h with no AM/PM column, violating the CLAUDE.md rule that picker wheels follow the time-format setting, and it re-implements a wheel that SteppedWheel already solves correctly; (2) dead code in ColorPresetStore (add(_:) and isFull are unused, and add(_:) is a byte-identical duplicate of addToEmptySlot); (3) several hot-path DateFormatter allocations on every render; (4) pervasive hardcoded .font(.system(size:)) and appFont(...) in views that the DSKit migration is supposed to remove; and (5) some near-duplicated swatch-capacity guards and capsule-key markup. None of the suggested fixes require behavior changes beyond the explicitly-flagged DSTimeField wheel parity, which is a convention conformance the owner already documented as desired.

### 🟠 MEDIUM — DSTimeField picker wheel is hard-coded 24h while its label honors 12h/24h

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:128`
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:152-160`
- **Problem:** DSTimeField's read-out label uses clockString(date:) (so it shows '8:00 PM' in 12h mode), but the wheel that opens on tap is hard-coded to 24h: hour Picker is `ForEach(0..&lt;24)` shown as '%02d', minute is `0..&lt;60`, and there is NO AM/PM column. CLAUDE.md states 'the picker wheels also follow it (12h shows an AM/PM column)'. So a user in 12h mode sees '8:00 PM' but the wheel shows '20', which is the exact mismatch the convention forbids. SteppedWheel (EditorRowInteractions.swift:340-359) already implements the correct 12h hour(1-12)+minute+AM/PM layout, so the fix path is known. DSTimeField only feeds the Calendar add-event Starts/Ends fields (CalendarView.swift:1185/1192).
- **Recommendation:** Make DSTimeField's wheel branch on TimeFormatSetting.is24Hour the same way SteppedWheel does (12h: hour 1-12, minute, AM/PM column; 24h: current layout). Ideally reuse SteppedWheel by exposing a Date-backed minutes binding so the two time wheels share one implementation instead of two. Do not change clockString usage on the label.
- **Risk if applied:** Medium. Adding a 12h branch changes the picker UI in 12h mode; the underlying Date math must preserve AM/PM correctly (SteppedWheel's hour12/isPM bindings are the reference). If reused carelessly it could shift the stored hour. Low risk if the 24h branch is left exactly as-is and only the 12h case is added behind the existing is24 check.

### 🟠 MEDIUM — Hardcoded .font(.system(size:)) inside DSKit-era component views

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Components/SettingsComponents.swift:95`
  - `HumanProgram/Features/Settings/Components/SettingsComponents.swift:260`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:333`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:347`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:480-505`
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:25-29`
- **Problem:** CLAUDE.md: 'No hardcoded Color(hex:) / .font(.system(size:)) in views.' These shared component views use raw .font(.system(size:18/20/24/16 …)) for the back chevron, the AddNavButton '+', the keypad digits/letters/glyphs, the SteppedWheel ':' separators, and the DSCalendarView nav chevrons. Some are SF Symbol glyphs (icons), where .font(.system) is the standard sizing idiom and arguably acceptable, but the digit/letter/separator TEXT in GlassKeypad and SteppedWheel is plain text rendered with system font, not the app font / DSKit token — inconsistent with the rest of the file (which uses appFont/DSText).
- **Recommendation:** For text (keypad digits/letters, the ':' separators), route through appFont(...) or a DSKit text token so they scale with the chosen app font like everything else. For SF Symbol icon glyphs, this is the conventional approach; if the team wants strict conformance, use DSImageView(systemName:size:.font(...)) as SettingsRowContent already does. At minimum unify the keypad/separator text with appFont.
- **Risk if applied:** Medium. Changing the keypad/separator font size could shift glyph metrics and the carefully-tuned 50pt key height / wheel widths; would need a visual check. Icon-only changes are lower risk. Flagged for awareness, not a blind apply.

### 🟠 MEDIUM — DateFormatter allocated on every render in three date views

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:67-69`
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:93-95`
- **Problem:** monthTitle (DSCalendarView, line 67-69) and DSDateField.label (line 93-95) each build a fresh DateFormatter inside a computed property read on every body evaluation. DateFormatter creation is one of the most expensive Foundation operations, and these are recomputed during month stepping / scrolling. The CLAUDE.md efficiency rule explicitly calls out 'DateFormatter/Calendar built in hot paths'.
- **Recommendation:** Hoist the formatters to a shared cached static (e.g. a private static let with a fixed dateFormat) or a small cached helper, and reuse them. Behavior is identical since the format strings are constant.
- **Risk if applied:** Low. A cached DateFormatter with the same dateFormat produces identical strings. Only caveat: a shared static formatter is fine because these formats don't depend on a changing locale/calendar here, but to be safe keep them per-view static lets.

### 🟢 LOW — BlockColorPickerView mutates a global UISegmentedControl.appearance() from onAppear

- **Category:** best-practice | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Components/BlockColorPickerView.swift:122-128`
- **Problem:** onAppear sets `UISegmentedControl.appearance().setTitleTextAttributes(...)` globally for .normal and .selected to force the app font on the RGB/HSB/Spectrum segmented control. This is a process-wide UIKit appearance mutation triggered by a single popup appearing; it never gets reset, so it leaks to every other segmented control in the app and is order-dependent (whoever appears last wins). It also re-runs every time the picker opens.
- **Recommendation:** Either set this segmented-control appearance once at app launch (centralized, intentional), or scope it via a UIViewRepresentable wrapper around just this control instead of the global appearance proxy. At minimum, document that it's intentionally global. Behavior-wise the current code 'works' but is a side-effect-in-onAppear smell.
- **Risk if applied:** Medium. Moving/removing it changes the segmented control's font; if other screens silently rely on this global side effect, font would change there too. Investigate before touching.

### 🟢 LOW — AnchoredPopup uses UIScreen.main.bounds for keyboard overlap math

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Components/PlanningComponents.swift:200-204`
- **Problem:** Keyboard-overlap is computed as `UIScreen.main.bounds.height - frame.minY`. UIScreen.main is deprecated in newer SDKs and does not account for the popup's actual window in multi-scene/Stage Manager/iPad split scenarios; the keyboard frame is in screen coordinates while the popup positions itself in `geo` coordinates, so on a non-fullscreen window the lift could be off. On iPhone fullscreen (the only current target) it works, but it's a latent correctness gap.
- **Recommendation:** Derive the screen/window height from the view's own window (e.g. via the GeometryReader's coordinate space or a window-scene lookup) rather than UIScreen.main. Leave as-is if iPad/multi-scene is explicitly out of scope, but note it.
- **Risk if applied:** Medium. Changing the coordinate source could shift popup lift on the supported iPhone path; needs keyboard-up testing. Safe to leave; flagged as latent only.

### 🟢 LOW — IntervalWheel clamps amount only via onChange of unit, not when amount itself is edited

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:374-394`
- **Problem:** amountRange is `1...10` for hours and `1...59` for minutes, and the Picker only offers in-range values, so the wheel itself can't produce an out-of-range value. The onChange(of: unitIsHours) clamps amount&gt;10 when switching to hours and amount&lt;1 generally. But if `amount` is ever set out of band externally (e.g. a restored value of 30 with unitIsHours already true at first render), the Picker has no tag matching the bound value and SwiftUI wheel selection can silently reset/misbehave, and the clamp won't fire because unitIsHours didn't change.
- **Recommendation:** Add a clamp on first appearance (or an onChange(of: amount)) that snaps amount into amountRange regardless of how it got out of range, so a restored/seeded value can't leave the wheel with a non-existent selection. Verify against how callers seed amount/unitIsHours.
- **Risk if applied:** Low-Medium. Adding an onAppear clamp could change a seeded value if callers intentionally pass something the UI then snaps; check the Reminder editor's seeding before applying.

### 🟢 LOW — ColorPresetStore.add(_:) is dead code and a byte-identical duplicate of addToEmptySlot

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/BlockColorPickerView.swift:27-31`
  - `HumanProgram/Features/Settings/Components/BlockColorPickerView.swift:36-40`
- **Problem:** add(_:) (lines 27-31) and addToEmptySlot(_:) (lines 36-40) have identical bodies: uppercase, guard not-present and count &lt; max, append, persist. A grep across the whole app shows no caller of `.add(` on the store — only addToEmptySlot is wired up (line 138). So add(_:) is both unused and an exact duplicate.
- **Recommendation:** Delete add(_:) and keep addToEmptySlot, or keep one and have the other call it. Since add(_:) has no callers, removing it is the safest cleanup.
- **Risk if applied:** Very low. add(_:) has zero references; deleting it cannot change behavior. (Read-only report — no edit made.)

### 🟢 LOW — ColorPresetStore.isFull is unused

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/BlockColorPickerView.swift:48`
- **Problem:** `var isFull: Bool { presets.count &gt;= Self.maxPresets }` has no references anywhere in the app (grep for `.isFull` returns nothing). The grid already handles the full case structurally (it renders exactly maxPresets slots and the add/replace methods guard on count internally), so isFull is leftover API.
- **Recommendation:** Remove isFull, or if it is intended future API, leave a note; otherwise it is dead surface area.
- **Risk if applied:** Very low. No callers.

### 🟢 LOW — AnchorFrameKey/RowFrameKey rely on linear first(where:) scans over row frames per gesture event

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:91`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:166`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:189`
- **Problem:** Both recognizers hit-test the touched row with `rowFrames.first(where: { $0.value.contains(p) })` / `.contains(where:)` — a linear scan of the frame dictionary on every gesture begin (and shouldBegin runs on every pan attempt, including rejected vertical scrolls). For the small row counts in these editors this is negligible, but it is an O(n) scan in a per-touch path and the dictionary ordering means the 'first' matching row is nondeterministic if frames ever overlapped.
- **Recommendation:** Acceptable as-is for the current small lists; if row counts ever grow, sort/index by y-range or break early. Mainly note the nondeterministic-first-match if two row frames could overlap (they shouldn't with the current layout). No change needed now.
- **Risk if applied:** Very low. Leaving as-is is safe; only flagged for completeness.

### 🟢 LOW — GlassKeypad capsule key markup is copy-pasted three times

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:478-491`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:492-500`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:501-510`
- **Problem:** The three keyButton cases (.digit, .backspace, .done) each repeat the same trailing chrome: `.frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(Color.white.opacity(0.8)))` plus `.buttonStyle(.plain).a11yTapBorder(Capsule())`. The Color.white.opacity(0.8) capsule, the 50pt height, and the a11y border are duplicated and could drift (e.g. someone changes the capsule fill on one key only).
- **Recommendation:** Extract a private `keyChrome` ViewModifier (or a small wrapper view) that applies the capsule background, 50pt height, full width, .plain style and a11yTapBorder, and apply it to all three labels. The per-key content (digit text / icon) stays unique.
- **Risk if applied:** Low. Pure refactor of identical chrome; visual output unchanged if the extracted modifier matches the current chain exactly.

### 🟢 LOW — SettingsRowContent duplicates the DSText label block for destructive vs normal

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/SettingsComponents.swift:326-333`
- **Problem:** The if/else for `destructive` renders two near-identical DSText blocks differing only in the color argument: `DSText(label).dsTextStyle(.title3, Color.red)` vs `DSText(label).dsTextStyle(.title3)`, each followed by the same `.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)`. The shared modifiers are written twice.
- **Recommendation:** Compute the style once or factor the shared `.lineLimit(1).frame(...)` onto a single DSText whose color is chosen by the destructive flag (note: dsTextStyle's single-arg vs two-arg overloads differ per the DSKit gotchas, so this may need a small @ViewBuilder helper rather than a ternary on the color arg). Keep both overload forms but avoid repeating the frame/lineLimit.
- **Risk if applied:** Low. Behavior identical if the same dsTextStyle overload is used for each branch; the DSKit token overloading caveat means test that it still compiles (the two-arg form requires an explicit Color, which is already what the red branch uses).

### 🟢 LOW — WeekdayCircleSelector and WeekdayStrip each redeclare the same 1-7 letter table

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/PlanningComponents.swift:16-18`
  - `HumanProgram/Features/Settings/Components/PlanningComponents.swift:51-53`
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:17`
- **Problem:** The weekday letter table `[(1,"S"),(2,"M"),(3,"T"),(4,"W"),(5,"T"),(6,"F"),(7,"S")]` is declared independently in WeekdayCircleSelector (line 16) and WeekdayStrip (line 51), and DSCalendarView uses the parallel `["S","M","T","W","T","F","S"]` array (line 17). Three copies of the same Sun-first letter sequence; if the encoding/letters ever needed adjustment they'd have to change in lockstep.
- **Recommendation:** Define the (weekday, letter) table once (e.g. a static on a small WeekdaySymbols enum) and have both selector and strip read it; the calendar header can derive its letters from the same source. Pure data dedupe.
- **Risk if applied:** Very low. Same literal data centralized; no behavior change. Keep 1=Sun encoding exactly.

### 🟢 LOW — DateFieldRow (PlanningComponents) and DSDateField (DSDatePicker) overlap; DateFieldRow is a thin wrapper

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/PlanningComponents.swift:288-302`
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:87-120`
- **Problem:** DateFieldRow is a label + Spacer + DSDateField row used by the Schedule and Recurring editors (ScheduleEditorView.swift:180-181, RecurringTaskEditorView.swift:75-76). It hand-rolls an HStack with `DSText(label).dsTextStyle(.title3)` + `Spacer(minLength: 8)` + the field at a fixed height 34 — which is exactly the shape of a settings value row. It does not reuse SettingsRowContent's label+trailing layout, so the label styling/height/spacing can drift from the rest of the settings rows.
- **Recommendation:** Consider expressing DateFieldRow via SettingsRowContent(label:) { DSDateField(...) } (with hasTrailingAccessory) so it inherits the shared row metrics and the menu/centered inset logic, rather than a bespoke HStack. Low priority since it's small, but it is the kind of hand-rolled row the convention warns against.
- **Risk if applied:** Low-Medium. Routing through SettingsRowContent changes height/inset semantics (34 vs the row's 34 frame, plus the menu-pull logic) so it needs a visual check on both editors; safe only if the resulting layout matches. Flag, don't blind-apply.

### 🟢 LOW — BlurView is duplicated as a fallback in two places instead of one shared blur

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Components/PlanningComponents.swift:86-94`
  - `HumanProgram/Features/Settings/Components/PlanningComponents.swift:127-141`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:461-472`
- **Problem:** The pre-iOS-26 fallback pattern `BlurView(style: .systemX).clipShape(shape).ignoresSafeArea(...)` is written separately for PopupGlassBackground (uses .systemThinMaterial) and GlassKeypad.keypadGlass (uses .systemUltraThinMaterial). The glass/fallback split logic (`if #available(iOS 26.0) glassEffect else BlurView`) is repeated in three glass helpers (popupGlass background, hubTileGlass, keypadGlass) with slightly different parameters.
- **Recommendation:** Consider a single parameterized glass helper (style + corner radius + glassEffect variant) that all three call, so the iOS-26-vs-fallback branch lives in one place. Note the comments say hubTileGlass is intentionally separate from popupGlass for a rendering reason — so only the fallback BlurView wrapper, not the whole helper, may be worth unifying.
- **Risk if applied:** Medium. The owner explicitly kept hubTileGlass separate ([#22]) and tuned each material; consolidating risks a visual regression on the simulator-vs-device glass difference they already fought. Treat as a careful refactor, not a quick merge.

### 🟢 LOW — ReorderRecognizer and SwipePanRecognizer duplicate the scroll-view discovery + retry-install logic

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:68-85`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:145-160`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:239`
- **Problem:** Three coordinators (ReorderRecognizer, SwipePanRecognizer, KeyboardScrollNudge) each contain the identical `var v: UIView? = view; while let cur = v, !(cur is UIScrollView) { v = cur.superview }` enclosing-scroll-view walk, and the two recognizers additionally share the same 'guard recognizer == nil … if target missing, DispatchQueue.main.async retry install' pattern. This is the same plumbing copied three times.
- **Recommendation:** Extract a shared `UIView.enclosingScrollView` helper (mirrors the existing firstResponderInHierarchy extension) and, for the two recognizers, a small shared install-once-with-retry helper. Pure dedupe; each coordinator keeps its own recognizer type/handlers.
- **Risk if applied:** Low. Behavior identical if the extracted helpers reproduce the exact walk/retry. The retry-via-DispatchQueue.main.async is timing-sensitive, so keep it byte-equivalent.

### 🟢 LOW — SteppedWheel duration vs time branches repeat the same Picker scaffolding

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:314-360`
- **Problem:** The three layout branches (.duration, 24h-time, 12h-time) each rebuild an HStack of `.pickerStyle(.wheel)` pickers with nearly identical minute pickers (`ForEach(minuteOptions, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }` appears in both time branches) and the same `.frame(...,height: 150).padding(.vertical, 10).simultaneousGesture(...)` wrapper. The minute picker and hour picker markup are copy-pasted with small differences.
- **Recommendation:** Factor the minute wheel and the gesture/frame wrapper into small private subviews/helpers so the three modes differ only by which columns they include. Reduces drift between the 12h and 24h minute formatting.
- **Risk if applied:** Low. Refactor only; wheel widths (180/230) and heights must be preserved exactly to keep popup sizing correct.

### 🟢 LOW — BlockColorPickerView is a long multi-mode view mixing color math and UI

- **Category:** readability | **Effort:** large
- **Locations:**
  - `HumanProgram/Features/Settings/Components/BlockColorPickerView.swift:53-287`
- **Problem:** BlockColorPickerView is ~230 lines holding the swatch grid, three editor modes (hex/HSB/spectrum), channel/HSB sliders, spectrum drag math, and the RGB&lt;-&gt;hex&lt;-&gt;HSB sync helpers all in one type. The state-sync helpers (syncFromBinding/setWorking/syncHexField/applyHexField/applyHSB) and the editors could be separated for clarity, and the UIColor round-trips (applyHSB at 281-286, rgbToHSB at 290-294) are easy to get subtly wrong when buried in a big view.
- **Recommendation:** Optionally split the three editors into their own small views and move the color-conversion helpers into a tiny value type (ColorWorking) with unit-testable conversions. Not urgent; it works, but it's the densest file in this set.
- **Risk if applied:** Medium. A structural split touches the live color-editing flow; behavior must be preserved exactly (the binding writes colorHex live). Only worth doing with screenshots/tests.


---

## Settings misc screens (Customization / Format / Accessibility / Security / Import-Export / FactoryReset / About / Licenses / Terms / Tutorial / CatCorner)

> Overall this area is in good shape: every Settings screen correctly composes from the shared SettingsScreen/SettingsGroup/SettingsRowContent/SettingsNavRow/SettingsSelectRow/SettingsToggleRow/SettingsButtonRow primitives rather than hand-rolling rows, and DSKit text/image components are used consistently. The two destructive-confirm screens correctly use type-to-confirm rather than a confirmation dialog. The main issues are: (1) a dead/leftover PlaceholderSettingsView stub plus a redundant double-evaluation in the About gate; (2) several hardcoded colors and .font(.system(size:)) calls inside views, which violate the DSKit "no hardcoded Color(hex:)/.font(.system(size:))" rule (the hardcoded "lightBlue" RGB literal is duplicated in two files); (3) near-duplicated chunks of view code — the type-to-confirm destructive screen (FactoryReset vs HprgmRestoreConfirm), the four nearly identical toolbar "Load/Import/Done/Save" buttons in ImportExport, and the two identical onboarding/reference scaffolds in Terms and Tutorial — that should be shared; and (4) a few small efficiency/readability nits (per-row DateFormatter allocation, an O(n) UIImage(named:) probe loop at view init). None of the findings are behavioral bugs; the gate logic, snapshot protection, and reset/restore flows are correct. Also note the file-level comments in Customization/Format ("not yet applied app-wide") suggest persisted selections may not be wired into live rendering — out of scope to verify here but worth the owner confirming.

### 🟠 MEDIUM — Hardcoded .font(.system(size:)) inside views (DSKit rule violation)

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Customization/CustomizationView.swift:119`
  - `HumanProgram/Features/Settings/Customization/CustomizationView.swift:121`
  - `HumanProgram/Features/Settings/Customization/CustomizationView.swift:134`
  - `HumanProgram/Features/Settings/CatCornerView.swift:47`
  - `HumanProgram/Features/Settings/Legal/TermsOfServiceView.swift:61`
- **Problem:** CLAUDE.md states: 'No hardcoded Color(hex:) / .font(.system(size:)) in views.' Several views use raw .font(.system(size:)): the FontSizeSlider 'A' glyphs at sizes 15 and 27 (CustomizationView:119,121), the Image checkbox glyph at size 22 in Terms (TermsOfServiceView:61), and the empty-state icon at size 48 in CatCorner (CatCornerView:47). Some are arguably justified (the slider 'A's are intentionally fixed and font-independent; CatCorner is the intentionally non-DSKit immersive black view), but they are not annotated as deliberate exceptions, so they read as violations.
- **Recommendation:** For the genuinely fixed-size affordances (the font-size slider A's), either route through a DSKit/app token or add a one-line comment marking them as an intentional fixed-metric exception so future audits don't re-flag them. For the Terms checkbox glyph, prefer DSImageView with a DSKit size token. Leave CatCorner as-is (already documented as intentionally non-DSKit) but consider a note.
- **Risk if applied:** Low for the comment-only path. If actually swapping to DSKit sizing, verify the slider 'A's stay fixed-size (they must NOT scale with the app font, by design) — getting that wrong would make the control move when the font changes.

### 🟠 MEDIUM — FactoryReset clearUserDefaults whitelist can silently drift from the real preference keys

- **Category:** data-integrity | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/FactoryResetView.swift:206-221`
- **Problem:** clearUserDefaults() hardcodes a 5-key list (hp.lock.enabled, hp.lock.biometric, hp.lock.timeout, selectedCalendarIds, hp.onboarded) but the app stores many more user-preference keys that CLAUDE.md enumerates as part of app state — e.g. settings.bgLight/bgDark, settings.fontChoice, settings.fontSizeStep, settings.appearanceMode, settings.appIcon, settings.dateFormat, settings.timeFormat, settings.a11yButtonBorders, hp.permissionsAsked. After a factory reset these preference keys are NOT cleared, so a 'reset to factory state' leaves the user's old font/background/appearance/icon/format/accessibility choices in place. There is no shared registry of preference keys, so this list will keep drifting as keys are added (the same risk the .hprgm bundle guards against, but here it is unguarded).
- **Recommendation:** Centralize the set of user-preference UserDefaults keys in one place (a constant list shared with the .hprgm export/import) and have factory reset clear that full set, then re-set hp.permissionsAsked = true as it does now. Confirm with the owner whether a factory reset is INTENDED to wipe customization (likely yes, given 'restore the app to its factory state and wipe all data'). Do not change the SwiftData deletion logic.
- **Risk if applied:** Medium — this changes what a reset wipes. It is plausibly an intentional partial reset, so confirm intent with the owner before changing; if applied, verify reset returns font/background/appearance/icon/format to defaults and does not break the onboarding re-run (hp.permissionsAsked must still end up true).

### 🟠 MEDIUM — Hardcoded lightBlue RGB color literal duplicated across Terms and Tutorial (and ad-hoc in About)

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Legal/TermsOfServiceView.swift:21`
  - `HumanProgram/Features/Settings/Tutorial/TutorialView.swift:13`
- **Problem:** Color(red: 0.42, green: 0.69, blue: 0.99) is written identically as a private `lightBlue` in both TermsOfServiceView and TutorialView. This both duplicates a magic color and violates the DSKit rule against hardcoded Color literals in views (AppColors/AppTypography or the DSKit theme should own brand colors). If the brand accent changes, two copies must be edited and will drift.
- **Recommendation:** Extract the accent color into one shared token (a DSKit theme color or an AppColors constant) and reference it from both screens. Do not change the rendered color value.
- **Risk if applied:** Low — a pure refactor to a shared constant keeps the exact same color. Risk only if the shared token is later changed; the extraction itself is behavior-preserving.

### 🟠 MEDIUM — Two near-identical type-to-confirm destructive screens (FactoryReset vs HprgmRestoreConfirm)

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/FactoryResetView.swift:92-149`
  - `HumanProgram/Features/Settings/ImportExportView.swift:321-351`
- **Problem:** FactoryResetView and HprgmRestoreConfirmView share an almost identical layout: same SettingsScreen(centered: true, manualKeyboardAvoidance: true) + same red exclamationmark.triangle.fill (size 56) + DSText title + DestructiveWarningText + 'Type X to confirm' subheadline + identical TextField styling (autocorrectionDisabled, .never autocapitalization, appFont(18), center, vertical 14 / horizontal 20, Color.primary.opacity(0.06) rounded background) + identical red Capsule confirm button with the same contentLift:32 and resignFirstResponder dance. Only the confirm word ('RESET' vs 'RESTORE'), title, warning text, and the action differ. DestructiveWarningText was already shared, but the surrounding scaffold was copy-pasted. Two copies means a layout tweak (e.g. the keyboard-gap behavior) must be made twice and can drift.
- **Recommendation:** Extract a shared DestructiveConfirmScreen view that takes: title, warning text, confirm word, button label, and an onConfirm closure; have both screens compose it. Keep the existing resignFirstResponder + contentLift behavior inside the shared view. Do not change the confirm words or actions.
- **Risk if applied:** Medium — these are the app's two most destructive flows (wipe-all and replace-all). Refactor must preserve: the exact confirm-word match (uppercased == RESET/RESTORE), the disabled state, the resignFirstResponder-before-interstitial step, and the keyboard-avoidance-off layout. Worth doing but test both flows end to end after.

### 🟢 LOW — Hardcoded Color literals (.gray, .white, .black opacity, Color.primary.opacity) for swatch borders / inputs

- **Category:** best-practice | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Customization/CustomizationView.swift:79`
  - `HumanProgram/Features/Settings/Customization/CustomizationView.swift:139-141`
  - `HumanProgram/Features/Settings/Customization/CustomizationView.swift:303`
  - `HumanProgram/Features/Settings/FactoryResetView.swift:117`
  - `HumanProgram/Features/Settings/ImportExportView.swift:128`
  - `HumanProgram/Features/Settings/ImportExportView.swift:336`
- **Problem:** Selection-ring borders use Color.gray.opacity(...) (CustomizationView:79,303), the slider thumb uses Color.white + .black.opacity shadow (CustomizationView:139-141), and the type-to-confirm / TextEditor backgrounds use Color.primary.opacity(0.06). These are raw SwiftUI colors rather than DSKit theme tokens. They are low-risk (system colors adapt to dark mode) but are not theme-driven, so the selection ring / input chrome can't be restyled centrally.
- **Recommendation:** Where practical, move these to a shared DSKit theme color or an AppColors token (e.g. a single 'selectionRing' and 'inputFieldFill' token). Keep the same visual result. Low priority.
- **Risk if applied:** Low — these are cosmetic. A token swap that preserves the resolved color is behavior-neutral; just verify dark-mode appearance is unchanged.

### 🟢 LOW — ExportView empty-state caption 'Export a full app state.' borders on filler

- **Category:** best-practice | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/ImportExportView.swift:89`
- **Problem:** Below the single 'Export Backup' button, ExportView shows DSText('Export a full app state.'). CLAUDE.md's no-filler rule says to drop a sentence if the screen works without it. The button label 'Export Backup' under a 'Full Backup' group header already conveys this; the caption is borderline-redundant explanatory copy (and grammatically odd — 'a full app state').
- **Recommendation:** Consider removing the caption (the CSV-requirements DSText at line 155 is a genuine format requirement and should stay; this export caption is decorative). Owner's call — flagging per the no-filler convention.
- **Risk if applied:** None — removing a caption does not affect behavior. Cosmetic; confirm with owner since it's a copy decision.

### 🟢 LOW — FactoryReset error path silently swallows a partial-delete failure

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/FactoryResetView.swift:161-180`
- **Problem:** performReset() wraps deleteAllModels()+save() in a do/catch; on failure it just calls dismiss() with the comment that deletes 'may be partial'. The user typed RESET expecting a full wipe, but on error they are returned to Settings with possibly half-deleted data and no indication anything went wrong (no error message, isResetting left true is avoided only because the view dismisses). A partial wipe of SwiftData models is a data-integrity hazard the user can't see.
- **Recommendation:** At minimum surface a non-blocking error (the screen already has no error state — add one like the Restore screen's `error` DSText) instead of silently dismissing, OR perform the deletes so a failure rolls back. Do not auto-retry. Keep the happy path unchanged.
- **Risk if applied:** Low-to-medium — only the failure branch changes. Must not alter the success path (interstitial → onboarding re-run). Adding a visible error is safe; changing delete-to-transactional is riskier and should be scoped carefully.

### 🟢 LOW — ImportSelectionView seeds 'select all' via .onAppear, which re-runs on every appearance

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/ImportExportView.swift:197`
  - `HumanProgram/Features/Settings/ImportExportView.swift:224`
- **Problem:** selected starts empty and is filled to 'all rows' in .onAppear only when selected.isEmpty. If the user intentionally deselects every row (selected becomes empty) and the view re-appears (e.g. returning from the pushed summary via a back swipe before Done pops everything), the .onAppear guard sees selected.isEmpty == true and re-selects all rows, silently undoing the user's deselection. The guard conflates 'never initialized' with 'user cleared everything'.
- **Recommendation:** Track an explicit 'didSeed' flag (or seed selected = all in an init/task that runs once) instead of inferring first-run from isEmpty, so an intentional empty selection is not re-populated. Behavior on first appearance stays identical (all selected).
- **Risk if applied:** Low — only affects the edge case of an emptied selection on re-appear; first-run behavior is unchanged. Verify the normal flow (open → Import) still defaults to all-selected.

### 🟢 LOW — DateFormatView/TimeFormatView/Customization screens persist selections that comments say aren't applied app-wide

- **Category:** claude-md-inconsistency | **Effort:** large
- **Locations:**
  - `HumanProgram/Features/Settings/Format/FormatView.swift:4-6`
  - `HumanProgram/Features/Settings/Customization/CustomizationView.swift:4-6`
- **Problem:** File-level comments state the Format and Customization controls 'persist their selections (@AppStorage) but are not yet applied' to live rendering. CLAUDE.md requires every displayed clock time to go through clockString (which reads settings.timeFormat) and date display to honor settings.dateFormat. If the wiring is genuinely incomplete, a control that appears functional (it shows a checkmark and saves) but does nothing visible is the kind of 'decorative-only' surface CLAUDE.md warns against. This is a flag for the owner, not necessarily a code defect in this file — the formatters live elsewhere.
- **Recommendation:** Confirm whether settings.dateFormat / settings.timeFormat / font / appearance / background / appIcon are actually consumed by the live rendering paths (clockString already reads timeFormat). If any selection is purely stored-but-ignored, either wire it up or remove the control. No change to these files unless the wiring is confirmed missing.
- **Risk if applied:** Out of scope to change here. Investigation only; any wiring change touches many screens and must be verified broadly. Listed so it isn't missed.

### 🟢 LOW — Leftover PlaceholderSettingsView stub is dead code

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/SettingsView.swift:40-50`
- **Problem:** PlaceholderSettingsView is defined but never referenced anywhere in the codebase (grep finds only its definition). It also renders the filler string "&lt;title&gt; settings coming soon", which violates the no-filler-copy rule. It is a leftover scaffold stub from before the real settings screens were built.
- **Recommendation:** Delete the PlaceholderSettingsView struct entirely. Confirm with a project-wide search that nothing references it (it currently does not).
- **Risk if applied:** Essentially none — it is unreferenced. Only risk is if it is wired up by a name-based route somewhere not found by grep, which is not the case here.

### 🟢 LOW — About gate computes the same condition twice with a redundant OR

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/AboutView.swift:60-73`
- **Problem:** handleDeveloperTap sets tempPage.dayComplete = appState.streakStats.currentStreak &gt; 0 || isCurrentDayComplete(), and isCurrentDayComplete() returns exactly appState.streakStats.currentStreak &gt; 0. Both sides of the || evaluate the identical expression, so the OR and the helper are pure redundancy. It reads as if two different conditions are being combined when they are not. (The logic itself is correct — StreakCalculator's currentStreak only counts backward starting at today, so &gt;0 implies today is complete — so the gate behaves correctly; this is purely confusing dead code.)
- **Recommendation:** Replace with a single clear expression, e.g. tempPage.dayComplete = appState.streakStats.currentStreak &gt; 0, and remove the isCurrentDayComplete() helper. Keep the EasterEggGateService call unchanged.
- **Risk if applied:** None to behavior — the boolean result is identical. Safe to apply.

### 🟢 LOW — Per-row DateFormatter allocation in import-selection subtitle

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/ImportExportView.swift:230-235`
- **Problem:** subtitle(_:) builds a fresh DateFormatter() with dateFormat 'MMM d, yyyy' for every row that has a date, and it is called from inside the ForEach over flow.rows (line 216). DateFormatter creation is relatively expensive and this is in a SwiftUI body path, so for a large import list it allocates one formatter per row per render. CLAUDE.md flags 'DateFormatter/Calendar built in hot paths'.
- **Recommendation:** Hoist a single static/shared DateFormatter (or use a cached formatter) instead of constructing one per row. Keep the same format string and output.
- **Risk if applied:** Low — a cached formatter produces identical strings. Ensure the cached formatter's locale/timezone matches the current behavior (default DateFormatter uses current locale; keep that).

### 🟢 LOW — CatCorner probes UIImage(named:) for 20 assets at view init on the main thread

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/CatCornerView.swift:12-13`
- **Problem:** The `photos` array is computed by a stored property initializer that runs UIImage(named: 'cat_01'..'cat_20') for all 20 candidate names every time CatCornerView is constructed, to filter to the ones that exist. UIImage(named:) loads/caches the image, so this both touches disk and happens synchronously during view init on the main thread. With the gallery currently empty (owner will provide photos), this is 20 failed lookups each push.
- **Recommendation:** Either move the existence probe off the init path (compute once lazily / cache the resolved names) or, since the asset set is known, derive the list from a known count without instantiating UIImage just to test existence. Behavior (which photos show) must stay identical.
- **Risk if applied:** Low — must keep the same 'only show assets that exist' result so a missing asset never renders blank. Verify the resolved photo list is unchanged.

### 🟢 LOW — BiometryInfo evaluates an LAContext policy check on every property access

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/SecuritySettingsView.swift:332-349`
- **Problem:** BiometryInfo.label and .icon each read the computed `ctx` property, which constructs a fresh LAContext and calls canEvaluatePolicy every time. In SecuritySettingsView these are read via computed view properties (biometryLabel/biometryIcon at lines 83-84) referenced in the menu body, so each body evaluation does two LAContext policy evaluations (and FaceIDSetupView reads label/icon several more times). canEvaluatePolicy is not free. The biometry type does not change during a screen's lifetime.
- **Recommendation:** Cache the (available, type) result once (e.g. a lazily-computed static, or compute once in onAppear into @State) rather than re-running canEvaluatePolicy on every access. Output strings stay identical.
- **Risk if applied:** Low — caching the biometry type for the screen's lifetime matches real-world behavior (it can't change mid-session). Safe.

### 🟢 LOW — Restore preview is parsed twice (preview then importData re-reads)

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/ImportExportView.swift:361-368`
- **Problem:** restore() calls HprgmImportService().preview(fileURL: url) to decode the bundle, then constructs a second HprgmImportService() and calls importData(bundle, context:). It allocates the service twice and the preview decode is only used to obtain `bundle` for the import. If preview() and importData() each do file/JSON work, the file may be decoded redundantly. Minor, but it reads as accidental.
- **Recommendation:** Reuse one HprgmImportService() instance and pass the already-decoded bundle straight to importData (which is what it does) — just hoist the single service instance. If preview() is required for validation, keep it but document why both are needed. No behavior change.
- **Risk if applied:** Low — combining the two service instances into one is behavior-neutral as long as preview() side effects (validation) are preserved. Verify a corrupt-file path still surfaces the error.

### 🟢 LOW — Four copy-pasted toolbar text buttons (Load / Import / Done) in ImportExport

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/ImportExportView.swift:114-120`
  - `HumanProgram/Features/Settings/ImportExportView.swift:202-205`
  - `HumanProgram/Features/Settings/ImportExportView.swift:251-254`
- **Problem:** The trailing toolbar buttons in TextBacklogImportView ('Load'), ImportSelectionView ('Import'), and ImportSummaryView ('Done') are byte-for-byte the same except the label string and action: Text(label).font(appFont(18)).foregroundStyle(.primary).frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8).contentShape(Rectangle()).a11yTapBorder(Rectangle()). This is the same 44x44 tappable toolbar-button pattern repeated; the project already has an AddNavButton convention for toolbar icons, but no shared text-button equivalent.
- **Recommendation:** Add a small shared TextNavButton(label:action:) helper (mirroring AddNavButton) and use it for all three, so the tap-target/min-size/contentShape/a11y border are defined once. Behavior-identical.
- **Risk if applied:** Low — pure extraction of identical markup. Verify the 44x44 hit area and a11y border are preserved.

### 🟢 LOW — Terms and Tutorial duplicate the onboarding/reference scaffold and frozen-header pattern

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Legal/TermsOfServiceView.swift:23-50`
  - `HumanProgram/Features/Settings/Tutorial/TutorialView.swift:15-42`
- **Problem:** Both views implement the same two-mode shape: a `case .reference` that wraps header+body in SettingsScreen(centered: true), and a `case .onboarding` that builds ZStack { SettingsBackground(); VStack { frozen header padded 24/40/18; ScrollView { body + bottom button, padded 24, bottom 40 } } }. The frozen-header-over-scroll onboarding scaffold and its exact paddings (24 horizontal, 40 top, 18 bottom, 40 bottom) are duplicated verbatim. A change to the onboarding chrome must be made in both.
- **Recommendation:** Extract a shared OnboardingScrollScaffold(header:content:) (and rely on SettingsScreen for the reference mode) so the frozen-header layout and paddings live in one place. Keep the same paddings and behavior.
- **Risk if applied:** Low-to-medium — these are onboarding gates the user must pass through. Preserve the frozen-header-stays-while-body-scrolls behavior and the disabled-until-checked Confirm in Terms. Test the onboarding run after refactor.


---

## Security UI + Gate + Routines + Stats

> Overall these screens are reasonably well-factored: PINEntryView is correctly shared by the lock screen and the various PIN flows, the Routine editor reuses the EditorRowInteractions infrastructure as the convention requires, and Stats keeps streak math in pure helpers. However there are real issues. The biggest are (1) heavy violations of the "no hardcoded .font(.system(size:)) / Color in views, use DSKit" convention across PINEntryView, SudokuGateView, RoutinesView, RoutineEditorView and StatsView; (2) Stats recomputes streak runs and week bars from scratch on every body render (and inside a 260-page TabView), an O(n) work-per-render and O(pages*260) latent cost, with DateFormatters allocated in hot paths; (3) the Sudoku gate uses fragile "r,c" string-keyed Set lookups instead of integer coordinates, and on solve presents GameContainerView directly without re-checking GameAccessService; (4) the exercise-streak definition (title contains "exercise") is a brittle string match that can silently miss/over-count. None of the recommended fixes change behavior if applied carefully.

### 🟠 MEDIUM — Exercise streak detection by title.contains("exercise") is a brittle string match

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Stats/StatsView.swift:134`
  - `HumanProgram/Features/Stats/StatsView.swift:137`
- **Problem:** exerciseRuns qualifies a day if any completed task's lowercased title contains the substring "exercise". This silently misclassifies: a task titled "Exercise the dog" or "Exorcise"-typo-aside any unrelated task containing the substring counts as an exercise streak, while a legitimately exercise-sourced task not literally containing the word does not. The app already models exercise/recurring sources structurally (sourceType/sourceId on tasks), so deriving an exercise streak from free-text title is fragile and can desync from what the user means.
- **Recommendation:** Drive the exercise-streak qualifier off the task's structured source (sourceType == exercise / the routine/exercise sourceId) rather than a title substring, if such a field is available on DailyPageTask. If only titles are available, at least document the limitation. Verify against the model before changing; this is a semantics change so confirm with owner.
- **Risk if applied:** Medium. Changes which days count as exercise days, i.e. the displayed streak numbers. This is a behavior change and must be owner-approved; do not apply silently.

### 🟠 MEDIUM — Hardcoded .font(.system(size:)) and raw colors throughout views violate the DSKit convention

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Security/PINEntryView.swift:38`
  - `HumanProgram/Features/Security/PINEntryView.swift:55`
  - `HumanProgram/Features/Security/PINEntryView.swift:83`
  - `HumanProgram/Features/Security/PINEntryView.swift:118`
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:46`
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:123`
  - `HumanProgram/Features/Routines/RoutinesView.swift:52`
  - `HumanProgram/Features/Routines/RoutinesView.swift:58`
  - `HumanProgram/Features/Routines/RoutinesView.swift:74`
  - `HumanProgram/Features/Routines/RoutineEditorView.swift:73`
  - `HumanProgram/Features/Routines/RoutineEditorView.swift:98`
  - `HumanProgram/Features/Stats/StatsView.swift:49`
  - `HumanProgram/Features/Stats/StatsView.swift:101`
- **Problem:** CLAUDE.md states views must use DSKit (DSText/DSImageView/.dsTextStyle) with no hardcoded .font(.system(size:)) and that AppColors/raw Color use is legacy. These files use .font(.system(size:)) for SF Symbol icons, the masked PIN field text, the big streak number, the Sudoku digits, and the routine emoji/name, plus raw Color.white.opacity(...) / Color.red / Color.primary.opacity(...). The convention is applied unevenly: some siblings (the +/back chevrons) appear elsewhere via shared AddNavButton, but these reimplement the icon inline. This is mostly stylistic, but it is the project's most-emphasized UI rule and these are clear partial violations.
- **Recommendation:** Where a DSKit equivalent exists, route through it: SF Symbols via DSImageView(systemName:size:.font(...),tint:.color(.primary)); the masked PIN text, streak number, emoji and Sudoku digit through DSText/.dsTextStyle or at minimum appFont(...) helpers already used elsewhere in these same files. Note some of these (icon glyph sizing, the 40pt emoji, the 64pt cell) are genuine fixed-size design elements that may legitimately need system sizing; flag with the owner which are intentional rather than blanket-converting.
- **Risk if applied:** Low-to-medium. Pure presentation; mis-mapping a DSKit text token could shift a font size or color slightly. Should be done element-by-element with a visual check, not a sweep.

### 🟠 MEDIUM — Stats recomputes all streak runs and week bars on every body render (and 260 times in the TabView)

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Stats/StatsView.swift:21`
  - `HumanProgram/Features/Stats/StatsView.swift:113`
  - `HumanProgram/Features/Stats/StatsView.swift:130`
  - `HumanProgram/Features/Stats/StatsView.swift:134`
  - `HumanProgram/Features/Stats/StatsView.swift:181`
  - `HumanProgram/Features/Stats/StatsView.swift:192`
  - `HumanProgram/Features/Stats/StatsView.swift:149`
- **Problem:** pageByDate (line 21) rebuilds a dictionary over allPages every time it is read. completionRuns and exerciseRuns (130/134) each call runs(), which re-sorts allPages and walks every page, and both are read on every body render via streakRow. The week chart TabView (181) eagerly builds ForEach(0..&lt;260) — and weekChart-&gt;weekDays (192/149) calls pageByDate and filters tasks per page for each of 260 pages, so a body render can do ~260 * 7 dictionary lookups plus rebuild pageByDate repeatedly. As page history grows this is O(pages) rebuilt per render and the 260-week fan-out is constant but large. SwiftUI re-runs body frequently (state changes, scrolling), so this is real recomputation in a hot path.
- **Recommendation:** Compute pageByDate, completionRuns, and exerciseRuns once (e.g. cache derived values keyed off allPages, or compute in an onChange/onAppear into @State) rather than as computed properties read every render. TabView already lazily renders pages, but offset(forStatsPage:) lets you compute only the visible week; consider not materializing all 260 charts' data. Behavior is identical; only timing of computation changes.
- **Risk if applied:** Medium. Caching derived state must invalidate correctly when allPages changes (use the @Query array identity / onChange) or stats could go stale. Needs care, but no behavior change if invalidation is wired right.

### 🟠 MEDIUM — Sudoku gate presents the game directly on solve without re-checking GameAccessService

- **Category:** logic-structure | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:78`
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:90`
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:97`
  - `HumanProgram/Features/Settings/AboutView.swift:62`
- **Problem:** CLAUDE.md says GameAccessService is the only bridge and all unlock logic must go through it. The actual day-complete gate runs upstream in AboutView.handleDeveloperTap (it builds a synthetic DailyPage and calls gateService.shouldRevealGate) BEFORE the Sudoku is shown; once SudokuGateView is presented, solving the puzzle (checkSolution at 90) presents GameContainerView() directly (78) with no re-verification that the day is still complete. So once the gate view is open, the puzzle is the only barrier and the canonical access check is not consulted at the point of entering the game. If the gate view is ever reachable by another path, or the day-complete state changes while the puzzle is up, the game opens without GameAccessService approving it.
- **Recommendation:** Re-assert access at the moment of presenting GameContainerView (pass a GameAccessService check or a closure from AboutView that re-evaluates today's real DailyPage), so the single-bridge invariant holds at the entry point, not just at reveal. Do not change the puzzle UX. Confirm with owner whether the upstream-only check is intentional for the stub before changing.
- **Risk if applied:** Medium. Adding a re-check could, if the proxy and the real page disagree, prevent the game from opening in a state the owner currently considers valid. Needs owner confirmation of intended semantics; behavior could shift at the edge.

### 🟢 LOW — Sudoku gate uses string-keyed "r,c" Set for given positions instead of integer coordinates

- **Category:** best-practice | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:13`
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:29`
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:62`
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:84`
- **Problem:** givenPositions is a Set&lt;String&gt; of "row,col" strings, and membership is tested by interpolating "\(r),\(c)" in three places (29, 62, 84). String interpolation + hashing for what is a tiny coordinate set is non-idiomatic and fragile (a stray space or format change silently breaks matching). It also allocates a String per cell per render at line 62.
- **Recommendation:** Use a Set&lt;Coordinate&gt; where Coordinate is a Hashable struct/tuple of (Int,Int), or simply a [[Bool]] given-mask. Lookups become value comparisons with no string allocation. Behavior is identical for the fixed 4x4 puzzle.
- **Risk if applied:** Very low. Self-contained to this file; the puzzle data is static.

### 🟢 LOW — PIN shake animation uses a chain of DispatchQueue.main.asyncAfter timers that can overlap

- **Category:** best-practice | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Security/PINEntryView.swift:144`
  - `HumanProgram/Features/Security/PINEntryView.swift:147`
- **Problem:** triggerShake schedules five independent asyncAfter closures to step shakeOffset. If shake is triggered again rapidly (e.g. two wrong PINs in quick succession, or done()+onChange both firing) the un-cancelable timers from the previous shake overlap the new one, producing a janky offset. It also drives an offset via withAnimation inside dispatched closures rather than a single keyframe/phase animation.
- **Recommendation:** Replace with a single SwiftUI animation primitive (a phase/keyframe animator or a one-shot withAnimation on a discrete state) so re-triggering cleanly restarts. Purely an animation-quality improvement; the visual intent is unchanged.
- **Risk if applied:** Low. Cosmetic; ensure the field still clears on shakeToken change (currently done separately at line 106).

### 🟢 LOW — DateFormatter allocated inside computed properties / per-bar accessors (hot paths)

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Stats/StatsView.swift:160`
  - `HumanProgram/Features/Stats/StatsView.swift:216`
  - `HumanProgram/Features/Stats/StatsView.swift:232`
- **Problem:** DateFormatter is constructed fresh on each access: weekLabel (160) builds one per render; WeekBar.shortDay (216) builds one per bar per render (7 bars * up to 260 charts); streakDateString (232) builds one per call. DateFormatter creation is comparatively expensive and these run in render paths driven by the TabView. CLAUDE.md's efficiency guidance explicitly calls out building DateFormatter/Calendar in hot paths.
- **Recommendation:** Hoist these formatters to static lets (e.g. a private static let shortDayFormatter / monthDayFormatter / fullDateFormatter) reused across calls. Output is identical; only allocation is removed.
- **Risk if applied:** Very low. Static formatters with fixed dateFormat are safe to share; no locale/behavior change.

### 🟢 LOW — runs() re-sorts allPages on every call even though pageByDate already exists

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Stats/StatsView.swift:113`
  - `HumanProgram/Features/Stats/StatsView.swift:114`
- **Problem:** runs() maps allPages to start-of-day dates and sorts them on every invocation, and it is invoked twice per render (completionRuns + exerciseRuns). allPages already arrives sorted by date from @Query(sort:\DailyPage.date, .forward), so the extra map+sort is redundant work repeated each render. Combined with the per-render recomputation noted above, this compounds.
- **Recommendation:** Reuse the already-sorted pageByDate keys (or the already-sorted allPages dates) instead of re-sorting inside runs(); compute the sorted date list once. Output identical.
- **Risk if applied:** Very low. Confirm allPages truly stays sorted (it is, via @Query sort) before dropping the local sort.

### 🟢 LOW — done() failure path and onChange(shakeToken) both call triggerShake / clear entry, with split responsibility

- **Category:** logic-structure | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Security/PINEntryView.swift:104`
  - `HumanProgram/Features/Security/PINEntryView.swift:140`
- **Problem:** done() (140) calls triggerShake() on a too-short entry but does NOT clear entry, whereas the onChange(of: shakeToken) handler (104) both shakes and clears entry. So a short-PIN submit shakes but leaves the digits; a parent-driven wrong-PIN (shakeToken bump) shakes and clears. The two 'wrong' paths behave inconsistently and the clearing logic is split between the view's own validation and the parent's token. This is a latent UX inconsistency and makes the entry-clearing contract unclear.
- **Recommendation:** Centralize: have done()'s short-entry branch route through the same clear+shake path, or deliberately document why short-PIN keeps the digits while a rejected PIN clears them. No external API change needed.
- **Risk if applied:** Low. Changing whether a short-PIN clears the field is a minor UX change; confirm intended behavior before unifying.

### 🟢 LOW — Routine editor and Stats top bars duplicate the same hand-rolled chevron/back HStack

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Routines/RoutinesView.swift:50`
  - `HumanProgram/Features/Stats/StatsView.swift:47`
  - `HumanProgram/Features/Security/PINEntryView.swift:34`
- **Problem:** The leading back chevron (Image systemName chevron.left, font .system(size:18,weight:.semibold), 44x44, contentShape, a11yTapBorder, onTapGesture dismiss) is reproduced almost verbatim in RoutinesView.topBar, StatsView.topBar, and PINEntryView's back block — and CLAUDE.md notes a shared AddNavButton already exists for the trailing '+'. CLAUDE.md's #1 UI rule is to never copy-paste a view chunk; this back-button markup is exactly that, copied across at least three of my files (and likely more app-wide). When the back affordance changes it must be edited in every copy.
- **Recommendation:** Extract a shared BackNavButton (mirroring AddNavButton) and a shared top-bar wrapper used by RoutinesView, StatsView and PINEntryView. Behavior identical; just consolidates the markup.
- **Risk if applied:** Low. Mechanical extraction; ensure each call site keeps its own dismiss/onBack closure and frost/padding.

### 🟢 LOW — Routine name placeholder uses 'Untitled'/'📋' fallbacks duplicated across tile and editor

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Routines/RoutinesView.swift:74`
  - `HumanProgram/Features/Routines/RoutinesView.swift:75`
  - `HumanProgram/Features/Routines/RoutineEditorView.swift:69`
  - `HumanProgram/Features/Routines/RoutineEditorView.swift:185`
- **Problem:** The empty-title fallback string 'Untitled' and the empty-emoji fallback '📋' are hardcoded in multiple spots: RoutineTile (74/75), the editor's read-mode title (69), and the item rowFace (185). These display-default literals are copy-pasted; if the placeholder wording changes it must be updated in several places and they can drift. CLAUDE.md also leans toward leaving empty values blank rather than placeholder text, so the chosen fallback should be defined once and decided deliberately.
- **Recommendation:** Define the display fallbacks once (e.g. a small computed displayTitle / displayEmoji on the draft/model or a shared constant) and reuse. No behavior change.
- **Risk if applied:** Very low. Pure consolidation of literals.

### 🟢 LOW — DSTextTitle helper in PINEntryView duplicates an app-wide title style with a misleading DSKit-implying name

- **Category:** readability | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Security/PINEntryView.swift:156`
  - `HumanProgram/Features/Security/PINEntryView.swift:160`
- **Problem:** A private DSTextTitle struct wraps Text(...).font(appFont(22, bold:true)). The name starts with 'DS' (implying DSKit) but it deliberately avoids DSKit and reimplements a .title2-ish style with a raw appFont. This both duplicates the title styling that DSText(.title2) provides elsewhere and uses a name that misleads future readers into thinking it is a DSKit component.
- **Recommendation:** Either use DSText with the appropriate title style here (consistent with the rest of the app) or rename the helper to something non-DS (e.g. PINTitleText) and add a one-line note on why DSKit is intentionally avoided. Cosmetic.
- **Risk if applied:** Very low. Rename is trivial; switching to DSText could change the title's exact metrics, so verify visually if you go that route.

### 🟢 LOW — Two magic 'current-week' constants (259 and 260) must be kept in lockstep by hand

- **Category:** sloppy | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Stats/StatsView.swift:16`
  - `HumanProgram/Features/Stats/StatsView.swift:166`
  - `HumanProgram/Features/Stats/StatsView.swift:167`
  - `HumanProgram/Features/Stats/StatsView.swift:169`
- **Problem:** statsPage defaults to 259 with a comment '= statsPageCount - 1', while statsPageCount is defined separately as 260 lower in the file (166). The initial-state literal is a hand-maintained duplicate of (statsPageCount - 1); if statsPageCount ever changes, the 259 initializer silently desyncs and the view opens on the wrong week. The two are coupled only by a comment.
- **Recommendation:** Initialize statsPage from the constant (e.g. in init or via a computed default referencing statsPageCount - 1) so the relationship is enforced by code, not a comment. No behavior change at the current values.
- **Risk if applied:** Very low. A property initializer can't reference another stored property directly in Swift, so this needs an init or a lazy default; mechanical and safe.


---

## Test suite (HumanProgramTests — 8 files)

> The 8 test files are well-organized, readable, and give solid coverage of the core pure services (RecurrenceEngine, DailyPageGenerator, CompletionService, BacklogMaintenanceService, StreakCalculator) and the two most important invariants (past-page snapshot protection and .hprgm round-trip). The dominant problem is duplicated fixture/setup scaffolding: the same `gregorianUTC`/`localCalendar` calendar, `makeDate`, `makeRecurring`, and `makeTestModelContainer` helpers are copy-pasted across 4–6 files, and two files even re-declare a `makeTestModelContainer` that ALREADY exists as a public helper in app source (ModelContainerSetup.swift) and can silently drift from the production schema. Beyond duplication there are a handful of redundant/weak assertions, one mislabeled test, and small coverage gaps right next to the critical invariants (sever no-op path, calendar-sourced tasks, future-page protection, v1 round-trip is only an empty bundle). All findings are test-only and safe; none touches production behavior.

### 🔴 HIGH — Two test files re-declare makeTestModelContainer that already exists as a shared public helper

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgramTests/CoreServicesTests.swift:29-49`
  - `HumanProgramTests/GameBridgeTests.swift:34-54`
  - `HumanProgram/Core/Persistence/ModelContainerSetup.swift:26-45`
- **Problem:** App source already exposes a public `makeTestModelContainer()` (ModelContainerSetup.swift:26) listing all 14 @Model types, and PastPageSnapshotTests / HprgmBackupRoundTripTests / PastPageDecoupling all consume a shared container helper. But CoreServicesTests.swift:30 and GameBridgeTests.swift:35 each hand-roll their OWN identical copy of the 14-model Schema + ModelConfiguration. These are full copy-paste duplicates of the public helper. If a new @Model is added to the app (e.g. a future model), the production helper gets updated but these two private copies silently drift — tests using them would build a container missing the new model and could pass while masking a real registration bug, or fail confusingly.
- **Recommendation:** Delete the private `makeTestModelContainer()` in CoreServicesTests.swift and GameBridgeTests.swift and let both call the public `makeTestModelContainer()` from ModelContainerSetup.swift (same signature/behavior, already @testable-imported). PastPageDecouplingTests.swift:10-17 and ExerciseRepositoryTests.swift:11-18 also hand-roll their own (smaller) schemas — they could reuse the shared one too, but those are deliberately trimmed so leave them if intentional; the two full duplicates are the clear win.
- **Risk if applied:** Very low. The public helper has the identical model list and isStoredInMemoryOnly:true config; swapping is behavior-preserving for the tests. Only risk is the public helper uses `configurations: [config]` (array) vs the local `configurations: config` form — both are valid ModelContainer initializers, so no behavior change.

### 🟠 MEDIUM — Decoupling test only covers the backlog-sever path; .manual no-op and .calendar source untested

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgramTests/PastPageDecouplingTests.swift:26-48`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:251-256`
- **Problem:** severPastTasks (DailyPageRepository.swift:252) iterates `task.sourceType != .manual || task.sourceId != nil` — i.e. it deliberately SKIPS tasks that are already .manual with nil sourceId (the no-op guard) and applies to calendar-sourced tasks too. The single test only inserts ONE past task with sourceType=.backlog. It never verifies (a) that an already-.manual past task is left untouched (no spurious save/mutation — the `changed` flag exists precisely for this), nor (b) that a .calendar-sourced past task is also severed. CLAUDE.md calls rollover-decoupling one of the three deliberate snapshot-protection exceptions, so the calendar branch and the idempotent no-op are exactly the edges worth pinning.
- **Recommendation:** Add cases to PastPageDecouplingTests: a past task already (.manual, nil) stays exactly (.manual, nil); a past task with sourceType=.calendar is severed to (.manual, nil); and optionally that re-running severPastTasks twice is idempotent. Test-only additions, no source change.
- **Risk if applied:** None to production (test additions only). Low risk of a flaky test if local TZ midnight handling differs, but the existing test already uses Calendar.current/startOfDay so the new cases follow the same proven pattern.

### 🟠 MEDIUM — v1-backup round-trip only decodes an EMPTY bundle, not a populated legacy backup

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgramTests/HprgmBackupRoundTripTests.swift:178-204`
- **Problem:** testV1BundleDecodesWithoutNewSections feeds a v1 JSON whose arrays are ALL empty (backlogItems:[], dailyPages:[], etc.). It proves the new optional sections decode as nil, but it does NOT prove that a v1 backup containing actual rows (a backlog item, a daily page, a schedule block) still imports correctly under the current importData. CLAUDE.md requires 'New bundle fields must be optional so older backups still decode' and pins fidelity here — but the only populated round-trip is the v2 path. A regression in decoding legacy populated rows would slip through.
- **Recommendation:** Extend the v1 JSON in this test (or add a sibling) with at least one populated backlogItem and one dailyPage with a task, then assert importData restores them. Test-only; exercises the legacy-decode path that the empty bundle cannot.
- **Risk if applied:** None to production. Authoring a correct v1 JSON fixture is the only effort; getting field names wrong would just make the test fail loudly, not mask a bug.

### 🟠 MEDIUM — gregorianUTC / localCalendar + makeDate fixtures copy-pasted across 6 files

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgramTests/DailyPageGeneratorTests.swift:9-24`
  - `HumanProgramTests/CoreServicesTests.swift:10-25`
  - `HumanProgramTests/RecurrenceEngineTests.swift:10-28`
  - `HumanProgramTests/PastPageSnapshotTests.swift:15-30`
  - `HumanProgramTests/GameBridgeTests.swift:11-26`
- **Problem:** The identical `gregorianUTC` calendar (gregorian + UTC) appears in DailyPageGeneratorTests, CoreServicesTests, RecurrenceEngineTests; the identical `localCalendar` (gregorian + TimeZone.current) appears in PastPageSnapshotTests and GameBridgeTests; and a byte-for-byte `makeDate(year:month:day:)` (set y/m/d, hour/minute/second=0, force-unwrap) appears in ALL of them. PastPageDecouplingTests instead uses Calendar.current with startOfDay. This is the single most-duplicated block in the suite — five near-identical helper preambles that must be edited in five places if the fixture convention changes.
- **Recommendation:** Extract a small shared test-support file (e.g. `TestCalendars.swift` / a `XCTestCase` extension or a `TestSupport` enum) exposing `gregorianUTC`, `localCalendar`, and `makeDate(year:month:day:)`, and have each file use it. Keep the UTC-vs-local distinction explicit (some tests deliberately need local TZ to match DailyPage's Calendar.current normalization — see PastPageSnapshotTests.swift:13-14 comment).
- **Risk if applied:** Low. Pure mechanical extraction of test-only helpers with identical bodies. Must preserve the UTC-vs-local split exactly (local-calendar tests rely on TimeZone.current to round-trip stored dates), so the shared helper should offer both calendars rather than collapsing them into one.

### 🟢 LOW — Multiple `try!`-equivalent force-unwraps in fetched-page assertions

- **Category:** best-practice | **Effort:** small
- **Locations:**
  - `HumanProgramTests/PastPageSnapshotTests.swift:102`
  - `HumanProgramTests/PastPageSnapshotTests.swift:221`
  - `HumanProgramTests/PastPageSnapshotTests.swift:228`
  - `HumanProgramTests/PastPageSnapshotTests.swift:259`
  - `HumanProgramTests/PastPageSnapshotTests.swift:275`
  - `HumanProgramTests/PastPageSnapshotTests.swift:325`
- **Problem:** Fetched optional pages are force-unwrapped with `!` (e.g. `try repo.fetch(...)!` and `fetchedYesterday!.tasks` at line 102). When a fetch unexpectedly returns nil, force-unwrap crashes the whole test process with an opaque EXC_BAD_INSTRUCTION instead of failing that one test with a readable message. The file already demonstrates the better idiom at line 308 with `try XCTUnwrap(...)`. This is inconsistent within the same file.
- **Recommendation:** Replace `...fetch(...)!` with `try XCTUnwrap(repo.fetch(...))` and the `fetchedYesterday!` access with the unwrapped local. XCTUnwrap fails the single test with a clear message and stops, rather than aborting the suite.
- **Risk if applied:** Very low and test-only. XCTUnwrap is behavior-equivalent on the success path; only the failure ergonomics improve. Note line 328 (`refreshedTask!.completed`) follows an XCTAssertNotNil and is conventional, so it's the lowest priority of the group.

### 🟢 LOW — Round-trip test mutates real UserDefaults.standard rather than an isolated suite

- **Category:** best-practice | **Effort:** medium
- **Locations:**
  - `HprgmBackupRoundTripTests.swift:19-29`
  - `HprgmBackupRoundTripTests.swift:92-114`
  - `HprgmBackupRoundTripTests.swift:168-171`
- **Problem:** The test writes to and reads from UserDefaults.standard (the process-wide store), then relies on setUp/tearDown to save and restore the 9 known keys. This is fragile: if the test crashes between setUp and tearDown (e.g. a force-unwrap elsewhere), the developer's/simulator's real defaults are left mutated; and it couples correctness to keeping settingKeys (lines 12-16) in sync with whatever keys the export service actually touches — a hidden duplication of the export's key list.
- **Recommendation:** If HprgmExportService/ImportService accept an injectable UserDefaults (or can be pointed at `UserDefaults(suiteName:)`), use an isolated suite that is fully wiped in tearDown, eliminating both the save/restore dance and the cross-test pollution risk. If injection isn't available, this is informational only — do not change production signatures just for the test without owner approval.
- **Risk if applied:** Low if the services already support an injectable defaults store; otherwise applying this would require a production signature change (out of scope for a read-only/test-only fix), so treat as advisory.

### 🟢 LOW — Snapshot-protection suite never asserts a FUTURE locked page is protected, nor that refresh skips isPastLocked specifically

- **Category:** bug-risk | **Effort:** medium
- **Locations:**
  - `HumanProgramTests/PastPageSnapshotTests.swift:54-105`
  - `HumanProgramTests/PastPageSnapshotTests.swift:172-231`
- **Problem:** All five snapshot tests exercise yesterday vs today. The #1 invariant per CLAUDE.md is 'pages with isPastLocked must never be modified by automatic refresh'. The tests verify the OUTCOME for past dates but never directly assert the gating field: e.g. there is no test that takes a page, sets isPastLocked=true on a date that refresh WOULD otherwise touch, and confirms it's skipped — the protection is currently inferred only via date ordering. There's also no coverage that refreshTodayAndFuture updates a FUTURE page (a date &gt; today) the way it updates today, which is the 'and Future' half of the method name.
- **Recommendation:** Add one test that refreshTodayAndFuture DOES update a future page (assert a new template task appears on tomorrow's page), and one that an explicitly isPastLocked-true page on a non-past date (edge) is left untouched by refresh. These pin the isPastLocked gate directly rather than via date arithmetic. Test-only.
- **Risk if applied:** None to production. New tests may reveal an actual gap if refresh keys off date rather than isPastLocked — but that is the point of the coverage; they assert documented behavior only.

### 🟢 LOW — Round-trip test omits calendar-sourced DailyPageTask, despite calendar tasks being part of the completion rule

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgramTests/HprgmBackupRoundTripTests.swift:67-70`
  - `HumanProgramTests/HprgmBackupRoundTripTests.swift:152-153`
- **Problem:** The single DailyPageTask backed up is sourceType:.manual (line 67). CLAUDE.md states 'Calendar-sourced tasks ARE included' in completion, and CalendarEventLocalState is separately exercised — but a DailyPageTask carrying sourceType=.calendar (with a sourceId) is never round-tripped, so the export/import of that source tag + id on a task is unverified. If the encoder dropped or defaulted sourceType for calendar tasks, this test wouldn't catch it.
- **Recommendation:** Add a second DailyPageTask on the past page with sourceType=.calendar and a sourceId, and assert both the type and id survive import. Test-only addition to the existing round-trip.
- **Risk if applied:** None to production. Pure assertion expansion.

### 🟢 LOW — syncUncompletion has only the happy-path test; non-matching-date and already-backlog paths untested

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HumanProgramTests/CoreServicesTests.swift:254-278`
- **Problem:** syncCompletion has BOTH a matching-date test (line 204) and a non-matching-date returns-nil test (line 230). Its mirror, syncUncompletion, has only the matching-date restore test (line 256). There is no symmetric test that syncUncompletion returns nil when the item's assignedDate does NOT match pageDate, leaving one branch of the pair asymmetrically covered.
- **Recommendation:** Add `test_syncUncompletion_nonMatchingDate_returnsNil` mirroring test_syncCompletion_nonMatchingDate_returnsNil (lines 230-252), asserting the item's status is left unchanged. Test-only.
- **Risk if applied:** None to production. Mirrors an existing proven test pattern.

### 🟢 LOW — Weak existence-only assertions on schedule fetch could pass on an empty result

- **Category:** bug-risk | **Effort:** small
- **Locations:**
  - `HprgmBackupRoundTripTests.swift:144-147`
- **Problem:** After fetching ScheduleTemplate the test asserts `schedules.first?.blocks.first?.title == "Sleep"` etc. (lines 145-147) without first asserting `schedules.count == 1`. If the import restored ZERO schedule templates, `schedules.first` is nil, `nil?.blocks.first?.title` is nil, and `XCTAssertEqual(nil, "Sleep")` would fail — so this particular case is caught — but the pattern of skipping the count check (done correctly for backlogItems at line 131, projectBuckets at line 136, pages at line 150) is applied inconsistently. A future edit that asserted an optional against nil-equivalent could silently pass.
- **Recommendation:** Add `XCTAssertEqual(schedules.count, 1)` before the block assertions, matching the count-then-content pattern used elsewhere in the same test. Cosmetic robustness, test-only.
- **Risk if applied:** None. Adding a count assertion cannot weaken the test.

### 🟢 LOW — Redundant CompletionService test duplicates an earlier assertion

- **Category:** dead-code | **Effort:** small
- **Locations:**
  - `HumanProgramTests/CoreServicesTests.swift:116-133`
- **Problem:** `test_emptyTasks_isNotComplete` (line 118) and `test_emptyListAlwaysFalse_regardlessOfCompletionIntent` (line 127) assert the exact same thing — `service.isComplete(tasks: [])` is false — with the same call and same expectation. The second test's own comment (lines 124-125, 128-129) admits it is 'the same guard'. It adds no new coverage; it is effectively a duplicate test kept for narrative purposes.
- **Recommendation:** Either delete `test_emptyListAlwaysFalse_regardlessOfCompletionIntent`, or repurpose it to actually exercise a distinct case (e.g. a list whose tasks are all completed=true but… there is no such distinct empty case, which is exactly why it's redundant — so deletion is the honest fix).
- **Risk if applied:** Very low. Removing a strictly-duplicate test does not reduce real coverage; the empty-list case remains covered by test_emptyTasks_isNotComplete.

### 🟢 LOW — makeRecurring convenience builder duplicated verbatim in two files

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgramTests/DailyPageGeneratorTests.swift:36-41`
  - `HumanProgramTests/PastPageSnapshotTests.swift:38-45`
- **Problem:** `makeRecurring(id:title:rule:active:)` returning a `RecurringTaskInput(id:title:notes:"",rule:active:)` is written identically in both DailyPageGeneratorTests and PastPageSnapshotTests. Same default-argument shape, same empty-notes literal. A change to RecurringTaskInput's shape forces edits in both.
- **Recommendation:** Move `makeRecurring` (and the analogous `makeBacklog` at DailyPageGeneratorTests.swift:44-49, though it currently lives in only one file) into the shared test-support extension alongside the calendar/date helpers.
- **Risk if applied:** Very low. Identical bodies; centralizing changes nothing about behavior.

### 🟢 LOW — Test comment claims everyOtherDay equals everyNDays(2) but the test never asserts the equivalence

- **Category:** readability | **Effort:** small
- **Locations:**
  - `HumanProgramTests/RecurrenceEngineTests.swift:160-169`
- **Problem:** The MARK header (line 160) asserts 'everyOtherDay matches alternating days (same as everyNDays(2))', and test_everyOtherDay_matchesAlternate duplicates the exact offset checks of test_everyNDays_interval2_matchesAlternate (lines 99-110) by hand. The equivalence is asserted only in prose; the two tests are near-identical copies with the only difference being the rule constructor. If the engine's everyOtherDay and everyNDays(2) ever diverge, both tests still pass independently and the documented equivalence is unverified.
- **Recommendation:** Either parametrize both rules through one shared offset-table assertion, or add an explicit test that, for a range of offsets, `engine.matches(everyOtherDay,...) == engine.matches(everyNDays(2),...)`. Test-only; pins the documented relationship.
- **Risk if applied:** None to production. Low risk the new equivalence test reveals an actual divergence — which would be a real finding, not a false positive.

### 🟢 LOW — Two different tests both labeled 'MARK: - 12'

- **Category:** sloppy | **Effort:** small
- **Locations:**
  - `HumanProgramTests/RecurrenceEngineTests.swift:199-216`
  - `HumanProgramTests/RecurrenceEngineTests.swift:218-239`
- **Problem:** The section marker comment '// MARK: - 12. startAndEndDate are inclusive' (line 199) is immediately followed by '// MARK: - 12. occurrenceLimit: returns false after limit is reached' (line 218). Two consecutive sections share the number 12, and the numbering never recovers (next is 13 at line 271). Copy-paste numbering drift makes the file's section index misleading.
- **Recommendation:** Renumber the occurrenceLimit section (and everything after) so the MARK numbers are unique and sequential. Cosmetic only — no code change.
- **Risk if applied:** None. Comment-only edit.


---

## Cross-file duplication (whole repo: HumanProgram/ + HumanProgramTests/)

> The repo has a solid set of shared primitives (Color(hex:), clockString, popupGlass/topBarFrost, SettingsScreen/AddNavButton, BacklogRow, GlassKeypad view, ConfirmPopup, SettingsBackground, A11yTapBorder), so the worst duplication is already avoided. But several cross-cutting patterns were copy-pasted instead of extracted, and they will drift: (1) three template-input fetch helpers duplicated verbatim across AppStartup, PageRefreshService and TodayViewModel; (2) the entire numeric-keypad wiring duplicated between the Schedule and Reminder editors; (3) a keyboardWillShow/Hide spacer observer repeated identically in five views; (4) the CSV cell-escaping + POSIX date-formatter logic duplicated across the two CSV exporters; (5) UserDefaults key strings ("settings.*", "hp.*", "selectedCalendarIds") scattered as raw literals across ~10 files with no central constants; (6) full weekday-name and weekday-letter tables redeclared in 4-5 places; (7) inline DateFormatter instances rebuilt per render in many view bodies (also an efficiency issue) with the user's settings.dateFormat never actually consumed for display; (8) two month-grid generators and two permission/empty-state layouts that should be one component each; and (9) inline haptic generator calls repeated at 8 sites. None of these are behavioral bugs, but each means a single fix has to be made in many places. Recommendations below are all behavior-preserving extractions.

### 🔴 HIGH — Template-input fetch helpers (recurring/backlog/schedule) duplicated in three files

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/App/AppStartup.swift:62`
  - `HumanProgram/App/AppStartup.swift:70`
  - `HumanProgram/App/AppStartup.swift:78`
  - `HumanProgram/App/PageRefreshService.swift:32`
  - `HumanProgram/App/PageRefreshService.swift:47`
  - `HumanProgram/App/PageRefreshService.swift:62`
  - `HumanProgram/Features/Today/TodayViewModel.swift:210`
  - `HumanProgram/Features/Today/TodayViewModel.swift:215`
  - `HumanProgram/Features/Today/TodayViewModel.swift:220`
- **Problem:** fetchRecurringInputs(), fetchBacklogInputs() and fetchScheduleInputs() — each mapping a fetched @Model to its plain Input struct (RecurringTaskInput / BacklogTaskInput / ScheduleBlockInput) — are written out three times, essentially identically. The ScheduleBlockInput flatMap in particular (10 fields copied per block) is repeated verbatim. If a field is added to any Input struct (e.g. a new schedule-block property), three copies must be updated in lockstep or the generated pages silently diverge between launch, post-edit refresh, and the Today view's own refresh.
- **Recommendation:** Add a single @MainActor helper (e.g. TemplateInputs.fetchAll(context:) returning a small struct of the three arrays, or three free functions in one file) and call it from AppStartup, PageRefreshService and TodayViewModel. The mapping closures are already identical, so this is a pure move with no behavior change.
- **Risk if applied:** Low. Pure extraction of identical code; the three call sites already pass the same inputs into the same DailyPageRepository methods. Verify TodayViewModel still compiles against the shared (likely non-private) symbol.

### 🔴 HIGH — Numeric keypad wiring duplicated between Schedule and Reminder editors

- **Category:** exact-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:444`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:449`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:453`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:458`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:466`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:469`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:328`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:333`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:337`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:342`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:350`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:353`
- **Problem:** showKeypad(), keypadDigit(_:), keypadBackspace(), applyTypedToActive() (the HHMM parse + snap-to-5 rule), keypadDone() and dismissKeypadAndPopup() are byte-for-byte identical in both editors (only activeMinutesBinding's case mapping legitimately differs). CLAUDE.md explicitly states the GlassKeypad and editor interactions are the SHARED path (EditorRowInteractions.swift), but only the GlassKeypad *view* is shared — the surrounding state machine is copy-pasted. A change to the snap rule (e.g. snap-to-1) or the dismiss animation would have to be made in both, and they will drift.
- **Recommendation:** Move the typedDigits state machine into a small reusable type (e.g. a KeypadController ObservableObject, or a generic struct in EditorRowInteractions.swift) that takes the active Binding&lt;Int&gt; and exposes onDigit/onBackspace/onDone/visible. Each editor supplies only its activeMinutesBinding mapping. This matches the documented intent that EditorRowInteractions owns the keypad behavior.
- **Risk if applied:** Medium. The keypad interacts with activePicker/keypadVisible animation state and the AnchoredPopup; an extraction must preserve the exact spring timings and the tap-out dismiss ordering. Recommend extracting cautiously and diffing the two editors before/after. Safe to apply but needs careful manual verification of both editors.

### 🟠 MEDIUM — keyboardWillShow/Hide spacer observer repeated identically in five views

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:75`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:544`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:202`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:136`
  - `HumanProgram/Features/Routines/RoutineEditorView.swift:136`
- **Problem:** The same pair of onReceive handlers — keyboardWillShowNotification reading keyboardFrameEndUserInfoKey to set `keyboardSpacer = f.height` with withAnimation(.easeOut(duration: 0.25)), and keyboardWillHideNotification setting it to 0 with .easeOut(duration: 0.2) — is duplicated verbatim across five views. (PlanningComponents.swift:200 has a third, slightly different variant using keyboardWillChangeFrameNotification and overlap math, so there are actually two competing implementations of 'measure the keyboard height'.) Any tweak to the animation timing or to using the safe-area-relative overlap must be applied in 5+ places.
- **Recommendation:** Extract a single ViewModifier, e.g. `.keyboardSpacer($keyboardSpacer)` (or `.onKeyboardHeight { }`), living next to KeyboardDismiss.swift or in PlanningComponents.swift, and apply it everywhere. Reconcile the PlanningComponents overlap variant into the same modifier if the math is meant to match.
- **Risk if applied:** Low-to-medium. The five copies are identical so factoring them is safe; the PlanningComponents variant computes overlap relative to the screen, so confirm whether those screens want raw f.height or the overlap before merging that one. If unsure, share only the 5 identical copies and leave PlanningComponents alone.

### 🟠 MEDIUM — CSV cell escaping + POSIX date/ISO formatter duplicated across both CSV exporters

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/ImportExport/BacklogCSVExporter.swift:58`
  - `HumanProgram/Core/ImportExport/BacklogCSVExporter.swift:16`
  - `HumanProgram/Core/ImportExport/BacklogCSVExporter.swift:20`
  - `HumanProgram/Core/ImportExport/BacklogCSVExporter.swift:46`
  - `HumanProgram/Core/ImportExport/TaskHistoryCSVExporter.swift:69`
  - `HumanProgram/Core/ImportExport/TaskHistoryCSVExporter.swift:16`
  - `HumanProgram/Core/ImportExport/TaskHistoryCSVExporter.swift:20`
  - `HumanProgram/Core/ImportExport/TaskHistoryCSVExporter.swift:57`
- **Problem:** csvCell(_:) — the formula-injection guard (prefix =,+,-,@ with apostrophe), double-quote doubling, and wrapping — is byte-for-byte identical in both exporters. The same en_US_POSIX 'yyyy-MM-dd' DateFormatter and the same ISO8601DateFormatter([.withInternetDateTime]) setup are also rebuilt in both. A fix to the injection rule (e.g. adding tab/CR handling) would have to be made twice and could silently diverge, weakening one export's CSV-injection defense.
- **Recommendation:** Extract csvCell and the two formatter factories into one shared CSV helper (e.g. enum CSV { static func cell(_:) ; static let posixDate ; static let iso }) used by both exporters. Pure logic, no SwiftData — fits the 'pure struct service' rule.
- **Risk if applied:** Low. Identical bodies; behavior preserved. Worth a quick round-trip check that the existing CSV export tests (if any) still pass.

### 🟠 MEDIUM — UserDefaults key strings scattered as raw literals across the app (no central constants)

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/DesignSystem/AppFont.swift:136`
  - `HumanProgram/Core/DesignSystem/AppFont.swift:146`
  - `HumanProgram/Core/DesignSystem/AppFont.swift:162`
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:275`
  - `HumanProgram/Core/ImportExport/HprgmImportService.swift:245`
  - `HumanProgram/App/HumanProgramApp.swift:8`
  - `HumanProgram/App/ContentView.swift:14`
  - `HumanProgram/Features/Settings/FactoryResetView.swift:207`
  - `HumanProgram/Features/Settings/Customization/CustomizationView.swift:24`
  - `HumanProgram/Features/Settings/Format/FormatView.swift:22`
  - `HumanProgram/Features/Settings/Components/SettingsComponents.swift:25`
  - `HumanProgram/Core/Security/AppLockRepository.swift:16`
- **Problem:** The preference keys 'settings.fontChoice', 'settings.fontSizeStep', 'settings.appearanceMode', 'settings.appIcon', 'settings.bgLight', 'settings.bgDark', 'settings.dateFormat', 'settings.timeFormat', 'selectedCalendarIds', 'hp.onboarded', 'hp.permissionsAsked', and the 'hp.lock.*' keys are typed as raw string literals in ~10 files. There is no shared constants enum. This is the highest-risk class of literal duplication for this app: HprgmExportService/HprgmImportService and FactoryResetView each re-list these keys by hand, so a typo or a forgotten key means a preference silently fails to back up, restore, or reset (CLAUDE.md flags exactly this: 'if you add a new user-preference key, you MUST add it to the bundle + export + import' — but that is enforced only by remembering the literal). The 'settings.bgLight/bgDark' default values also diverge slightly (CustomizationView and SettingsComponents both default to 0, but FormatView's defaults for date/time are duplicated in AppFont's fallbacks too).
- **Recommendation:** Introduce one enum DefaultsKey (or static let constants) in a Core file and reference it everywhere (@AppStorage(DefaultsKey.fontChoice), UserDefaults.standard.set(_, forKey: DefaultsKey.timeFormat), and the export/import/reset key lists). This also lets the reset/export/import lists be derived from a single source array. Behavior-preserving as long as the literal values are kept exactly.
- **Risk if applied:** Medium. The values must match the existing strings exactly (any mismatch would orphan a user's stored preference). @AppStorage requires compile-time-constant keys, so the constants must be `static let` String — verify each @AppStorage call site accepts the constant. Mechanical but touches many files.

### 🟠 MEDIUM — selectedCalendarIds key + read-helper duplicated in Today and Calendar

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:43`
  - `HumanProgram/Features/Calendar/CalendarView.swift:54`
  - `HumanProgram/Features/Calendar/CalendarSourceSettingsView.swift:17`
  - `HumanProgram/Core/ImportExport/HprgmExportService.swift:283`
  - `HumanProgram/Core/ImportExport/HprgmImportService.swift:253`
  - `HumanProgram/Features/Settings/FactoryResetView.swift:211`
- **Problem:** The computed property `private var selectedCalendarIds: [String] { UserDefaults.standard.stringArray(forKey: "selectedCalendarIds") ?? [] }` is duplicated identically in TodayView and CalendarView, and the literal "selectedCalendarIds" appears in six files (the two views, the source-settings screen which at least names it `selectedIdsKey`, export, import, and reset). The two view copies will drift if, say, a migration changes the default.
- **Recommendation:** Expose one shared accessor (e.g. CalendarSelection.selectedIds in the calendar adapter layer, reading the key once) and have both views use it; route the export/import/reset literals through the same DefaultsKey constant from the previous finding.
- **Risk if applied:** Low. Same value everywhere; consolidating the read path changes nothing observable.

### 🟠 MEDIUM — Full weekday-name table redeclared in four places

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/ExerciseRepository.swift:24`
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:333`
  - `HumanProgram/Features/Settings/Exercise/ExerciseSettingsView.swift:12`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:49`
- **Problem:** The 1=Sunday … 7=Saturday name mapping exists as: a [Int:String] dictionary in ExerciseRepository (now unused-but-kept), a switch in ScheduleRepository.weekdayName(for:), and an identical `static let fullWeekdayName: [Int:String]` in BOTH ExerciseSettingsView and ExerciseRoutineEditorView (byte-for-byte the same). Four sources of truth for the same encoding; the fallback strings differ ('Day N' vs 'Exercise' vs none), so they are not consistent.
- **Recommendation:** Add one canonical mapping next to RecurrenceRule (which already documents the 1=Sun…7=Sat encoding), e.g. `Weekday.fullName(_:)` and `Weekday.letters`, and reference it from all four sites. Keep each call site's own fallback if it intentionally differs.
- **Risk if applied:** Low. Centralizing the lookup is safe; just preserve the differing fallback strings where they matter (conflict messages vs routine titles).

### 🟠 MEDIUM — Inline DateFormatter rebuilt per render in view bodies; settings.dateFormat never read for display

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:229`
  - `HumanProgram/Features/Backlog/BacklogView.swift:107`
  - `HumanProgram/Features/Backlog/BacklogView.swift:370`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:162`
  - `HumanProgram/Features/Stats/StatsView.swift:160`
  - `HumanProgram/Features/Stats/StatsView.swift:233`
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:68`
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:94`
  - `HumanProgram/Features/Settings/ImportExportView.swift:233`
  - `HumanProgram/Features/Settings/Schedule/ScheduleListView.swift:87`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTasksView.swift:71`
- **Problem:** Roughly a dozen sites build a fresh DateFormatter() inline inside a computed property/closure that runs on render, almost always with the same patterns ('MMM d, yyyy', 'MMM d', 'MMMM yyyy'). Two of them (ScheduleListView.summary and RecurringTasksView.summary) produce the IDENTICAL custom-date-range string '\(MMM d) – \(MMM d)'. DateFormatter allocation is comparatively expensive and is happening every time these bodies recompute. Separately, the user-selectable 'settings.dateFormat' (FormatView.swift:22) is written and round-tripped in backups but is NOT read by any of these display sites — they all hardcode 'MMM d, yyyy' — so the Format setting has no visible effect, which is both a duplication and a feature-consistency gap.
- **Recommendation:** Add a shared, cached date-string helper (mirroring the existing clockString) — e.g. `func dateString(_ date: Date, style: ...)` backed by static cached DateFormatter instances — and use it at every display site, factoring the duplicated range summary into one helper too. Decide deliberately whether that helper should honor settings.dateFormat (FormatView's own header comment says formatting is 'not yet applied app-wide', so wiring it in is a real behavior change and should be owner-approved).
- **Risk if applied:** Medium. Caching the formatter and sharing the helper is safe and behavior-preserving IF the same format strings are kept. Making the helper read settings.dateFormat WOULD change displayed output app-wide — do that only with owner sign-off, and note 'EEEE, MMM d, yyyy' / 'MMM d' / 'MMMM yyyy' / 'EEE' variants would each need a style so they aren't flattened to one format.

### 🟠 MEDIUM — Back-chevron + trailing icon top-bar buttons re-rolled in every feature view

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:171`
  - `HumanProgram/Features/Today/TodayView.swift:199`
  - `HumanProgram/Features/Backlog/BacklogView.swift:168`
  - `HumanProgram/Features/Backlog/BacklogView.swift:203`
  - `HumanProgram/Features/Backlog/BacklogView.swift:403`
  - `HumanProgram/Features/Calendar/CalendarView.swift:103`
  - `HumanProgram/Features/Stats/StatsView.swift:47`
  - `HumanProgram/Features/Routines/RoutinesView.swift:50`
- **Problem:** Every hub section view builds its own topBar with the same leading element — Image(systemName: "chevron.left").font(.system(size:18,weight:.semibold)).foregroundStyle(.primary).frame(width:44,height:44).contentShape(Rectangle()).a11yTapBorder(Rectangle()).onTapGesture { dismiss() } — and its own near-identical trailing icon button (plus/calendar, 44x44, contentShape, a11yTapBorder). TodayView.navButton and BacklogView.iconButton are two local helper variants of the same thing. Settings already has the shared AddNavButton; the feature views don't reuse it (it's NavigationLink-based and only used in Settings). The 44x44 + contentShape + a11yTapBorder requirement is exactly the CLAUDE.md toolbar-button rule, repeated by hand five+ times — easy to forget contentShape on a new screen.
- **Recommendation:** Extract a shared BackNavButton (the chevron + dismiss) and a generic ToolbarIconButton(systemName:action:) into SettingsComponents.swift (or a Shared components file) and reuse across Today/Backlog/Calendar/Stats/Routines, alongside the existing AddNavButton. Keeps the tap-target/contentShape rule in one place.
- **Risk if applied:** Low-to-medium. The leading button has per-screen tap behavior (Today calls dismissAddIfOpen + relockOnLeave before dismiss), so the shared component must accept a custom action rather than hardcoding dismiss(). Spacing/padding differs slightly between screens (spacing 6 vs 8), so verify each topBar still lays out identically after extraction.

### 🟢 LOW — Repeated 'today' computation Calendar.current.startOfDay(for: Date()) across the app

- **Category:** conciseness | **Effort:** small
- **Locations:**
  - `HumanProgram/App/AppState.swift:8`
  - `HumanProgram/App/PageRefreshService.swift:14`
  - `HumanProgram/Features/Today/TodayViewModel.swift:29`
  - `HumanProgram/Features/Calendar/CalendarView.swift:123`
  - `HumanProgram/Features/Settings/AboutView.swift:61`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:41`
- **Problem:** Calendar.current.startOfDay(for: Date()) ('today, normalized to midnight') is written 30+ times across the codebase (the grep returned matches in AppState, repositories, and most feature views). It is correct everywhere, but the verbosity invites a subtle error if one site forgets startOfDay (using raw Date() would break date-keyed lookups and the isPastLocked comparison).
- **Recommendation:** Add one tiny helper, e.g. `extension Date { static var todayStart: Date { Calendar.current.startOfDay(for: Date()) } }` or `Calendar.current.today`, and use it. Reduces noise and removes the 'forgot startOfDay' failure mode. Purely cosmetic — apply broadly or not at all.
- **Risk if applied:** Low. Behavior-identical wrapper. Only value is consistency; safe to skip if churn is a concern.

### 🟢 LOW — weekdays(from rule:) helper duplicated verbatim in two recurring-task files

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTasksView.swift:79`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:248`
- **Problem:** The static helper weekdays(from rule:) -&gt; Set&lt;Int&gt; mapping frequency (.everyDay/.weekdays/.weekends/default) to the 1..7 set is byte-for-byte identical in the list view and the editor. If the frequency-to-weekdays mapping ever changes (e.g. a new frequency case), both must be updated together.
- **Recommendation:** Move this onto RecurrenceRule itself (e.g. a computed `effectiveWeekdays: Set&lt;Int&gt;`) next to the existing 1=Sun encoding, and call it from both view files. The logic is pure and belongs with the rule.
- **Risk if applied:** Low. Identical bodies; pure relocation. Confirm RecurrenceRule's RecurrenceFrequency cases match the switch exactly.

### 🟢 LOW — resignFirstResponder keyboard-dismiss call (with identical comment) duplicated

- **Category:** exact-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/ImportExportView.swift:357`
  - `HumanProgram/Features/Settings/FactoryResetView.swift:157`
- **Problem:** The same UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) call — preceded by the same 'Drop the keyboard before the confirmation interstitial appears' comment — appears in both the restore flow and the reset flow. KeyboardDismiss.swift exists but provides a different (tap-anywhere window recognizer) mechanism, so this programmatic dismiss is unshared.
- **Recommendation:** Add a one-line helper (e.g. UIApplication.shared.endEditing() extension, or a static KeyboardDismisser.resignActive()) next to KeyboardDismiss.swift and call it from both sites.
- **Risk if applied:** Low. Trivial single-call extraction; no behavior change.

### 🟢 LOW — Weekday-letter array ["S","M","T","W","T","F","S"] duplicated across calendar/date components

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:17`
  - `HumanProgram/Features/Calendar/CalendarView.swift:278`
  - `HumanProgram/Features/Calendar/CalendarView.swift:404`
  - `HumanProgram/Features/Settings/Components/PlanningComponents.swift:16`
  - `HumanProgram/Features/Settings/Components/PlanningComponents.swift:51`
- **Problem:** The seven single-letter weekday headers are hardcoded as a literal array in DSDatePicker, twice in CalendarView (month header and week header), and as the (day,letter) tuple list twice in PlanningComponents (WeekdayCircleSelector and WeekdayStrip). Five copies of the same Sun-first letters.
- **Recommendation:** Pull into the same canonical Weekday helper as the names (Weekday.letters: [String]) and reuse. Note all five are Sunday-first, consistent with the 1=Sun encoding, so this is purely cosmetic deduplication.
- **Risk if applied:** Low. Cosmetic constant; no behavior change.

### 🟢 LOW — minute-of-day extraction and 24h gutter formatting duplicated across timeline views

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/DailyTimeline.swift:147`
  - `HumanProgram/Features/Today/DailyTimeline.swift:152`
  - `HumanProgram/Features/Calendar/CalendarView.swift:535`
  - `HumanProgram/Features/Calendar/CalendarView.swift:879`
  - `HumanProgram/Features/Calendar/CalendarView.swift:890`
  - `HumanProgram/Features/Today/TodayView.swift:153`
- **Problem:** Converting a Date to minutes-of-day via Calendar.dateComponents([.hour,.minute]) then (hour*60+minute) is reimplemented in DailyTimeline.currentMinute, CalendarView.minuteOfDay (line 879), CalendarView.dayTimeline's nowMinute (535) and nowTimeString (890). The fixed-24h gutter string String(format: "%02d:%02d", m/60, m%60) appears in DailyTimeline.hhmm and CalendarView.nowTimeString. TodayView.minutesOfDay(_:dayStart:) computes the same concept from a time interval. These are intentionally NOT clockString (gutters are fixed 24h per CLAUDE.md), so they can't reuse that — but they could share one tiny 24h helper.
- **Recommendation:** Add a small fixed-24h helper pair (e.g. Date.minuteOfDay and func gutter24h(_ minutes: Int) -&gt; String) in the design system and reuse in DailyTimeline and CalendarView. Keep it explicitly separate from clockString so the 24h-gutter invariant stays obvious.
- **Risk if applied:** Low. The bodies are identical; centralizing is safe. Be careful NOT to route these through clockString (that would break the fixed-24h gutter rule).

### 🟢 LOW — Inline UIImpactFeedbackGenerator haptic calls repeated at eight sites

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayView.swift:399`
  - `HumanProgram/Features/Today/TodayView.swift:559`
  - `HumanProgram/Features/Today/TodayView.swift:561`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:586`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:328`
  - `HumanProgram/Features/HiddenGate/SudokuGateView.swift:97`
  - `HumanProgram/Features/Routines/RoutineEditorView.swift:240`
  - `HumanProgram/Features/Settings/AboutView.swift:67`
- **Problem:** `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` (and the .light / UINotificationFeedbackGenerator().notificationOccurred(.success) variants) are instantiated inline at eight sites in six files. Allocating a fresh generator each time and not calling prepare() is the common pattern; there is no shared Haptics helper, so the feedback styles can drift and there is no single place to tune or disable haptics (e.g. for an accessibility/reduce-feedback setting).
- **Recommendation:** Add a tiny enum Haptics { static func impact(_:); static func success() } and replace the inline calls. Trivial and behavior-preserving.
- **Risk if applied:** Low. Direct mechanical replacement; keep the same styles so the tactile feel is unchanged.

### 🟢 LOW — Two month-grid generators (CalendarView vs DSCalendarView)

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:864`
  - `HumanProgram/Features/Settings/Components/DSDatePicker.swift:74`
- **Problem:** CalendarView.daysInMonthGrid(for:) and DSCalendarView.gridDays both build a 7-column month grid: compute leading blanks from (firstWeekday - 1) with 1=Sun, then pad to a whole number of weeks. CalendarView returns adjacent-month Dates for fillers; DSDatePicker returns nil for fillers — same algorithm, two implementations. A change to the week-start convention (e.g. Monday-first) would need both edited.
- **Recommendation:** Extract one month-grid builder (returning [Date?] or a typed cell) into a shared calendar helper and have both consumers map it to their own cell view. Keep the 1=Sun leading-blank logic identical to preserve current layout.
- **Risk if applied:** Medium. The two grids feed different cell renderers and one expects adjacent-month dates while the other expects nils; the shared builder must support both or each consumer adapts. Layout is pixel-sensitive, so verify the grids render identically after refactor.

### 🟢 LOW — Calendar permission/empty-state layout duplicated instead of reusing CalendarMessageState

- **Category:** near-duplication | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:154`
  - `HumanProgram/Features/Calendar/CalendarView.swift:184`
  - `HumanProgram/Features/Calendar/CalendarSourceSettingsView.swift:179`
- **Problem:** CalendarSourceSettingsView already has a reusable `CalendarMessageState` (DSKit-based: DSImageView 48 + DSText title/subheadline + capsule action) whose own doc comment says it is 'Reused for the calendar permission-request, denied, and empty states.' But CalendarView builds its OWN permissionRequestView and permissionDeniedView as near-identical VStacks using LEGACY Text/appFont/.font(.system(size:48)) and a bordered button — duplicating the layout and, per CLAUDE.md, also violating the DSKit-only rule for new/migrated UI. The two CalendarView copies differ only in icon text/button action.
- **Recommendation:** Make CalendarMessageState non-private (or move it to a shared file) and have CalendarView's permissionRequestView/permissionDeniedView use it, deleting the hand-rolled VStacks. This removes the duplication and the legacy-styling inconsistency in one move.
- **Risk if applied:** Low. The shared component already exists and is proven; only the icon/title/message/action differ. Visual result will shift slightly to the DSKit styling — acceptable per the migration direction, but confirm with the owner since it changes the look of those two states.

### 🟢 LOW — Discard-changes guard (attemptBack/hasUnsavedChanges/showDiscardConfirm) re-wired per editor

- **Category:** near-duplication | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:156`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:215`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:57`
  - `HumanProgram/Features/Settings/RecurringTasks/RecurringTaskEditorView.swift:93`
  - `HumanProgram/Features/Settings/Reminders/ReminderEditorView.swift:98`
- **Problem:** Each editor independently declares @State showDiscardConfirm, an identical attemptBack() { if hasUnsavedChanges { showDiscardConfirm = true } else { dismiss() } }, the same SettingsScreen(onBack: attemptBack, swipeBackBlocked: { hasUnsavedChanges }) wiring, and the same inline ConfirmPopup('Discard Changes?', confirmTitle: 'Discard'). The ConfirmPopup component is shared, but the surrounding boilerplate (state + attemptBack + the popup invocation) is copy-pasted across three editors; only hasUnsavedChanges legitimately differs per editor.
- **Recommendation:** Factor the discard boilerplate into a small reusable piece — e.g. a `.discardGuard(hasChanges:onDismiss:)` modifier or a shared EditorScaffold that owns showDiscardConfirm/attemptBack and renders the ConfirmPopup — so each editor supplies only its hasUnsavedChanges predicate.
- **Risk if applied:** Medium. attemptBack ties into SettingsScreen's swipe-back recognizer and the editor's dismiss; an extraction must keep the swipeBackBlocked closure and back-button both routing through the guard. Behavior-preserving if done carefully, but verify swipe-back still triggers the dialog in each editor.


---

## Cross-cutting CLAUDE.md convention consistency (whole repo)

> The repo follows most CLAUDE.md conventions uniformly: weekday encoding is consistently 1=Sun..7=Sat (RecurrenceRule, DailyPageGenerator, ScheduleRepository, WeekdayCircleSelector/WeekdayStrip); no Core/Services file imports SwiftData (services stay pure); every Settings-area screen is built from SettingsScreen/SettingsGroup/SettingsRowContent (only CatCorner and the shared component files opt out, both intentionally); clockString(...) is used for displayed clock times in the Reminder/Schedule editors and lists, and the Today/Calendar gutters and now-bar pills correctly stay fixed 24h; width-only Color.clear spacers in headers all carry a fixed height; custom top-bar icon buttons consistently carry .contentShape(Rectangle()) on a 44x44 (or 30x30) frame; AppColors/AppTypography legacy tokens are no longer referenced by any view. The notable PIECEMEAL gaps are: (1) the #1 architecture rule "Views never write to ModelContext directly" is violated in several feature views that call context.save()/insert()/delete() inline; (2) hardcoded colors and a copy-pasted lightBlue constant + primary-button pattern across the four interstitial/legal/onboarding screens; (3) a few real Text(...) nodes rendered in the system font instead of appFont/DSText; (4) one editor (Calendar event sheet) mixes appScaledSize(...) and raw fixed font sizes for its text fields, unlike the other editors.

### 🔴 HIGH — Views write to ModelContext directly, violating the #1 architecture rule

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Backlog/BacklogView.swift:318`
  - `HumanProgram/Features/Backlog/BacklogView.swift:444`
  - `HumanProgram/Features/Backlog/BacklogTaskDetailView.swift:190`
  - `HumanProgram/Features/Settings/FactoryResetView.swift:163`
  - `HumanProgram/Features/Settings/FactoryResetView.swift:202`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:892`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:909`
- **Problem:** CLAUDE.md rule #1 states 'Views never write to ModelContext directly. Views call a ViewModel or Repository, which calls ModelContext. No exceptions.' Yet several feature views mutate the store inline: BacklogView.moveSelected reassigns item.project and calls context.save() (line 318), BacklogView.confirmMove calls context.save() (line 444), BacklogTaskDetailView.save() calls context.save() (line 190), FactoryResetView calls context.save() (line 163) and context.delete(item) (line 202), and ScheduleEditorView calls context.insert(t) (line 892) and context.delete(t)/context.save() (line 909). Most other writes in the app correctly route through repositories (BacklogRepository, ScheduleRepository, etc.), so this is applied in some places and skipped in others — exactly the kind of drift the rule guards against. The risk is that snapshot-protection and conflict logic living in repositories can be bypassed by these direct writes.
- **Recommendation:** Move each inline context.save/insert/delete into the matching repository method (BacklogRepository for the project-move and task-detail save, ScheduleRepository for the insert/delete/rollback, a reset routine on a repository/service for FactoryReset) and have the view call that. Do not change behavior — wrap the exact same operations. This is a read-only report; no edits were made.
- **Risk if applied:** Medium if actually refactored: moving the save/insert/delete into repositories must preserve ordering (e.g. ScheduleEditor inserts before save then deletes on conflict; FactoryReset deletes then saves). Mechanical extraction with identical call order is low-risk, but careless reordering could change persistence semantics. As a report only, zero risk.

### 🟠 MEDIUM — Copy-pasted lightBlue color constant and primary-button pattern across 4 screens (hardcoded color)

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/App/AppInterstitialView.swift:13`
  - `HumanProgram/App/AppInterstitialView.swift:48`
  - `HumanProgram/App/PermissionsOnboardingView.swift:18`
  - `HumanProgram/App/PermissionsOnboardingView.swift:66`
  - `HumanProgram/App/PermissionsOnboardingView.swift:92`
  - `HumanProgram/Features/Settings/Legal/TermsOfServiceView.swift:21`
  - `HumanProgram/Features/Settings/Legal/TermsOfServiceView.swift:77`
  - `HumanProgram/Features/Settings/Tutorial/TutorialView.swift:13`
  - `HumanProgram/Features/Settings/Tutorial/TutorialView.swift:49`
- **Problem:** The exact constant `private let lightBlue = Color(red: 0.42, green: 0.69, blue: 0.99)` is duplicated verbatim in four files, and the full-width primary button (`.background(lightBlue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))` + matching contentShape + a11yTapBorder) is near-duplicated across all of them. This violates two CLAUDE.md rules at once: 'No hardcoded Color(hex:)/Color(red:) in views — new/migrated UI must use DSKit, not hardcoded colors,' and 'Reuse UI, never duplicate it... a button style must come from ONE shared component/token.' The blue is also reused for icon tints (TodayView calendarBlue-style greens elsewhere are separate), so the same magic RGB lives in several places and will drift if the brand color is ever tweaked.
- **Recommendation:** Promote the blue to one shared token (a DSKit appearance color or a single AppColors/DesignSystem constant) and extract the full-width primary button into one reusable view/ButtonStyle that all four screens call. Keep the rendered result identical. No edits made here.
- **Risk if applied:** Low: factoring the literal into one constant and one button view is visually behavior-preserving as long as the RGB, corner radius (note PermissionsOnboarding line 92 uses cornerRadius 12, not 14 — keep that difference), enabled/disabled opacity (0.35), and tap shapes are reproduced exactly. Report only, so no risk now.

### 🟢 LOW — Real text rendered in system font instead of appFont/DSText (DSKit typography drift)

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Stats/StatsView.swift:101`
  - `HumanProgram/Features/Routines/RoutinesView.swift:74`
  - `HumanProgram/Features/Routines/RoutineEditorView.swift:73`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:333`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:347`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:480`
  - `HumanProgram/Features/Settings/Components/EditorRowInteractions.swift:482`
- **Problem:** CLAUDE.md says no hardcoded `.font(.system(size:))` in views; plain Text that can't use DSText should use the `appFont(...)` helper so it honors the user's chosen font. Most of the app does this. The exceptions render real content text in the system font: StatsView:101 shows the stat number `Text("\(value)").font(.system(size: 34, weight: .bold))` right beside DSText labels (lines 99/103), so the number visibly mismatches the app font; the GlassKeypad digits in EditorRowInteractions (lines 333/347 colon, 480 number, 482 letters) and the keypad are shared but still bypass appFont. (RoutinesView:74 / RoutineEditorView:73 are emoji, which render the same regardless of font, so those are cosmetic-only.) Note: the many other `.font(.system(size:))` hits are on Image(systemName:) glyphs (icon sizing), which is the app-wide top-bar pattern and not a text-typography issue.
- **Recommendation:** Swap the genuine Text nodes (StatsView:101, EditorRowInteractions keypad digits/colon/letters) to `Text(...).font(appFont(&lt;size&gt;, bold: ...))` so they follow the selected app font, matching the surrounding DSText. Leave emoji and SF-Symbol Image glyph sizing as-is. No edits made.
- **Risk if applied:** Low: appFont returns a Font at the same point size, so layout barely shifts; only the typeface changes to match the rest of the app. Verify the monospacedDigit() intent on StatsView:101 is preserved (appFont won't carry it) so the big number stays tabular if that matters.

### 🟢 LOW — Calendar event editor mixes appScaledSize(...) and raw fixed font sizes for its text fields

- **Category:** claude-md-inconsistency | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:1173`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1174`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1213`
  - `HumanProgram/Features/Calendar/CalendarView.swift:1215`
- **Problem:** Every other editor passes the AppTextField fontSize through `appScaledSize(...)` so the field tracks the global font-size setting (ReminderEditorView:108/156 use appScaledSize(20)/(18); RecurringTaskEditorView:65/80; ScheduleEditorView:168; ExerciseRoutineEditorView:69; this same Calendar editor uses appScaledSize(20) for the title on line 1173). But the Location (line 1174), Note (1213), and URL (1215) fields use a bare `fontSize: 17` that does NOT apply the global scale. Result: in this one editor the title scales with the user's font-size setting while location/note/url stay fixed — inconsistent with the rest of the app and with the title field one line above. CLAUDE.md's read/edit text-size rule and the appScaledSize convention both point at scaling these consistently.
- **Recommendation:** Change the three bare `fontSize: 17` to `fontSize: appScaledSize(17)` so they scale like every other editor's secondary fields. No edits made here.
- **Risk if applied:** Low: at the default font-size step appScaledSize(17) == 17, so default rendering is unchanged; only non-default font-size steps change, bringing this editor in line with the others. The event sheet is always-editable (no separate read mode), so there is no reflow-between-modes concern.

### 🟢 LOW — Top-bar/header icons use Image(systemName:).font(.system(size:)) instead of DSImageView (partial DSKit migration)

- **Category:** claude-md-inconsistency | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Components/SettingsComponents.swift:95`
  - `HumanProgram/Features/Settings/Components/SettingsComponents.swift:260`
  - `HumanProgram/Features/Today/TodayView.swift:174`
  - `HumanProgram/Features/Today/TodayView.swift:201`
  - `HumanProgram/Features/Calendar/CalendarView.swift:105`
  - `HumanProgram/Features/Calendar/CalendarView.swift:113`
  - `HumanProgram/Features/Routines/RoutinesView.swift:52`
  - `HumanProgram/Features/Stats/StatsView.swift:49`
  - `HumanProgram/Features/Backlog/BacklogView.swift:405`
- **Problem:** The settings ROWS use the DSKit icon path `DSImageView(systemName:size:.font(.title3),tint:.color(.primary))` (per the documented Settings convention), but every custom top-bar/header icon (back chevron, +, nav arrows) is a raw `Image(systemName:).font(.system(size:18/20))`. CLAUDE.md lists `.font(.system(size:))` among the hardcoded patterns to avoid in views. This is applied consistently across all top bars (so it's a coherent pattern, not random drift) but it is the legacy non-DSKit path coexisting with DSImageView elsewhere — i.e. the DSKit migration is only partial for icons. Flagging because the section asked for conventions followed in some places and not others.
- **Recommendation:** If/when fully migrating, route top-bar glyphs through DSImageView (or a single shared IconButton) so icon sizing/tinting comes from DSKit tokens rather than fixed point sizes. Because these are SF Symbol glyph sizes (not text), this is cosmetic and behavior-neutral; low priority. No edits made.
- **Risk if applied:** Low-to-medium if changed: DSImageView's sizing model differs from Image.font(.system(size:)), so glyph sizes and the careful 44x44/30x30 hit frames could shift and would need re-checking against the pixel-tuned layouts. Safer to leave unless a deliberate icon-migration pass is done. Report only.


---

## Algorithmic complexity & performance (whole repo)

> Overall the core services are well-structured and most loops are bounded by small collections (tasks per day, blocks per template, 7 weekdays, 42 month cells). The pure services (DailyPageGenerator, CompletionService, BacklogMaintenanceService) already use Set/Dictionary lookups where it matters, and StreakCalculator builds a proper date→bool dictionary. The real, concrete performance wins are concentrated in a few SwiftUI views that recompute expensive work on every body evaluation: StatsView re-sorts allPages and rebuilds a date→page dictionary plus several DateFormatters on every render; CalendarView re-filters/re-sorts the full events array per day-column and per month cell; and the app-wide appFont/appUIFont helpers rebuild a UIFont (and read UserDefaults) on every call, of which there are dozens per timeline render. There is also one latent super-linear path in RecurrenceEngine.countOccurrences (O(days since 1970) when occurrenceLimit is set without a startDate/anchorDate) that is currently unreachable because no editor ever sets occurrenceLimit, but it is a landmine. None of these are correctness bugs; all the suggested fixes are behavior-preserving caching/precomputation.

### 🟠 MEDIUM — StatsView recomputes pageByDate dictionary and re-sorts allPages on every body render and inside every streak pass

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Stats/StatsView.swift:21`
  - `HumanProgram/Features/Stats/StatsView.swift:113`
  - `HumanProgram/Features/Stats/StatsView.swift:114`
  - `HumanProgram/Features/Stats/StatsView.swift:130`
  - `HumanProgram/Features/Stats/StatsView.swift:134`
  - `HumanProgram/Features/Stats/StatsView.swift:149`
- **Problem:** `pageByDate` is a computed property that rebuilds a whole [Date: DailyPage] dictionary (O(n)) every time it is read, and it is read for both completionRuns and exerciseRuns, plus once per weekDays(offset:) bar lookup. `runs(qualifies:)` independently re-maps and re-sorts `allPages` (`allPages.map{startOfDay}.sorted()`) on every call — even though `allPages` already comes from `@Query(sort: \.date, order: .forward)` and is therefore already date-ordered, so the sort is redundant. completionRuns and exerciseRuns are each evaluated during body, and the week chart (TabView with statsPageCount=260 pages) plus the two streakRows all re-trigger these on each render. With N pages this is several redundant O(N log N) sorts and O(N) dictionary builds per render.
- **Recommendation:** Compute `pageByDate` and the sorted start-of-day date list once (e.g. cache them in derived stored state recomputed only when allPages changes, or hoist into a single computed `let` at the top of body and pass down). Drop the `.sorted()` in `runs(qualifies:)` since allPages is already ascending by date — iterate it directly mapping to startOfDay. Reuse the single pageByDate for both completion and exercise runs instead of reading the computed property multiple times.
- **Risk if applied:** Low. Behavior is identical as long as the cached dictionary/date list is kept in sync with allPages (e.g. keyed off allPages identity/count) and the date list stays ascending. Dropping the redundant sort is safe because @Query already sorts by date ascending.

### 🟠 MEDIUM — StatsView builds DateFormatters on the hot path (per bar, per render)

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Stats/StatsView.swift:160`
  - `HumanProgram/Features/Stats/StatsView.swift:216`
  - `HumanProgram/Features/Stats/StatsView.swift:233`
- **Problem:** `WeekBar.shortDay` creates a fresh `DateFormatter` for every bar (7 per week chart, and the TabView materializes multiple week pages), `weekLabel` creates one per render, and `streakDateString` creates one per streak row. DateFormatter construction is notoriously expensive (locale/calendar setup) and here it happens inside view rendering rather than once.
- **Recommendation:** Hoist these DateFormatters to static cached instances (e.g. a `private static let dayFormatter = DateFormatter()` configured once with the en-equivalent format), or precompute the short-day / label strings when building the WeekBar array. Same for the file-level `streakDateString`/`streakRangeString` formatter.
- **Risk if applied:** Low. Identical output as long as the cached formatter keeps the same dateFormat/locale. Formatters are not mutated after creation so a shared static instance is safe on the main actor (these are all main-thread view code).

### 🟠 MEDIUM — CalendarView month grid does a full linear scan of events for every visible day cell

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:295`
  - `HumanProgram/Features/Calendar/CalendarView.swift:298`
- **Problem:** monthGrid renders ~42 cells and each in-month cell evaluates `events.contains { cal.isDate($0.startDate, inSameDayAs: day) }`. That is O(cells * events) = O(42 * E) calendar comparisons per grid render, and isDate(inSameDayAs:) is itself relatively costly. The month TabView holds multiple month pages, multiplying the work.
- **Recommendation:** Precompute a `Set&lt;Date&gt;` of start-of-day dates that have events once per loadEvents()/events change (e.g. `Set(events.map { cal.startOfDay(for: $0.startDate) })`), then each cell does an O(1) `eventDays.contains(cal.startOfDay(for: day))`. This turns O(42*E) into O(E) once + O(42) lookups.
- **Risk if applied:** Low. Same visual result. Only nuance: build the set with the same Calendar instance used for the cell comparison so day-boundary semantics match exactly.

### 🟠 MEDIUM — CalendarView Week/Day views re-filter and re-sort the entire events array per day column

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Calendar/CalendarView.swift:722`
  - `HumanProgram/Features/Calendar/CalendarView.swift:731`
  - `HumanProgram/Features/Calendar/CalendarView.swift:737`
  - `HumanProgram/Features/Calendar/CalendarView.swift:455`
  - `HumanProgram/Features/Calendar/CalendarView.swift:758`
  - `HumanProgram/Features/Calendar/CalendarView.swift:762`
- **Problem:** `eventsForDay`, `timedEventsForDay`, and `allDayEventsForDay` each do a fresh `events.filter{...}.sorted{...}` over the WHOLE events array. In the week timeline these are called once per day column (7x) for timed events (line 455), and `weekAllDayBand` calls `allDayEventsForDay` for the contains check (line 758) and then AGAIN inside the ForEach for each column (line 762) — so the all-day filter runs ~2x7 times per render, each an O(E) pass plus a sort. timedEventsForDay also calls eventsForDay (full filter+sort) then filters again, an extra redundant pass.
- **Recommendation:** Group events once per render into a `[Date: [EKEvent]]` (keyed by start-of-day) with each bucket pre-sorted, computed at the top of the week/day builder (or cached when `events` changes). Day columns then index the dictionary in O(1). Also avoid calling allDayEventsForDay twice in weekAllDayBand — compute each day's all-day list once and reuse it for both the `contains` guard and the ForEach.
- **Risk if applied:** Low–medium. Pure refactor of how the same filtered/sorted lists are obtained; output ordering must stay identical (timed by startDate, all-day by title). Care needed because all-day events use an overlap test (startDate &lt; dayEnd &amp;&amp; endDate &gt; dayStart), not start-of-day equality, so a simple start-day bucket won't capture multi-day all-day events — those still need an overlap pass or a separate precomputed per-day expansion.

### 🟠 MEDIUM — appFont/appUIFont rebuild a UIFont and read UserDefaults on every call; called dozens of times per timeline render

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/DesignSystem/AppFont.swift:135`
  - `HumanProgram/Core/DesignSystem/AppFont.swift:151`
  - `HumanProgram/Features/Calendar/CalendarView.swift:449`
  - `HumanProgram/Features/Calendar/CalendarView.swift:464`
  - `HumanProgram/Features/Today/DailyTimeline.swift:84`
  - `HumanProgram/Features/Today/DailyTimeline.swift:96`
- **Problem:** `appFont`/`appUIFont` each read UserDefaults, parse the FontChoice, build a `UIFontDescriptor` from attributes, and construct a `UIFont` on every invocation. These are called inside tight ForEach grids: CalendarView's week timeline builds a font per hour line (24x) and per event label, the Today DailyTimeline builds fonts per grid label and per placed item label, and they recompute on every body render. UIFont/descriptor creation is not free; doing it O(rows*events) times per frame is wasteful churn even though each call is individually cheap.
- **Recommendation:** Memoize the resolved font: cache the (fontChoice, size, bold) → Font/UIFont mapping in a small dictionary keyed by those parameters, invalidated when settings.fontChoice changes. At minimum, read the font choice once per view body and pass the resolved FontChoice down rather than re-reading UserDefaults per glyph. This preserves the 'updates when the font changes' behavior while eliminating per-call descriptor construction.
- **Risk if applied:** Medium. Must keep the live-update behavior (font changes mid-session must still take effect) — a cache keyed by the current fontChoice raw string handles that. Risk is a stale cache if the invalidation key is wrong; keeping the UserDefaults read but caching only the UIFont construction per (raw,size,bold) is the safe minimal version.

### 🟢 LOW — RecurrenceEngine.countOccurrences is O(days since origin) and falls back to a 1970 origin (latent ~20k-iteration loop)

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:18`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:85`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:97`
  - `HumanProgram/Core/Services/RecurrenceEngine.swift:111`
- **Problem:** When a rule has `occurrenceLimit`, `matches` calls `countOccurrences`, which iterates day-by-day from the origin to the target date calling `rule.occurs(on:)` each step (each step does startOfDay + dateComponents + a date add). If `startDate` and `anchorDate` are both nil the origin is `Date(timeIntervalSince1970: 0)` (1970), so for today's date the loop runs ~20,000+ iterations per single match check — and `generate()` calls matches() for every recurring template, every time a page is generated/refreshed. This is currently unreachable in production because no editor ever sets `occurrenceLimit` (confirmed by grep: it is only declared in the model/engine), but it is a landmine for any future feature that enables occurrence limits.
- **Recommendation:** Either (a) document/guard that occurrenceLimit requires a startDate/anchorDate (clamp the counting origin to a sane recent bound), or (b) replace the day-walk with closed-form counting for the frequencies that allow it (everyDay/everyNDays/everyOtherDay/fourDaySplit are arithmetic on day-difference; weekday-based ones can count weeks * matches-per-week + remainder). Since the path is currently dead, the cheapest safe fix is bounding the origin fallback rather than rewriting; flag it so a future occurrenceLimit feature doesn't ship the unbounded loop.
- **Risk if applied:** Low to flag/bound; medium if closed-form counting is implemented (must exactly match the day-walk semantics including startDate/endDate bounds). Because the code path is unreachable today, any change here cannot regress current behavior, but a closed-form rewrite would need the existing RecurrenceEngine tests plus new ones to lock equivalence.

### 🟢 LOW — DailyPageRepository.refreshTodayAndFuture and severPastTasks fetch ALL pages then filter in-memory instead of using a date predicate

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:100`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:101`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:103`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:249`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:251`
- **Problem:** refreshTodayAndFuture fetches every DailyPage (`FetchDescriptor&lt;DailyPage&gt;()` with no predicate) and then per-page guards `isPastLocked` / `date &gt;= today`, so it materializes the entire history (which grows ~1 page/day forever) just to touch today+future. severPastTasks similarly fetches all pages then filters `page.date &lt; normalizedToday` in memory. As the app accumulates years of pages this fetch and its relationship faulting grow unbounded even though only a handful of pages are relevant.
- **Recommendation:** Add a `#Predicate` on the FetchDescriptor to push the date filter into the store: for refreshTodayAndFuture, `#Predicate { $0.date &gt;= normalizedToday &amp;&amp; !$0.isPastLocked }`; for severPastTasks, `#Predicate { $0.date &lt; normalizedToday }`. This bounds the fetch to the relevant window instead of the whole history.
- **Risk if applied:** Low. Same set of pages is processed (the in-memory guards already encode these conditions). Minor caveat: SwiftData #Predicate on a normalized Date local must capture a `let` value (already the pattern used in fetch(date:)). The existing per-page guards can stay as a belt-and-suspenders check.

### 🟢 LOW — TodayViewModel.projectName fetches all BacklogItems and linear-scans for one id

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Features/Today/TodayViewModel.swift:202`
  - `HumanProgram/Features/Today/TodayViewModel.swift:204`
  - `HumanProgram/Features/Today/TodayViewModel.swift:205`
- **Problem:** projectName(for:) does `context.fetch(FetchDescriptor&lt;BacklogItem&gt;())` (loads every backlog item) and then `.first(where: { $0.id == sid })` (linear scan). It is only called when constructing the task-detail navigation destination (TodayView.swift:86), so it is not a per-frame hot path, but it still loads the whole backlog table to resolve a single id and the result feeds a 'None' fallback.
- **Recommendation:** Fetch the single item with a predicate and fetchLimit 1: `FetchDescriptor&lt;BacklogItem&gt;(predicate: #Predicate { $0.id == sid })` with `fetchLimit = 1`, then read `.project?.name`. O(1)-ish lookup instead of O(all backlog items).
- **Risk if applied:** Low. Same resolved name (and same 'None' fallback when missing). Only behavioral nuance is none — it is a read-only lookup.

### 🟢 LOW — ScheduleRepository.addBlock sorts the blocks array just to read the last element

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/ScheduleRepository.swift:90`
- **Problem:** `let lastBlock = template.blocks.sorted { $0.sortOrder &lt; $1.sortOrder }.last!` allocates a full sorted copy of the blocks array only to take the element with the max sortOrder. Blocks-per-template is small (bounded), so this is minor, but it builds a throwaway sorted array (and uses force-unwrap) where a single max pass suffices.
- **Recommendation:** Replace with `template.blocks.max(by: { $0.sortOrder &lt; $1.sortOrder })` (O(n), no allocation). The force-unwrap can also be removed by guarding/defaulting, since the function already ensures blocks is non-empty just above.
- **Risk if applied:** Low. Identical result for the common case. The only divergence from `.sorted().last` would be tie-breaking among equal sortOrders (max returns the first max encountered vs sorted's last) — sortOrders are normalized to be unique elsewhere, so this is not observable, but worth noting.

### 🟢 LOW — DailyPageRepository.applyRefresh does a nested removeAll inside a filter loop (O(n^2) within one page)

- **Category:** efficiency-bigO | **Effort:** small
- **Locations:**
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:350`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:351`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:352`
  - `HumanProgram/Core/Repositories/DailyPageRepository.swift:353`
- **Problem:** After computing `tasksToDelete = page.tasks.filter { removeSet.contains($0.id) }`, the loop calls `page.tasks.removeAll { $0.id == task.id }` once per task to delete — each removeAll is an O(n) scan over page.tasks, so deleting k tasks is O(k*n). Same pattern appears in syncCalendarTasks (line 199) and severPastTasks isn't affected. Tasks-per-page is small, so impact is minor, but it is a quadratic shape on the page-open/refresh hot path.
- **Recommendation:** Delete in a single pass: `page.tasks.removeAll { removeSet.contains($0.id) }` and separately `context.delete(task)` for each task in tasksToDelete. That makes the array mutation O(n) total instead of O(k*n).
- **Risk if applied:** Low. Same final set of removed/deleted tasks. Must keep the `context.delete(task)` calls for every removed task (the single removeAll only updates the in-memory relationship array; the SwiftData delete still has to be issued per task).

### 🟢 LOW — ScheduleEditorView value bindings do first(where:)+firstIndex(where:) linear scans on every get/set

- **Category:** efficiency-bigO | **Effort:** medium
- **Locations:**
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:374`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:380`
  - `HumanProgram/Features/Settings/Schedule/ScheduleEditorView.swift:391`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:290`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:296`
  - `HumanProgram/Features/Settings/Exercise/ExerciseRoutineEditorView.swift:302`
- **Problem:** Per-row bindings resolve the row by `blocks.first(where: { $0.id == id })` on get and `blocks.firstIndex(where: { $0.id == id })` on set, each an O(n) scan. With one binding per visible field and several fields per row, editing redraws do O(rows * fields * rows) scans. Row counts are small (a handful of schedule blocks / exercise items), so this is bounded and low-impact, but it is the repeated-linear-scan pattern the audit targets.
- **Recommendation:** If these editors ever support larger lists, index the rows by id into a dictionary (id → array index) computed when the array changes, and have the bindings use the index directly. For the current small bounded lists this is optional; flagging for consistency since the same id-scan binding pattern is duplicated across the Schedule, Exercise, and Routine editors.
- **Risk if applied:** Low to leave as-is (bounded). If refactored, the index map must be invalidated on every insert/delete/reorder or a binding could write to the wrong row — so the cheaper/safer choice for these small lists is to leave them and only act if list sizes grow.

