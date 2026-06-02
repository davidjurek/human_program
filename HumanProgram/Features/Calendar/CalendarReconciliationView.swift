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

    /// One event that is in the calendar but removed from its Today page.
    struct Discrepancy: Identifiable {
        let id: String          // "eventId|day"
        let event: EKEvent
        let date: Date          // start-of-day
    }

    var body: some View {
        SettingsScreen(centered: true, trailing: { restoreButton }) {
            DSText("Sync")
                .dsTextStyle(.title2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)

            if discrepancies.isEmpty {
                DSText("Today is in sync with your calendar")
                    .dsTextStyle(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            } else {
                ForEach(groupedDates, id: \.self) { day in
                    SettingsGroup(title: AppDateFormat.weekdayMonthDay(day)) {
                        ForEach(discrepancies.filter { $0.date == day }) { d in
                            row(d)
                        }
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

    // MARK: - Toolbar restore button

    @ViewBuilder
    private var restoreButton: some View {
        if !discrepancies.isEmpty {
            Button {
                if selected.isEmpty { restoreAll() } else { restoreSelected() }
            } label: {
                Text(selected.isEmpty ? "Restore All" : "Restore (\(selected.count))")
                    .font(appFont(17))
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44).padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .a11yTapBorder(cornerRadius: 6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Row

    private func row(_ d: Discrepancy) -> some View {
        HStack(spacing: 12) {
            Button { toggle(d.id) } label: {
                SelectionCircle(isOn: selected.contains(d.id))
            }
            .buttonStyle(.plain)
            .a11yTapBorder(Circle())

            VStack(alignment: .leading, spacing: 2) {
                DSText(d.event.title ?? "(No title)").dsTextStyle(.body).longTitle(lineLimit: 2)
                DSText(timeLabel(d.event)).dsTextStyle(.subheadline)
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

    private func timeLabel(_ ev: EKEvent) -> String {
        if ev.isAllDay { return "All day" }
        guard let start = ev.startDate else { return "" }
        return clockString(date: start)
    }

    // MARK: - Data

    private var groupedDates: [Date] {
        Array(Set(discrepancies.map { $0.date })).sorted()
    }

    private func reload() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: windowDays, to: today) ?? today
        guard !selectedCalendarIds.isEmpty else { discrepancies = []; return }

        let events = calendarService.fetchEvents(from: today, to: end, calendarIds: selectedCalendarIds)

        // Build per-day hidden-id sets once from all hidden rows.
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
        discrepancies = result.sorted {
            $0.date != $1.date ? $0.date < $1.date
                : (($0.event.startDate ?? .distantPast) < ($1.event.startDate ?? .distantPast))
        }
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
    private func restoreAll() { restore(discrepancies) }
}
