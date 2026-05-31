# CLAUDE.md — Human Program

This file is instructions for AI coding agents (Claude Code) working on this project. Read it before writing any code.

---

## What this app is

Human Program is a personal daily planning iOS app. Each day gets one generated page. That page combines recurring tasks, backlog items, exercise routines, schedule blocks, and calendar events into one required checklist. Complete all tasks → day is complete → a hidden game unlocks. Nothing syncs to the cloud. Everything stays on device.

---

## How to build

**Requirements:**
- Xcode 15+
- XcodeGen installed: `brew install xcodegen`

**Steps:**
1. Generate the Xcode project: `make setup` (or run `xcodegen generate` in the project root)
2. Open `HumanProgram.xcodeproj` in Xcode
3. Build and run on a simulator or device (iOS 17+)

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
    GameBridge/     — game access service and easter egg gate
    Persistence/    — ModelContainer factory functions
    DesignSystem/   — AppColors, AppTypography tokens
  Features/
    Today/          — primary screen, TodayViewModel, components
    Backlog/        — backlog list (stub, needs full build)
    Settings/       — settings menu + About page + easter egg
    HiddenGate/     — Sudoku puzzle gate (full-screen black)
    Stats/          — streak and completion stats
    Routines/       — simple routine lists
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
4. **Past daily pages must never be modified.** If `isPastLocked == true`, that page is a historical snapshot. Template changes, refreshes, or bulk operations must skip past pages. This is the single most important rule in the entire codebase.
5. **`GameAccessService` is the only bridge between planner and game.** Game code must never query task or page tables directly. All game unlock logic goes through `GameAccessService`.

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
tasks.isNotEmpty && tasks.allSatisfy { $0.isCompleted }
```
That's it. An empty task list is NOT complete. Exercise is not in the task list (unless the user separately created a recurring task for it). Calendar-sourced tasks ARE included.

### GameAccessService
`GameAccessService.canAccessGame(todayPage:today:)` returns `true` only when:
- `todayPage` is not nil
- `todayPage.dayComplete` is `true`
- `todayPage.date` matches today's date (yesterday's completed page does not count)

---

## Design rules — ALWAYS follow these

- **Reuse UI, never duplicate it.** When the same visual element appears in more than one place — a row, a section header, a banner, a button style, a card, a sheet layout, a spacing value — it must come from ONE shared component, modifier, or token. Do not copy-paste a chunk of view code and tweak it. Before building any UI, search the codebase for an existing component that already does it (or nearly does it) and extend that instead. If a change to one screen needs the same change on another, that is a sign the markup should have been shared — extract it into a reusable view rather than editing two copies. This is the single most important UI rule: many small UI edits are coming, and duplicated view code means each fix has to be made in several places and they will drift apart.
- **No stock `List {}` with default iOS styling** for the main task list or backlog list. Use `VStack` with custom row views.
- **Read mode is the default.** Edit controls are hidden until the user enters edit mode.
- **Read and edit modes must share identical layout — no reflow.** Hiding an edit-only control (delete button, reorder handle, inline field) must NOT move other content. Reserve the same spacing, row heights, columns, padding, and alignment in both modes. Build one shared layout and make edit-only controls invisible/disabled in read mode — don't build two separate layouts that "look close."
- **Never eyeball or guess UI positions.** When two screens or states must line up, the shared position must come from one shared layout path, wrapper, or component — not from hand-tuned spacers or trial-and-error offsets. Account for every offsetting element (titles, wrappers, hidden controls, padding, insets, different parent layouts). Never claim a position is precise when any part of it was estimated.
- **No confirmation dialogs for delete.** The plan is undo/redo (not yet built). Don't add "Are you sure?" dialogs as a workaround — just skip the confirmation for now.
- **UI is built on DSKit.** The whole app's UI is migrating to the DSKit design system (`import DSKit`). Use DSKit components (`DSText`, `DSImageView`, `DSButton`, etc.) and the appearance/theme set in `AppTheme.appearance`, applied once at the app root via `.dsAppearance(...)`. `AppColors` / `AppTypography` are LEGACY — they still exist for not-yet-migrated screens, but new or migrated UI must use DSKit, not them. No hardcoded `Color(hex:)` / `.font(.system(size:))` in views.
- **See the "DSKit" section below** for the Settings UI convention and the API gotchas (the tokens are tricky — read it before writing DSKit code).
- **The game is completely hidden.** No button, no hint, no card, no label anywhere in the normal UI.
- **Easter egg path:** About page → double-tap the developer name → Sudoku gate screen → game. If the day is not complete, the double-tap produces a subtle haptic and nothing else. No error message, no explanation.

---

## DSKit — UI framework

The app's UI runs on [DSKit](https://github.com/imodeveloper/dskit-swiftui) (MIT). Migration is phased, screen by screen, with a green build at each checkpoint. Add new files to the project then run `xcodegen generate` BEFORE building, or DSKit-using files won't be found.

### Settings UI convention (the standard for ALL settings screens)

Every Settings-area screen is composed from the shared components in `Features/Settings/Components/SettingsComponents.swift`. Do NOT hand-roll settings rows — reuse these so one change updates every screen:

- `SettingsScreen { ... }` — themed scroll container. Soft lavender→blue→peach **gradient** background (`SettingsBackground`, Settings screens only), **no nav title** (titles are hidden app-wide; back button stays). Top inset 28.
  - **Side margins depend on screen type, set by the `centered` flag:**
    - **Menu screens** (the default, `centered: false`) — **left 42, right 14** (intentional right-shifted asymmetry).
    - **Non-menu screens** (editors, list screens, etc. — pass `centered: true`) — **left 20, right 20** (symmetric).
  - **Swipe-back is re-enabled here.** Hiding the nav bar kills iOS's leading-edge swipe-back gesture, so `SettingsScreen` re-installs it (a recognizer that re-asserts on every (re)appear, so it doesn't go stale after visiting another screen). Editors pass `onBack`/`swipeBackBlocked`: when there are unsaved changes the swipe (and the back button) route through the **discard-changes guard** instead of popping. Toolbar icon buttons (back, `+`, trash, Save) get `.contentShape(Rectangle())` so the whole 44×44 is tappable.
  - A faint **gradient frost** sits behind the top bar so the back/Save buttons stay legible over scrolling content.
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

The Schedule editor is the reference implementation; the wheel/keypad/popup pieces are meant to roll out to the other editors next. Patterns that took many iterations to get right — reuse them, don't re-derive:

- **Toolbar icon buttons need `.contentShape(Rectangle())`** on their 44×44 frame, or only the opaque glyph is tappable and taps near it miss (hit the `+`, trash, etc.). Use the shared `AddNavButton`.
- **Popups all share `popupGlass()`** — one modifier (clear iOS-26 `glassEffect`, blur fallback) used by every popup (confirm dialogs, Repeat dropdown, wheel popups). Change the glass in that one place.
- **Anchored popups** (`AnchoredPopup`, drops under a tapped value) must capture the value's frame and position themselves in **one shared NAMED coordinate space**, never `.global`. The popup layer ignores the safe area, so its `.global` origin doesn't match the content's `.global` frames and the popup jumps to the corner.
- **Numeric entry uses a custom keypad (`GlassKeypad`), NOT the system numpad.** iOS 26 floats keyboard accessory bars, so a flush attached "Done" bar on the system keyboard is impossible. The custom keypad is bottom-pinned liquid glass, feeds HHMM (minutes snap to 5), and ✓/tap-outside close it + the wheel popup.
- **Uniform keyboard gap (text fields):** SwiftUI's automatic keyboard avoidance gives a non-uniform, field-TYPE-dependent gap (a `UITextView`-backed field gets a bigger gap than a plain `TextField`) and fights manual scrolling. The combo that works: (1) disable SwiftUI avoidance on the screen (`SettingsScreen(manualKeyboardAvoidance: true)` → `.ignoresSafeArea(.keyboard)`); (2) add a **bottom content spacer = keyboard height** for scroll room — do NOT use `contentInset` for the room, SwiftUI resets it and the scroll snaps back; (3) a small UIKit `keyboardDidShow` observer scrolls the focused field to a fixed gap (20pt) above the keyboard, only when it's actually covered. Keep title fields the **same SwiftUI `TextField` type** so the measured frames match.
- **Reorder and swipe-to-delete use UIKit recognizers**, not SwiftUI gestures. SwiftUI gesture composition can't cleanly separate tap / hold-to-drag / horizontal-swipe / vertical-scroll on one custom row. Reorder = a `UILongPressGestureRecognizer` (≈0.4s, small allowable movement) on the enclosing scroll view, hit-testing rows by their reported window frames; swipe = a `UIPanGestureRecognizer` that only *begins* for horizontal drags so vertical drags fall through to native scrolling.
- **Editable rows have four distinct, non-overlapping gestures:** a quick **tap** edits (inline title / opens the value popup), a **hold (~0.4s)** pops the row and starts a drag-reorder, a **horizontal swipe** reveals delete, and a **vertical drag** scrolls the page. The reorder pop appears the instant the hold fires and auto-shrinks the moment the finger lifts (driven by gesture state, never a stuck flag). A tap must NOT fire after a hold/drag/swipe.
- **Swipe-to-delete behaviour:** swiping a row reveals a red circular trash that **slides in from the trailing edge** (content + trash move together, clipped — never flash in over the row). It **stays open**; drag back to close; **tap the trash to delete** (there is NO full-swipe-to-delete and no expand-to-fill). Opening one row's trash, or interacting with anything else (editing, a control), **auto-closes** an open one — but **scrolling does not** close it.
- **Popups are sized to their content, never full-width.** The anchored popups use a fixed/intrinsic width and drop under the tapped value (right-aligned for trailing values), not a full-width sheet.
- **Tapping out of an open keypad/keyboard/popup just dismisses it** — it does not also open whatever was tapped. Any value/title tap first checks "is something open? if so close it and return" (`dismissOpenInputIfAny`), so an accidental tap on a `##h ##m` value while the keypad is up only closes the keypad.

## What's built and what isn't

### Built (milestone 1)
- `RecurrenceRule` + `RecurrenceEngine` (full recurrence logic)
- All SwiftData models
- `DailyPageGenerator` (pure logic, no database)
- `CompletionService`, `BacklogMaintenanceService`, `StreakCalculator`
- `DailyPageRepository` (get-or-create, snapshot protection, refresh, toggle completion, add task, delete task)
- `BacklogRepository` (basic CRUD)
- Today screen (date navigation, task list, completion banner, schedule blocks, exercise stub)
- Stub screens for Backlog, Routines, Stats, Settings, About, SudokuGate, GameContainer
- Unit tests for recurrence, generation, completion, streaks, game bridge

### Not yet built (future milestones)
- Full backlog UI (project grouping, bulk select, sorting, text/CSV import)
- Recurring task editor in Settings
- Schedule block editor in Settings
- Exercise block editor in Settings
- Calendar integration (EventKit)
- Notifications
- App lock (Face ID + PIN, 4–20 digits)
- Export/import (`.hprgm` format)
- Stats charts
- Full calendar screen (month/week/day/agenda views)
- Real game integration (Unity or Godot)
- Cat Corner photo gallery (owner will provide photos)

---

## Decisions already locked in — do not change without owner approval

These are not up for debate. If a task seems to require changing one of these, stop and ask the owner first.

- **iOS 17.6+ minimum.** Raised from 17.0 (2026-05-29) because DSKit requires 17.6. SwiftData only, no Core Data fallback.
- **DSKit is the app's UI framework (owner-approved 2026-05-29).** This REVERSES the former "zero third-party dependencies" rule. The app binary now ships three Swift packages: `DSKit` (MIT), and its transitive deps `SDWebImage` + `SDWebImageSwiftUI` (both MIT). Their licenses are credited in the in-app Licenses screen (Settings → About → Licenses). Any OTHER new third-party package still needs explicit owner approval first. XcodeGen remains a dev tool only (never ships).
- **No cloud, no analytics, no Firebase, no trackers.** Everything stays on device.
- **App lock = Face ID + PIN (4–20 digits).** Forgotten PIN = reset app. No recovery phrase, no iCloud backup of the PIN.
- **Backup files (`.hprgm`) are not encrypted.** App lock protects the data on device. Backup files are plain.
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
- Fold durable lessons into the maintained docs (`CLAUDE.md`, `ADD.md`). Don't create separate long-lived handoff/notes files as a parallel source of truth.
