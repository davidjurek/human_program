import SwiftUI
import DSKit

// Custom DSKit date picker [#13]: a card-less, app-font date VALUE that opens a
// custom month-grid calendar popup (app font, our glass) — replaces the system
// `DatePicker` everywhere (Schedule From/To, Add-event Starts/Ends, Stats jump,
// Backlog Assigned Date). System pickers used the wrong font + a gray capsule.

/// The month-grid calendar (app font). Bound to a date; optional lower bound.
struct DSCalendarView: View {
    @Binding var date: Date
    var minDate: Date? = nil
    @State private var month: Date = Date()

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: 12) {
            // Month nav.
            HStack {
                DSText(monthTitle).dsTextStyle(.headline)
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.primary).frame(width: 40, height: 36).contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
                Button { step(1) } label: { Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.primary).frame(width: 40, height: 36).contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
            }
            // Weekday header.
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    DSText(weekdays[i]).dsTextStyle(.caption1).frame(maxWidth: .infinity)
                }
            }
            // Day grid.
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 38) }
                }
            }
        }
        .onAppear { month = cal.startOfDay(for: date) }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSel = cal.isDate(day, inSameDayAs: date)
        let isToday = cal.isDateInToday(day)
        let disabled = minDate.map { day < cal.startOfDay(for: $0) } ?? false
        return Button {
            if !disabled { date = day }
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(appFont(15, bold: isToday))
                .foregroundStyle(isSel ? Color.white : (disabled ? Color.secondary.opacity(0.4) : (isToday ? Color.accentColor : Color.primary)))
                .frame(width: 34, height: 34)
                .background(Circle().fill(isSel ? Color.accentColor : Color.clear))
                .frame(maxWidth: .infinity, minHeight: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(disabled)
        .a11yTapBorder(Rectangle())
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: month)
    }
    private func step(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: month) { month = m }
    }
    /// 42-slot grid (leading blanks + days of `month`).
    private var gridDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let leading = cal.component(.weekday, from: first) - 1   // 1=Sun
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        var out: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<count { out.append(cal.date(byAdding: .day, value: d, to: first)) }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }
}

/// Card-less date value (app font, no capsule) that opens the calendar popup. [#13]
struct DSDateField: View {
    @Binding var date: Date
    var minDate: Date? = nil
    var fontSize: CGFloat = 17
    @State private var show = false

    private var label: String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: date)
    }

    var body: some View {
        Button { show = true } label: {
            Text(label).font(appFont(fontSize)).foregroundStyle(.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .a11yTapBorder(cornerRadius: 4)
        .sheet(isPresented: $show) {
            ZStack {
                SettingsBackground().ignoresSafeArea()
                VStack {
                    HStack {
                        Spacer()
                        Button { show = false } label: { DSText("Done").dsTextStyle(.headline).contentShape(Rectangle()) }.buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
                    }
                    DSCalendarView(date: $date, minDate: minDate)
                    Spacer()
                }
                .padding(20)
            }
            .presentationDetents([.medium])
        }
    }
}

/// Card-less time value (app font) that opens an app-font wheel picker. [#13]
struct DSTimeField: View {
    @Binding var date: Date
    @State private var show = false
    private let cal = Calendar.current

    private var label: String { clockString(date: date) }
    private var hour: Binding<Int> {
        Binding(get: { cal.component(.hour, from: date) },
                set: { date = cal.date(bySettingHour: $0, minute: cal.component(.minute, from: date), second: 0, of: date) ?? date })
    }
    private var minute: Binding<Int> {
        Binding(get: { cal.component(.minute, from: date) },
                set: { date = cal.date(bySettingHour: cal.component(.hour, from: date), minute: $0, second: 0, of: date) ?? date })
    }

    var body: some View {
        Button { show = true } label: {
            Text(label).font(appFont(17)).foregroundStyle(.primary).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .a11yTapBorder(cornerRadius: 4)
        .sheet(isPresented: $show) {
            ZStack {
                SettingsBackground().ignoresSafeArea()
                VStack {
                    HStack {
                        Spacer()
                        Button { show = false } label: { DSText("Done").dsTextStyle(.headline).contentShape(Rectangle()) }.buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
                    }
                    HStack(spacing: 0) {
                        Picker("", selection: hour) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).font(appFont(20)).tag($0) }
                        }.pickerStyle(.wheel).frame(maxWidth: .infinity)
                        DSText(":").dsTextStyle(.title2)
                        Picker("", selection: minute) {
                            ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).font(appFont(20)).tag($0) }
                        }.pickerStyle(.wheel).frame(maxWidth: .infinity)
                    }
                    Spacer()
                }
                .padding(20)
            }
            .presentationDetents([.height(300)])
        }
    }
}
