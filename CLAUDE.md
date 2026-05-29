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

- **No swipe-to-delete** anywhere in the app. Not on tasks, not on backlog items, not anywhere.
- **No stock `List {}` with default iOS styling** for the main task list or backlog list. Use `VStack` with custom row views.
- **Read mode is the default.** Edit controls are hidden until the user enters edit mode.
- **No confirmation dialogs for delete.** The plan is undo/redo (not yet built). Don't add "Are you sure?" dialogs as a workaround — just skip the confirmation for now.
- **Color tokens only.** Use `AppColors` enum. No hardcoded `Color(.red)` or `Color(hex:...)` values in views.
- **Font tokens only.** Use `AppTypography` enum. No hardcoded `.font(.system(size: 14))` or similar in views.
- **The game is completely hidden.** No button, no hint, no card, no label anywhere in the normal UI.
- **Easter egg path:** About page → double-tap the developer name → Sudoku gate screen → game. If the day is not complete, the double-tap produces a subtle haptic and nothing else. No error message, no explanation.

---

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

- **iOS 17+ minimum.** SwiftData only, no Core Data fallback.
- **No third-party dependencies in the app binary.** XcodeGen is a dev tool only — it never ships. If you want to add a Swift package, ask first.
- **No cloud, no analytics, no Firebase, no trackers.** Everything stays on device.
- **App lock = Face ID + PIN (4–20 digits).** Forgotten PIN = reset app. No recovery phrase, no iCloud backup of the PIN.
- **Backup files (`.hprgm`) are not encrypted.** App lock protects the data on device. Backup files are plain.
- **Sleep block is mandatory** as the first block in every schedule template.
- **Exercise does not count toward day completion** unless the user also creates a separate recurring task for it.
- **No swipe-to-delete anywhere.** Use undo/redo once that's built.
- **No confirmation dialogs for delete.** Same reason.
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
