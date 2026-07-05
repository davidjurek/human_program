import SwiftUI
import SwiftData
import DSKit
import EventKit

// Today ↔ templates "differences" report (today & future only).
//
// A recurring task or an assigned backlog item that the templates say belongs on a day
// can be DELETED from that day's Today page (the delete is honored and sticks — the
// backlog item itself keeps its date on the Backlog screen). A deleted calendar event
// is likewise hidden from Today. This page lists those missing items for the viewed day
// and lets the user restore them, mirroring the Calendar reconciliation page.
//
// Past days are frozen snapshots, so they have NO differences report — the padlock owns
// that top-right slot there instead.

// MARK: - Difference models

/// A recurring/backlog item expected on the page but currently deleted (hidden).
struct PageTaskDifference: Identifiable, Equatable {
    enum Kind { case recurring, backlog }
    let id: String
    let kind: Kind
    let title: String
    let sourceId: String       // recurring template id / backlog item id
}

/// A calendar event hidden from the Today page on a given day.
struct CalendarEventDifference: Identifiable, Equatable {
    let id: String
    let eventId: String
    let title: String
    let date: Date
}

// MARK: - Shared computation

/// Computes recurring/backlog differences for a page by comparing what the templates
/// WOULD generate for that date against what's actually present. The missing ones are
/// exactly the items the user deleted (they're in the page's hidden lists). Shared by the
/// Today capsule count and the differences page so both agree. [today-diffs]
enum TodayDifferenceEngine {
    static func taskDifferences(
        page: DailyPage,
        recurring: [RecurringTaskInput],
        backlog: [BacklogTaskInput],
        schedule: [ScheduleBlockInput]
    ) -> [PageTaskDifference] {
        let expected = DailyPageGenerator().generate(
            date: page.date,
            recurringTemplates: recurring,
            backlogItems: backlog,
            scheduleTemplates: schedule
        )
        let presentRecurring = Set(page.tasks.filter { $0.sourceType == .recurring }.compactMap { $0.sourceId })
        let presentBacklog = Set(page.tasks.filter { $0.sourceType == .backlog }.compactMap { $0.sourceId })

        var diffs: [PageTaskDifference] = []
        for t in expected.tasks where t.sourceType == .recurring {
            if let sid = t.sourceId, !presentRecurring.contains(sid) {
                diffs.append(PageTaskDifference(id: "recurring|\(sid)", kind: .recurring, title: t.title, sourceId: sid))
            }
        }
        for t in expected.tasks where t.sourceType == .backlog {
            if let sid = t.sourceId, !presentBacklog.contains(sid) {
                diffs.append(PageTaskDifference(id: "backlog|\(sid)", kind: .backlog, title: t.title, sourceId: sid))
            }
        }
        return diffs
    }
}

// MARK: - Count capsule (sits where the past-day padlock sits)

/// Outline capsule with the difference count. Matches the padlock's 66×32 footprint so
/// the top-right slot looks identical between past days (padlock) and today/future
/// (this). Light green when 0, light yellow when > 0.
struct DiffCountButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        let color = count == 0 ? appDiffZeroGreen : appDiffYellow
        Button(action: action) {
            ZStack {
                Capsule().strokeBorder(color, lineWidth: 2)
                Text("\(count)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 66, height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: count == 0)
    }
}

// MARK: - Differences page

struct TodayDifferencesView: View {
    @Environment(\.modelContext) private var context
    let date: Date

    @State private var taskDiffs: [PageTaskDifference] = []
    @State private var calDiffs: [CalendarEventDifference] = []
    @State private var selected: Set<String> = []
    @State private var calendarService = CalendarAdapterService()

    private var pageRepo: DailyPageRepository { DailyPageRepository(context: context) }
    private var stateRepo: CalendarLocalStateRepository { CalendarLocalStateRepository(context: context) }
    private var selectedCalendarIds: [String] {
        UserDefaults.standard.stringArray(forKey: DefaultsKey.selectedCalendarIds) ?? []
    }

    /// One flat, ordered list of every difference row (recurring, backlog, then calendar).
    private var rows: [(id: String, title: String, subtitle: String)] {
        taskDiffs.map { ($0.id, $0.title, $0.kind == .recurring ? "Recurring" : "Backlog") }
            + calDiffs.map { ($0.id, $0.title, "Calendar") }
    }

    var body: some View {
        SettingsScreen(centered: true, trailing: { trailingButtons }) {
            if rows.isEmpty {
                DSText("No differences")
                    .dsTextStyle(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            } else {
                SettingsGroup {
                    ForEach(rows, id: \.id) { r in
                        row(id: r.id, title: r.title, subtitle: r.subtitle)
                    }
                }
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - Toolbar (select-all toggle + Restore)

    @ViewBuilder
    private var trailingButtons: some View {
        if !rows.isEmpty {
            HStack(spacing: 4) {
                toggleAllButton
                restoreButton
            }
        }
    }

    private var allSelected: Bool {
        !rows.isEmpty && selected.count == rows.count
    }

    private var toggleAllButton: some View {
        Button {
            if allSelected { selected = [] }
            else { selected = Set(rows.map { $0.id }) }
        } label: {
            Text("Toggle All")
                .font(appFont(17))
                .foregroundStyle(.primary)
                .frame(minHeight: 44).padding(.horizontal, 8)
                .contentShape(Rectangle())
                .a11yTapBorder(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }

    private var restoreButton: some View {
        Button { restoreSelected() } label: {
            Text("Restore")
                .font(appFont(17))
                .foregroundStyle(selected.isEmpty ? .secondary : .primary)
                .frame(minHeight: 44).padding(.horizontal, 8)
                .contentShape(Rectangle())
                .a11yTapBorder(cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
    }

    // MARK: - Row

    private func row(id: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Button { toggle(id) } label: {
                SelectionCircle(isOn: selected.contains(id))
            }
            .buttonStyle(.plain)
            .a11yTapBorder(Circle())

            VStack(alignment: .leading, spacing: 2) {
                DSText(title).dsTextStyle(.body).longTitle(lineLimit: 2)
                DSText(subtitle).dsTextStyle(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 48)
    }

    // MARK: - Data

    private func reload() {
        taskDiffs = computeTaskDiffs()
        calDiffs = computeCalendarDiffs()
        selected = selected.intersection(Set(rows.map { $0.id }))
    }

    private func computeTaskDiffs() -> [PageTaskDifference] {
        let today = Calendar.current.startOfDay(for: Date())
        guard date >= today, let page = try? pageRepo.fetch(date: date),
              let inputs = try? TemplateInputs.fetchAll(context: context) else { return [] }
        return TodayDifferenceEngine.taskDifferences(
            page: page, recurring: inputs.recurring, backlog: inputs.backlog, schedule: inputs.schedule)
    }

    private func computeCalendarDiffs() -> [CalendarEventDifference] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard start >= cal.startOfDay(for: Date()), !selectedCalendarIds.isEmpty else { return [] }
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let events = calendarService.fetchEvents(from: start, to: end, calendarIds: selectedCalendarIds)
        let hidden = (try? stateRepo.hiddenEventIds(for: start)) ?? []
        return events.compactMap { ev in
            guard let eid = ev.eventIdentifier, hidden.contains(eid) else { return nil }
            return CalendarEventDifference(id: "calendar|\(eid)", eventId: eid,
                                           title: ev.title ?? "(no title)", date: start)
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func restoreSelected() {
        let ids = selected
        let page = try? pageRepo.fetch(date: date)

        // Un-hide each selected item on its source.
        for d in taskDiffs where ids.contains(d.id) {
            switch d.kind {
            case .recurring: page?.unhideRecurringTask(id: d.sourceId)
            case .backlog:   page?.unhideBacklogTask(id: d.sourceId)
            }
        }
        for d in calDiffs where ids.contains(d.id) {
            try? stateRepo.setHidden(false, eventId: d.eventId, date: d.date)
        }
        try? context.save()

        // Re-add the un-hidden recurring/backlog tasks by refreshing the page from
        // templates. (Restored calendar events flow back when Today reloads.)
        let today = Calendar.current.startOfDay(for: Date())
        if let inputs = try? TemplateInputs.fetchAll(context: context) {
            _ = try? pageRepo.getOrCreate(
                date: date, today: today,
                recurringTemplates: inputs.recurring,
                backlogItems: inputs.backlog,
                scheduleTemplates: inputs.schedule)
        }

        selected = []
        reload()
    }
}
