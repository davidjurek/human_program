import SwiftUI
import SwiftData
import DSKit
import EventKit

// Calendar ↔ Today reconciliation.
//
// Because the user can delete a calendar-sourced item from the Today tasks list,
// the set of events shown in Today can fall OUT OF SYNC with the calendar — there
// can be fewer events in Today than in the calendar (never more). This page lists
// those discrepancies (events that are in the calendar but were removed from Today)
// for TODAY and the FUTURE only — past days are frozen snapshots we don't reconcile.
//
// The user can confirm the discrepancy is acceptable (leave it), tap an event to see
// its card, or select events and Restore them (or Restore All), which un-hides them
// so they flow back into the Today page on its next refresh.
struct CalendarReconciliationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var calendarService = CalendarAdapterService()
    @State private var discrepancies: [Discrepancy] = []
    @State private var selected: Set<String> = []
    @State private var detailEvent: EKEvent?
    @State private var detailDate = Date()
    @State private var showDetail = false

    /// How far ahead to look for discrepancies.
    private let windowDays = 120

    private var selectedCalendarIds: [String] {
        UserDefaults.standard.stringArray(forKey: DefaultsKey.selectedCalendarIds) ?? []
    }
    private var stateRepo: CalendarLocalStateRepository { CalendarLocalStateRepository(context: context) }

    typealias Discrepancy = CalendarReconciliation.Discrepancy

    var body: some View {
        SettingsScreen(centered: true, trailing: { trailingButtons }) {
            if discrepancies.isEmpty {
                DSText("Today is in sync with your calendar")
                    .dsTextStyle(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            } else {
                // Flat list (no date grouping); each row is title + "time date".
                SettingsGroup {
                    ForEach(discrepancies) { d in
                        row(d)
                    }
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            if let ev = detailEvent {
                CalendarEventDetailSheet(event: ev, date: detailDate, context: context)
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - Toolbar (select-all toggle + Restore)

    @ViewBuilder
    private var trailingButtons: some View {
        if !discrepancies.isEmpty {
            HStack(spacing: 4) {
                toggleAllButton
                restoreButton
            }
        }
    }

    /// True when every discrepancy is currently selected.
    private var allSelected: Bool {
        !discrepancies.isEmpty && selected.count == discrepancies.count
    }

    /// Selects all when none / some are selected; clears when all are selected.
    private var toggleAllButton: some View {
        Button {
            if allSelected { selected = [] }
            else { selected = Set(discrepancies.map { $0.id }) }
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

    /// Restores the SELECTED items. Greyed + disabled until something is selected.
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

    private func row(_ d: Discrepancy) -> some View {
        // The circle is centered on the TITLE line only; the time/date sits below
        // and does not shift that alignment (custom `.titleCenter` guide).
        HStack(alignment: .titleCenter, spacing: 12) {
            Button { toggle(d.id) } label: {
                SelectionCircle(isOn: selected.contains(d.id))
            }
            .buttonStyle(.plain)
            .a11yTapBorder(Circle())
            .alignmentGuide(.titleCenter) { $0[VerticalAlignment.center] }

            VStack(alignment: .leading, spacing: 2) {
                DSText(d.event.title ?? "(No title)").dsTextStyle(.body).longTitle(lineLimit: 2)
                    .alignmentGuide(.titleCenter) { $0[VerticalAlignment.center] }
                DSText(timeDateLabel(d)).dsTextStyle(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                detailEvent = d.event
                detailDate = d.date
                showDetail = true
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 48)
    }

    /// "time date" on one line, honoring the Time + Date Format settings,
    /// e.g. "7:00 PM Jun 2, 2026" (or "All day Jun 2, 2026").
    private func timeDateLabel(_ d: Discrepancy) -> String {
        let time: String
        if d.event.isAllDay {
            time = "All day"
        } else if let start = d.event.startDate {
            time = clockString(date: start)
        } else {
            time = ""
        }
        let date = AppDateFormat.userPreferred(d.date)
        return time.isEmpty ? date : "\(time) \(date)"
    }

    // MARK: - Data

    private func reload() {
        discrepancies = CalendarReconciliation.discrepancies(
            calendarService: calendarService, stateRepo: stateRepo,
            selectedCalendarIds: selectedCalendarIds, windowDays: windowDays)
        selected = selected.intersection(Set(discrepancies.map { $0.id }))
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func restore(_ items: [Discrepancy]) {
        for d in items {
            guard let eid = d.event.eventIdentifier else { continue }
            // Un-hide: the event flows back into the Today page on its next refresh.
            try? stateRepo.setHidden(false, eventId: eid, date: d.date)
        }
        selected = []
        reload()
    }

    private func restoreSelected() { restore(discrepancies.filter { selected.contains($0.id) }) }
}

// MARK: - Title-centered alignment

private extension VerticalAlignment {
    /// Centers an external view (the selection circle) on the title line of a
    /// title-over-subtitle group, ignoring the subtitle below.
    enum TitleCenterID: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    static let titleCenter = VerticalAlignment(TitleCenterID.self)
}

// MARK: - Shared discrepancy computation

/// Computes the calendar↔Today discrepancies (today/future calendar events the user
/// removed from Today). Shared by the reconciliation page AND the Calendar top-bar
/// "Sync: N differences" count so both agree.
enum CalendarReconciliation {
    struct Discrepancy: Identifiable {
        let id: String          // "eventId|day"
        let event: EKEvent
        let date: Date          // start-of-day
    }

    @MainActor
    static func discrepancies(calendarService: CalendarAdapterService,
                              stateRepo: CalendarLocalStateRepository,
                              selectedCalendarIds: [String],
                              windowDays: Int = 120) -> [Discrepancy] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: windowDays, to: today) ?? today
        guard !selectedCalendarIds.isEmpty else { return [] }

        let events = calendarService.fetchEvents(from: today, to: end, calendarIds: selectedCalendarIds)

        var hiddenByDay: [Date: Set<String>] = [:]
        for state in (try? stateRepo.fetchAllHidden()) ?? [] {
            hiddenByDay[cal.startOfDay(for: state.date), default: []].insert(state.eventId)
        }

        var result: [Discrepancy] = []
        for ev in events {
            guard let eid = ev.eventIdentifier, let start = ev.startDate else { continue }
            let day = cal.startOfDay(for: start)
            guard day >= today else { continue }                 // today/future only
            if hiddenByDay[day]?.contains(eid) == true {
                result.append(Discrepancy(id: "\(eid)|\(day.timeIntervalSince1970)", event: ev, date: day))
            }
        }
        return result.sorted {
            $0.date != $1.date ? $0.date < $1.date
                : (($0.event.startDate ?? .distantPast) < ($1.event.startDate ?? .distantPast))
        }
    }
}
