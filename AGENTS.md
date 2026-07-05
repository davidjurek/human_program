# AGENTS.md — Human Program

This file is instructions for AI coding agents (Codex) working on this project. Read it before writing any code.

---

## Working rules — ALWAYS follow these (highest priority)

These govern *when* you act. They override any inclination to be helpful by getting ahead of the owner.

1. **Do not write or change code unless you receive an unmistakable, explicit command to do so.** Discussion, questions, screenshots, "do you see X?", or descriptions of a problem are NOT permission to edit. If it is at all unclear whether the owner wants you to make the change now, **do not** — ask or wait. When in doubt, don't.
2. **Compiling is ALWAYS allowed; RUNNING the simulator is NEVER allowed unless the owner explicitly asks in that moment.** These are two different things — keep them separate:
   - **Compiling/building IS allowed and encouraged at any time** to check your work. `xcodebuild build -destination 'generic/platform=iOS Simulator'` compiles the code and does **NOT** boot, install, launch, or open a simulator — it is just a syntax/type check. You may run it freely after edits to confirm a green build, without asking. This is the right way to verify your changes compile.
   - **Running/using the simulator is absolute-NEVER on your own initiative.** Do NOT boot, install, launch, run, screenshot, or otherwise interact with a running simulator — **not to "verify," not to "just check," not for any reason** — unless the owner explicitly and specifically says so in that moment. Past permission does not carry forward; each time needs a fresh "yes, use the simulator." When in doubt, compile (allowed) but do not run the sim (not allowed).
3. **If (and only if) told to use the simulator, use iPhone 17 Pro, iOS 26.4** — not 26.5.

---

## What this app is

Human Program is a personal daily planning iOS app. Each day gets one generated page. That page combines recurring tasks, backlog items, exercise routines, schedule blocks, and calendar events into one required checklist. Complete all tasks → the day is marked complete (the date turns green). Nothing syncs to the cloud. Everything stays on device.

> **The hidden game was removed (owner-approved).** The Sudoku gate, the game container, `GameAccessService`/`EasterEggGateService`, and the `GameAccessState`/`GameSaveMetadata` models are all gone. `dayComplete` is now purely a planner state — completing a day no longer unlocks anything. The unrelated **Cat Corner** photo gallery and the hidden UDHR document (double-tap the version in About) remain.

---

## How to build

**Requirements:**
- Xcode 15+
- XcodeGen installed: `brew install xcodegen`

**Steps:**
1. Generate the Xcode project: `make setup` (or run `xcodegen generate` in the project root)
2. Open `HumanProgram.xcodeproj` in Xcode

**Run tests:**
```
make test
```

**Tech stack:** iOS 17+, Swift 5.9, SwiftUI, SwiftData

---

## Project structure

```
HumanProgram/
  App/              — app entry point, AppState, AppStartup, ContentView
  Core/
    Models/         — SwiftData @Model classes and plain Codable structs
    Services/       — pure logic (no SwiftData); the brain of the app
    Repositories/   — @MainActor classes that own ModelContext access
    (GameBridge/ removed — the hidden game was deleted)
    Persistence/    — ModelContainer factory functions
    DesignSystem/   — AppColors, AppTypography tokens
  Features/
    Today/          — primary screen, TodayViewModel, components
    Backlog/        — backlog list (stub, needs full build)
    Settings/       — settings menu + About page (Cat Corner, hidden UDHR doc)
    Stats/          — streak and completion stats
    Routines/       — simple routine lists
HumanProgramWidget/ — WidgetKit extension (Today widgets). `WidgetShared.swift` is
                      compiled into BOTH this target and the app; everything else here
                      is widget-only. Reads a snapshot from the App Group, never SwiftData.
HumanProgramTests/  — XCTest unit tests for all core services
project.yml         — XcodeGen config (source of truth for project structure)
Makefile            — build and test shortcuts
ADD.md              — full product spec (read this before changing behavior)
```

**Important:** `project.yml` is the source of truth for what files are in the project. If you add a new file, add it to `project.yml` and re-run `xcodegen generate` (or `make setup`). Never edit the `.xcodeproj` file directly.

---

## Architecture rules — ALWAYS follow these

1. **Views never write to ModelContext directly.** Views call a ViewModel or Repository, which calls ModelContext. No exceptions.
2. **Services are pure structs with no SwiftData imports.** `RecurrenceEngine`, `DailyPageGenerator`, `CompletionService`, etc. take plain data in and return plain data out. This makes them fast and easy to test without spinning up a database.
3. **Repositories are `@MainActor` classes.** SwiftData's `ModelContext` must only be used on the main thread. Repositories own all ModelContext access.
4. **Past daily pages must never be modified *automatically*.** If `isPastLocked == true`, that page is a historical snapshot. Template changes, refreshes, or bulk operations must skip past pages. This is the single most important rule in the codebase. **Three deliberate, owner-approved exceptions (do NOT "fix" these as bugs):** (a) the user can manually **unlock** a past day on the Today screen (red→green padlock, tap-and-hold) to add/edit its tasks; it auto-re-locks on leaving. (b) At day rollover, `DailyPageRepository.severPastTasks` clears the `sourceType`/`sourceId` of past page-tasks so they become standalone snapshots decoupled from the backlog/calendar — completion no longer affects the backlog/calendar, and reassigning a backlog item to a new date yields two independent tasks. (c) A **full `.hprgm` restore** (`HprgmImportService.importData`) deletes and replaces ALL daily pages, including locked snapshots, so the restore exactly mirrors the backup. This is an explicit, user-typed "REPLACES all current data" action — not an automatic refresh. Neither (a) nor (b) is a template refresh, and automatic refresh still never touches past pages.
5. *(Removed.)* There is no longer a game or a planner↔game bridge. `dayComplete` is a plain planner state.

---

## Key types — read before changing anything

### RecurrenceRule
- Location: `Core/Models/RecurrenceRule.swift`
- A `Codable` struct stored as a SwiftData attribute.
- **Weekday encoding: 1=Sunday, 2=Monday, 3=Tuesday, 4=Wednesday, 5=Thursday, 6=Friday, 7=Saturday.**
- This matches iOS `Calendar`'s `.weekday` component. Every single feature that touches weekdays uses this encoding. Do not change it, do not use 0-based indexing anywhere.

### DailyPage
- One page per date. Created on demand in `DailyPageRepository.getOrCreate()`.
- `isPastLocked = true`: historical snapshot. Never refresh, never modify.
- `isPastLocked = false`: today or a future date. Always refresh from current templates when opened.
- `dayComplete`: calculated by `CompletionService`. Never set this manually.

### Completion rule
```
date <= today (NOT a future day)  &&  tasks.allSatisfy { $0.completed }
```
A day is complete when it is **today or in the past** AND every task is checked off — and an **empty list counts as complete** ("nothing to do = done"), so an empty today/past page is complete. A **future day is NEVER complete**, even if it has tasks and they're all checked off: you can tick tasks ahead of time, but it isn't flagged done and doesn't feed streaks/stats until that day actually arrives (an empty future page that rolls into today flips to complete automatically on the next refresh). Exercise is not in the task list (unless the user separately created a recurring task for it). Calendar-sourced tasks ARE included. The "today vs future" gate lives in `CompletionService.isComplete(tasks:date:today:)`; `recalculate(page:today:)` is called by every mutator and by `getOrCreate`/refresh (which pass the page-generation `today`). *(Owner-approved 2026-06-06, reversing the old "empty = not complete, future days completable" rule.)*

### GameAccessService *(removed)*
The game and its access service were deleted. `dayComplete` no longer gates anything.

---

## Design rules — ALWAYS follow these

- **Reuse UI, never duplicate it.** When the same visual element appears in more than one place — a row, a section header, a banner, a button style, a card, a sheet layout, a spacing value — it must come from ONE shared component, modifier, or token. Do not copy-paste a chunk of view code and tweak it. Before building any UI, search the codebase for an existing component that already does it (or nearly does it) and extend that instead. If a change to one screen needs the same change on another, that is a sign the markup should have been shared — extract it into a reusable view rather than editing two copies. This is the single most important UI rule: many small UI edits are coming, and duplicated view code means each fix has to be made in several places and they will drift apart.
- **No stock `List {}` with default iOS styling** for the main task list or backlog list. Use `VStack` with custom row views.
- **Read mode is the default.** Edit controls are hidden until the user enters edit mode.
- **Read and edit modes must share identical layout — no reflow.** Hiding an edit-only control (delete button, reorder handle, inline field) must NOT move other content. Reserve the same spacing, row heights, columns, padding, alignment, **and text size** in both modes. A common trap: read mode uses a DSKit text style (e.g. `.dsTextStyle(.title3)`, which applies the global font scale) while edit mode uses a plain `AppTextField(fontSize: 20)` (which does NOT) — the title then jumps size between modes. Match the edit field's size to the read style with `appScaledSize(...)` (`.title3` → `appScaledSize(20)`, `.title2` → `appScaledSize(22)`). Build one shared layout and make edit-only controls invisible/disabled in read mode — don't build two separate layouts that "look close."
- **No filler/explanatory text, and keep needed copy short.** Don't add descriptive or instructional copy anywhere in the app unless it's a message the user genuinely needs (e.g. a destructive-action warning, a real error, a format requirement). If a screen works without the sentence, leave it out — empty states should be blank, not captioned. When copy IS needed, keep it short and concise (e.g. "No routines yet", not "No routines yet — tap + to add one"). Prefer no "—" placeholders for empty values either (just leave it blank), except where a value row reads better as "None".
- **Width-only frames on spacers/`Color.clear` are greedy in height.** A `Color.clear.frame(width: x)` (or any spacer with only a width) expands to fill all available vertical space, which silently stretches its parent row/HStack and pushes siblings apart. In header rows always give such spacers a fixed height (`.frame(width: x, height: 1)`). This caused the calendar week-header gap.
- **Never eyeball or guess UI positions.** When two screens or states must line up, the shared position must come from one shared layout path, wrapper, or component — not from hand-tuned spacers or trial-and-error offsets. Account for every offsetting element (titles, wrappers, hidden controls, padding, insets, different parent layouts). Never claim a position is precise when any part of it was estimated.
- **No confirmation dialogs for delete.** The plan is undo/redo (not yet built). Don't add "Are you sure?" dialogs as a workaround — just skip the confirmation for now.
- **Clock times honor the 12h/24h setting via the shared `clockString(...)` helper** (`AppFont.swift`, reads `settings.timeFormat`, default 12h → "8:00 PM" / 24h → "20:00"). Use it for every DISPLAYED `##:##` clock time (Schedule sleep/block ranges, Reminder time read-outs, Reminders-list summaries, `DSTimeField`); the picker wheels also follow it (12h shows an AM/PM column), while the keypad always types HHMM in 24h (unambiguous). **The Today timeline gutter + block labels + now-pill, AND the Calendar Week/Day gutters + now-pills, now ALSO honor the setting (owner-approved 2026-06-03, reversing the old "fixed 24h" rule).** The shared gutter width and the `NowPill` come from `Features/Today/TimelineShared.swift` (`TimelineMetrics`) so Today, Calendar week, and Calendar day share one left-margin width and one pill shape/size in both formats. Only route durations (`##h ##m`) and running totals as fixed 24h — those are NOT clock times.
- **UI is built on DSKit.** The whole app's UI is migrating to the DSKit design system (`import DSKit`). Use DSKit components (`DSText`, `DSImageView`, `DSButton`, etc.) and the appearance/theme set in `AppTheme.appearance`, applied once at the app root via `.dsAppearance(...)`. `AppColors` / `AppTypography` are LEGACY — they still exist for not-yet-migrated screens, but new or migrated UI must use DSKit, not them. No hardcoded `Color(hex:)` / `.font(.system(size:))` in views.
- **See the "DSKit" section below** for the Settings UI convention and the API gotchas (the tokens are tricky — read it before writing DSKit code).
- **No game.** The hidden game was removed; there is no game button, gate, or unlock anywhere. (A hidden UDHR document still opens by double-tapping the version row in About; the developer-name row no longer has any hidden action.)

---

## DSKit — UI framework

The app's UI runs on [DSKit](https://github.com/imodeveloper/dskit-swiftui) (MIT). Migration is phased, screen by screen, with a green build at each checkpoint. Add new files to the project then run `xcodegen generate` BEFORE building, or DSKit-using files won't be found.

### Settings UI convention (the standard for ALL settings screens)

Every Settings-area screen is composed from the shared components in `Features/Settings/Components/SettingsComponents.swift`. Do NOT hand-roll settings rows — reuse these so one change updates every screen:

- `SettingsScreen { ... }` — themed scroll container. Soft lavender→blue→peach **gradient** background (`SettingsBackground`, Settings screens only), **no nav title** (titles are hidden app-wide; back button stays). Top inset 28.
  - **Side margins depend on screen type, set by the `centered` flag:**
    - **Menu screens** (the default, `centered: false`) — **titles run to left 42 / right 8** (intentional right-shifted asymmetry), but **trailing accessories** (toggles, trailing values, etc.) are pulled in to the **right-20** margin. This split is automatic: `SettingsScreen` sets `\.settingsIsMenu` and `SettingsRowContent` insets its trailing accessory by 12pt on menu screens. So: menu **title** = 42-8, menu **everything else** = 42-20.
    - **Non-menu screens** (editors, list screens, etc. — pass `centered: true`) — **left 20, right 20** (symmetric).
  - **Swipe-back is re-enabled here.** Hiding the nav bar kills iOS's leading-edge swipe-back gesture, so `SettingsScreen` re-installs it (a recognizer that re-asserts on every (re)appear, so it doesn't go stale after visiting another screen). Editors pass `onBack`/`swipeBackBlocked`: when there are unsaved changes the swipe (and the back button) route through the **discard-changes guard** instead of popping. Toolbar icon buttons (back, `+`, trash, Save) get `.contentShape(Rectangle())` so the whole 44×44 is tappable.
  - A faint **gradient frost** sits behind the top bar so the back/Save buttons stay legible over scrolling content.
  - **Scroll indicator: Apple default, app-wide.** The vertical scroll indicator sits flush at the trailing edge (Apple's default position) — there is **no** custom inset. (An earlier `ScrollIndicatorInset` that pulled it ~7pt inboard was removed at the owner's request; don't re-add it.)
- `SettingsGroup(title:) { rows }` — a section. Optional uppercase label, then rows. Spacing: **18pt** label→first row, **38pt** between rows. Top-level groups are spaced **28pt** apart. Every section that should read as its own block needs a `title` (an untitled group collapses to the smaller 28pt gap and looks inconsistent — give it a header).
- `SettingsRowContent` / `SettingsNavRow` — **open, card-less rows**: icon + `.title3` label, **no chevron**, full-width tap target. `SettingsNavRow` pushes a destination.
- Row look: leading SF Symbol icon (`DSImageView(systemName:size:.font(.title3),tint:.color(.primary))`) + `DSText(label).dsTextStyle(.title3)`, optional trailing value.

### DSKit API gotchas (learned the hard way — read before writing DSKit code)

- **Color/typography tokens are ambiguously overloaded.** `.text(...)` exists on multiple DSKit enums, so the two-arg `dsTextStyle(_, .text(.secondary))` does NOT compile. Rules that work:
  - Default color: use single-arg `.dsTextStyle(.caption1)` (DSKit applies a sensible semantic color).
  - Explicit color: `.dsTextStyle(.headline, Color.white)` or DSImageView `tint: .color(.primary)`.
  - Tint from a typography token: `tint: .text(.subheadline)` (the arg is a `DSTypographyToken`, not a color name).
- **`.label` typography token is ambiguous bare** — use `.body` or `.headline` instead, or it won't type-check.
- DSKit has **no native Toggle / Segmented / Stepper** — use SwiftUI's native controls inside DSKit containers.
- `DSText(_:)` takes just a string (no `lineSpacing:` arg here).

### Planning editors (Schedule / Recurring / Reminder) — interaction patterns learned the hard way

The Schedule editor is the reference implementation. The hold-to-reorder + swipe-to-delete recognizers, the keyboard-scroll nudge, the `GlassKeypad`, and the `SteppedWheel`/`CountWheel`/`IntervalWheel` pickers now live in **`Features/Settings/Components/EditorRowInteractions.swift`** (generic over the row's `Hashable` id) and are SHARED — the Exercise editor reuses them. Build new editable-row editors on these, don't re-derive. Patterns that took many iterations to get right — reuse them, don't re-derive:

**All three planning editors (Schedule / Recurring / Reminder) now share ONE picker path: the `AnchoredPopup` (Repeat dropdown, time wheels, interval wheel) + the custom `GlassKeypad` for numeric entry.** The old inline-expanding controls — `AppDropdown`, `WheelHourMinute`, `TimeFieldRow`, `IntervalFieldRow` — and the last `.keyboardType(.numberPad)` (Apple's numpad) are GONE; don't reintroduce them. The Reminder editor's "Every N min/hr" uses the two-wheel `IntervalWheel` (amount + unit) in an `AnchoredPopup`, no keypad.

- **Toolbar icon buttons need `.contentShape(Rectangle())`** on their 44×44 frame, or only the opaque glyph is tappable and taps near it miss (hit the `+`, trash, etc.). Use the shared `AddNavButton`.
- **Popups all share `popupGlass()`** — one modifier (clear iOS-26 `glassEffect`, blur fallback) used by every popup (confirm dialogs, Repeat dropdown, wheel popups). Change the glass in that one place.
- **Anchored popups** (`AnchoredPopup`, drops under a tapped value) must capture the value's frame and position themselves in **one shared NAMED coordinate space**, never `.global`. The popup layer ignores the safe area, so its `.global` origin doesn't match the content's `.global` frames and the popup jumps to the corner.
- **Numeric entry uses a custom keypad (`GlassKeypad`), NOT the system numpad.** iOS 26 floats keyboard accessory bars, so a flush attached "Done" bar on the system keyboard is impossible. The custom keypad is bottom-pinned liquid glass, feeds HHMM (minutes snap to 5), and ✓/tap-outside close it + the wheel popup.
- **Uniform keyboard gap (text fields):** SwiftUI's automatic keyboard avoidance gives a non-uniform, field-TYPE-dependent gap (a `UITextView`-backed field gets a bigger gap than a plain `TextField`) and fights manual scrolling. The combo that works: (1) disable SwiftUI avoidance on the screen (`SettingsScreen(manualKeyboardAvoidance: true)` → `.ignoresSafeArea(.keyboard)`); (2) add a **bottom content spacer = keyboard height** for scroll room — do NOT use `contentInset` for the room, SwiftUI resets it and the scroll snaps back; (3) a small UIKit `keyboardDidShow` observer scrolls the focused field to a fixed gap (20pt) above the keyboard, only when it's actually covered. Keep title fields the **same SwiftUI `TextField` type** so the measured frames match.
- **Reorder and swipe-to-delete use UIKit recognizers**, not SwiftUI gestures. SwiftUI gesture composition can't cleanly separate tap / hold-to-drag / horizontal-swipe / vertical-scroll on one custom row. Reorder = a `UILongPressGestureRecognizer` (≈0.4s, small allowable movement) on the enclosing scroll view, hit-testing rows by their reported window frames; swipe = a `UIPanGestureRecognizer` that only *begins* for horizontal drags so vertical drags fall through to native scrolling. The swipe pan commits at ~4pt of horizontal motion (so a small slide can't be mistaken for a tap) and **ignores the leading ~24pt edge zone** so iOS swipe-back works on list screens.
- **The SAME engine drives all five list screens** — Today, Schedule, Exercise, Routines, and **Backlog** — via `RowGestureCoordinator` + `EditableRow`/`rowGestures`. Backlog passes `reorderEnabled: false` (it's a sorted list, no manual ordering) so only tap / swipe-to-delete / scroll are active there. Backlog rows navigate via `consumeTap()` + programmatic navigation (NOT an in-row `NavigationLink`) so a tap that began as a swipe or an edge-back never fires.
- **Editable rows have four distinct, non-overlapping gestures:** a quick **tap** edits (inline title / opens the value popup), a **hold (~0.4s)** pops the row and starts a drag-reorder, a **horizontal swipe** reveals delete, and a **vertical drag** scrolls the page. The reorder pop appears the instant the hold fires and auto-shrinks the moment the finger lifts (driven by gesture state, never a stuck flag). A tap must NOT fire after a hold/drag/swipe.
- **Swipe-to-delete behaviour:** swiping a row reveals a red circular trash that **slides in from the trailing edge** (content + trash move together, clipped — never flash in over the row). It **stays open**; drag back to close; **tap the trash to delete** (there is NO full-swipe-to-delete and no expand-to-fill). Opening one row's trash, or interacting with anything else (editing, a control), **auto-closes** an open one — but **scrolling does not** close it.
- **Popups are sized to their content, never full-width.** The anchored popups use a fixed/intrinsic width and drop under the tapped value (right-aligned for trailing values), not a full-width sheet.
- **Tapping out of an open keypad/keyboard/popup just dismisses it** — it does not also open whatever was tapped. Any value/title tap first checks "is something open? if so close it and return" (`dismissOpenInputIfAny`), so an accidental tap on a `##h ##m` value while the keypad is up only closes the keypad.

## Undo/redo (shake-triggered)

A **phone shake** opens a DSKit popup (`Features/Undo/UndoRedoPopup.swift`) with three fixed-size rows: **Undo**, **Redo**, and **Close**. The Undo/Redo rows are each labelled with the pithy, specific action they'd act on, **including the item's title** ("Add task “poop”", "Delete project “Home”" — built via the `undoTitle(_:)` helper, which quotes the name and falls back to "Untitled"); the side with nothing to do is greyed/disabled. The popup is fixed size and fixed-centred (never shifts with content — every row is a fixed 72pt height with single-line labels), stays open after a press so you can chain, and closes **only via the Close button** (outside taps are absorbed, never dismiss). Shake is caught app-wide by `ShakeDetector` (a first-responder VC posting `.humanProgramShake`); `ContentView` shows the popup only during normal use (never over the lock/onboarding/interstitial covers).

The engine (`Core/Undo/`) is **snapshot-based, in-memory, ONE global stack**, cleared on every cold launch (never persisted) and on factory-reset / `.hprgm` restore (`UndoStore.shared.clear()` — else a shake-undo would resurrect deleted objects by id). `UndoStore` is an `@Observable @MainActor` singleton (depth cap 50; `redo` stack cleared on any new action; same-key bursts like one drag-reorder coalesce within 0.6s). Each action is two op lists (`undoOps`/`redoOps`) of `upsert(snapshot)` / `remove(type,id)` primitives that re-resolve objects by their stable String `id`, so they survive delete→recreate cycles. Per-type value snapshots live in `UndoSnapshots.swift` (capture ALL fields incl. `createdAt`/`updatedAt` and relationships as ids, so a recreate is faithful and keeps its list position).

**To make a new mutation undoable**, record at the user-commit call site (NOT deep in the repo — granularity is "an edit + its Save = 1 action; a delete = 1 action; a create = 1 action"): `Undo.created/deleted/edited(...)` for single objects, `Undo.record(undoOps:redoOps:)` for multi-object (multi-delete, move, delete-project-and-its-tasks), or `Undo.recordContainer(...)` for a lazy-create/commit-on-leave editor that's best recorded once per visit (Routines). Capture the *before* snapshot **before** the entity is mutated. Pass `post: .pageRefresh` when the original action refreshed today/future pages (recurring, schedule, exercise) or `post: .rescheduleReminders` for reminders.

**In scope:** Today tasks, Backlog (items + projects + move + multi-select), Recurring, Reminders, Schedule, Exercise, Routines — create/edit/delete/toggle/reorder. **Out of scope (never recorded):** anything calendar (EventKit events, calendar-sourced Today tasks, reconciliation, calendar settings), all Settings categories (customization/format/accessibility/security/import/export/reset/restore), view switches, sort-mode changes, past-page lock/unlock, and any automatic/system refresh.

## Navigation model (post-DSKit rebuild)

The **hub** (`HubView` in `App/ContentView.swift`) is the navigation **root** — a static, centered 2×3 grid of liquid-glass tiles (Today, Backlog, Calendar, Routines, Stats, Settings), no title/back arrow. On launch the app deep-links straight to **Today** (pushed on top of the hub), so every section's upper-left back arrow returns to the hub. **No tab bar.** The app-unlock gate is a `fullScreenCover` over everything.

## What's built and what isn't

### Built
- Core: `RecurrenceRule`/`RecurrenceEngine`, all SwiftData models, `DailyPageGenerator`, `CompletionService`, `BacklogMaintenanceService`, `StreakCalculator`, EventKit calendar service, notification scheduling.
- Repositories: `DailyPageRepository` (get-or-create, snapshot protection, refresh, toggle, add/delete/update task, unlock/lock, `severPastTasks`), `BacklogRepository`, `ExerciseRepository`, `RoutineRepository`, `NotificationReminderRepository`, `ScheduleRepository`, `AppLockRepository`.
- Navigation: hub-root + Today launch (see Navigation model above), no tab bar; full-screen Welcome/reset/restore interstitials (`hp.hasLaunched` flag).
- DSKit screens: Today (timeline + now-bar + past lock/unlock + task detail; the timeline supports **vertical pinch-zoom** — `DailyTimeline` — from the full 00:00–24:00 down to a 4-hour window, focal-point anchored, with 3-hour→hourly→half-hourly grid lines as it zooms and every visible line labelled; zoom is in-memory only, resetting when the screen is left and surviving backgrounding; tapping a **calendar** block opens its event card, schedule blocks are inert), full Backlog (Task/Project views, folders, swipe/select delete, move, task detail), Calendar tab (Month/Week/Day/List + EventKit create/edit), Routines (grid + emoji editor), Stats (streaks + week chart), Settings + every sub-screen (Customization, Format, Reminders + editor + sound, Recurring + editor, Schedule + editor, Exercise + editor, Calendar Sources, Security (PIN/App Lock/Face ID) + shared `PINEntryView` + unlock gate, About/Licenses, Factory Reset + PIN gate, Import (text/CSV/.hprgm restore) + Export).
- Past-page ↔ backlog/calendar decoupling (`severPastTasks` at rollover).
- **Today navigation floor:** an install date (`DefaultsKey.installDate`, set once at first launch in `AppStartup`) floors how far back the Today screen can go — `TodayViewModel.minNavigableDate` = `min(installDate, earliest existing page)`. Navigation/jump are clamped to it (left arrow disables at the floor; the jump picker passes it as `minDate`). The `min` with the earliest page is what keeps a **.hprgm restore's** older pages reachable; clamping navigation is what stops back-stepping from endlessly creating ever-earlier pages. `installDate` is in `allKeys` (factory reset re-anchors it) but is NOT a `.hprgm` user-preference (restore handles older pages via the `min`).
- **Home-screen widgets** (`HumanProgramWidget/` — a WidgetKit `app-extension` target): a small ("Today Count" — completed/total) and a medium ("Today Tasks" — outstanding list + count); both deep-link `humanprogram://today` to the Today screen (handled by `onOpenURL` in `ContentView`). When the day is complete they show "All done" but still show the count. They DON'T open the SwiftData store — the app publishes a tiny `WidgetSnapshot` to a shared **App Group** (`group.app.humanprogram`) via `WidgetSync.refresh(context:)` (called from `AppStartup` and every Today mutation), and the widget reads it. The App Group is a new entitlement on BOTH targets (`*.entitlements`); `WidgetShared.swift` is the only file compiled into both. The widget snapshot is not a `@Model` and is not in `.hprgm`.
- **Unified text selection color:** a soft lavender (`appSelectionLavender`) set once on `UITextField.appearance().tintColor` + `UITextView.appearance().tintColor` in `HumanProgramApp.init()`, so every caret/selection (SwiftUI `TextField` is UITextField-backed; `AppTextField` is a UITextView) matches instead of a per-field default that could render invisibly.
- Calendar ↔ Today reconciliation (`CalendarReconciliationView`, reached from the Calendar top-bar sync button): deleting/hiding a calendar event removes it from Today and persists (via `CalendarEventLocalState.hidden`); the page lists today/future discrepancies and restores them.
- Tests: recurrence, generation, completion, streaks, exercise repo, past-page decoupling, backup round-trip (71 passing). Note: the test target is **host-based** (loads symbols + DSKit from the app); don't revert that in `project.yml`.

### Not yet built / out of scope
- The hidden game is **removed**, not pending — do not re-add a game, gate, or unlock.
- Cat Corner photo gallery (owner will provide photos) — viewer exists, intentionally a full-screen black immersive view (not DSKit).

---

## Decisions already locked in — do not change without owner approval

These are not up for debate. If a task seems to require changing one of these, stop and ask the owner first.

- **iOS 17.6+ minimum.** Raised from 17.0 (2026-05-29) because DSKit requires 17.6. SwiftData only, no Core Data fallback.
- **DSKit is the app's UI framework (owner-approved 2026-05-29).** This REVERSES the former "zero third-party dependencies" rule. The app binary now ships three Swift packages: `DSKit` (MIT), and its transitive deps `SDWebImage` + `SDWebImageSwiftUI` (both MIT). Their licenses are credited in the in-app Licenses screen (Settings → About → Licenses). Any OTHER new third-party package still needs explicit owner approval first. XcodeGen remains a dev tool only (never ships).
- **No cloud, no analytics, no Firebase, no trackers.** Everything stays on device.
- **App lock = Face ID + PIN (4–40 digits).** Forgotten PIN = reset app. No recovery phrase, no iCloud backup of the PIN. The lock engages on **cold launch** (a force-quit→reopen must lock) as well as on the background→foreground timeout; **Face ID auto-engages** when the lock screen appears and whenever the app becomes active (re-armed once per lock so a Face ID cancel can't loop). There is **no PIN lockout / wait-after-N-failures** — a wrong PIN just shakes and clears (owner-removed; do not re-add).
- **Every font renders at the same vertical (cap) height per size.** `FontSpec.uiFont` normalizes each typeface's cap height to the default font's, so switching the font choice changes style/width but never how tall the text is. Don't add per-font `sizeMultiplier` hacks to "match" — the normalization handles it.
- **Backup files (`.hprgm`) are not encrypted.** App lock protects the data on device. Backup files are plain.
- **`.hprgm` = the FULL app state (format v2).** Export/import (`HprgmExportService`/`HprgmImportService`, bundle = `HprgmBundle`) must cover **every** `@Model`, PLUS the user's UserDefaults preferences (font, font size, appearance, app icon, backgrounds, date/time format, selected calendar IDs). It deliberately EXCLUDES the PIN / Face ID / app-lock keys (the restore screen says "Your PIN and Face ID stay as they are"). If you add a new `@Model` or a new user-preference key, you MUST add it to the bundle + export fetch + import insert, or backups silently lose it. New bundle fields must be **optional** so older backups still decode. Round-trip fidelity is pinned by `HprgmBackupRoundTripTests`.
- **Sleep block is mandatory** as the first block in every schedule template.
- **Exercise does not count toward day completion** unless the user also creates a separate recurring task for it.
- **No confirmation dialogs for delete.** The plan is undo/redo. Skip the confirmation for now. (Swipe-to-delete is allowed — the old "no swipe-to-delete" rule was removed at the owner's request; it's now used for schedule blocks.)
- **Weekday 1=Sun, 2=Mon … 7=Sat everywhere.** Do not change this encoding.

---

## Testing guidance

- Run `make test` before committing anything that touches `Core/`.
- The most important test file is `PastPageSnapshotTests.swift` — the snapshot protection rule (past pages never modified) is the #1 invariant. Make sure those tests pass.
- Pure service tests (`RecurrenceEngine`, `CompletionService`, etc.) do not need a SwiftData container. Just instantiate the struct and call it.
- SwiftData model tests use `makeTestModelContainer()` — an in-memory container that leaves no files on disk.
- If you add a new service, add unit tests for it in `HumanProgramTests/`.

### Verifying screens in the simulator (when you can't tap)

> **Only when explicitly told to** (see Working rules #2 at the top). Do not reach for the simulator on your own — describe what you'd verify and wait for the go-ahead. **When told, use iPhone 17 Pro, iOS 26.4 (not 26.5).**

You can build/install/launch the app and take screenshots, but on this machine there is **no UI-tap automation** (no `idb`/`cliclick`; AppleScript/System Events lacks Accessibility permission). That means you can't tap/scroll/type to navigate. This is NOT a reason to skip visual verification — **if navigation by tapping doesn't work, render the target screen directly instead:**

- **Flag-gated screens** (Welcome, Terms gate, reset/restore interstitials, anything behind an `@AppStorage`/state flag): set the underlying value with `xcrun simctl spawn booted defaults write <bundle-id> <key> -bool YES/...`, relaunch, and the app opens onto that screen. (Bundle id: `app.humanprogram.ios`.)
- **Pushed/nested pages** (e.g. About → Tutorial, a row deep in Settings): add a tiny *temporary* launch override — point the app root (or the launch nav `path`) straight at that view — build, screenshot, then revert the override. Renders any view in isolation regardless of depth.
- **Specific interaction states** (e.g. "Confirm enabled after the agree box is checked"): temporarily initialize that view's `@State` (or the gating flag) to the post-interaction value and screenshot. You verify the before/after states by rendering; you verify the wiring between them by reading the code.

Use this as a fallback whenever tapping fails — don't fall back to "I couldn't verify it." The only thing it can't prove is the literal tap transition firing, which is cheap to confirm by inspection.

---

## How to talk to the owner

The owner is a beginner iOS developer. When you finish a task or explain a change:
- Use plain language. Avoid jargon. If you must use a technical term, define it briefly.
- Say exactly what you changed and what to test to verify it works.
- Keep explanations short. Go deeper only if asked.
- Ask questions only when you genuinely cannot proceed without an answer. Don't ask for things you can figure out from context or this file.

### Don't overpromise

- **Never claim "done," "complete," "production-ready," or "100%"** unless every core feature, flow, persistence path, and QA item for that work has actually been verified. The owner is frustrated by overpromising and partial-completion claims. If something is partially done, say exactly what works and what doesn't.
- **No decorative-only work.** Every page, function, and tool must have a real working purpose. A screen is not finished just because it opens — remove or replace placeholder-only routes and stubs rather than leaving them to look complete.

### Work in tested checkpoints

- Make changes in chunks small enough to test. Keep the app buildable and usable after each significant chunk — don't pile up large unverified edits.
- Commit only after the behavior actually works and the owner approves or asks.
- **Commit messages must NEVER include a `Co-Authored-By: Codex ...` line** (or any AI-attribution trailer). Leave it out of every commit, always.
- Fold durable lessons into the maintained docs (`AGENTS.md`, `ADD.md`). Don't create separate long-lived handoff/notes files as a parallel source of truth.
