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
    /// Optional upper bound: days after it are disabled and month-forward nav stops at
    /// its month (e.g. the Today jump picker caps navigation at year 2100). [owner]
    var maxDate: Date? = nil
    @State private var month: Date = Date()
    /// Tapping the month/year title opens the scroll-wheel month+year jump popup. [owner]
    @State private var showMonthYear = false

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = Weekday.shortLetters   // canonical S M T W T F S (1=Sun) [#148][#193]
    private static let monthAbbrevs = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                       "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        VStack(spacing: 12) {
            // Month nav. The title is inset by colW/2 − half the "S" glyph — computed
            // from the live width via GeometryReader (applies during layout, no state) —
            // so its first letter aligns under the centred Sunday "S". Tapping it opens
            // the month+year scroll wheels. Fixed 36-tall row so it can't nudge ‹ ›. [owner]
            GeometryReader { geo in
                HStack {
                    Button { showMonthYear = true } label: {
                        Text(monthTitle)
                            .font(appFont(24, bold: true))
                            .foregroundStyle(Color.blue)
                            .underline()
                            .frame(height: 36, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
                    .padding(.leading, max(0, geo.size.width / 14 - 4))
                    Spacer()
                    Button { step(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.primary).frame(width: 40, height: 36).contentShape(Rectangle())
                        .a11yTapBorder(Rectangle())
                    Button { step(1) } label: { Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.primary).frame(width: 40, height: 36).contentShape(Rectangle())
                        .a11yTapBorder(Rectangle())
                }
            }
            .frame(height: 36)
            // Weekday header. The whole calendar block is pushed down so the gap from
            // the title row triples (12→36). [owner]
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    DSText(weekdays[i]).dsTextStyle(.caption1).frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 24)
            // Day grid.
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 38) }
                }
            }
        }
        .onAppear { month = cal.startOfDay(for: date) }
        .overlay { monthYearPopup }
    }

    /// Month (Jan…Dec) + year (1900–2100) scroll wheels, app font, in our glass popup.
    @ViewBuilder private var monthYearPopup: some View {
        if showMonthYear {
            ZStack {
                // Fill the calendar's own bounds (no ignoresSafeArea) so the card
                // doesn't re-centre after appearing — it stays in one place. [owner]
                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { showMonthYear = false }
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Picker("", selection: monthIndex) {
                            ForEach(1...12, id: \.self) { m in
                                Text(Self.monthAbbrevs[m - 1]).font(appFont(20)).tag(m)
                            }
                        }.pickerStyle(.wheel).frame(maxWidth: .infinity).clipped()
                        Picker("", selection: yearValue) {
                            ForEach(1900...2100, id: \.self) { y in
                                Text(String(y)).font(appFont(20)).tag(y)
                            }
                        }.pickerStyle(.wheel).frame(maxWidth: .infinity).clipped()
                    }
                    .frame(height: 170)
                    Button { showMonthYear = false } label: {
                        DSText("Done").dsTextStyle(.headline)
                            .padding(.horizontal, 24).padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
                }
                .padding(16)
                .frame(width: 300)
                .popupGlass(cornerRadius: 22)
            }
        }
    }

    private var monthIndex: Binding<Int> {
        Binding(get: { cal.component(.month, from: month) },
                set: { setMonthYear(month: $0, year: cal.component(.year, from: month)) })
    }
    private var yearValue: Binding<Int> {
        Binding(get: { cal.component(.year, from: month) },
                set: { setMonthYear(month: cal.component(.month, from: month), year: $0) })
    }
    /// Jump the displayed grid to a month/year, clamped to min/maxDate if present.
    private func setMonthYear(month m: Int, year y: Int) {
        var c = DateComponents(); c.year = y; c.month = m; c.day = 1
        guard var d = cal.date(from: c) else { return }
        if let maxDate, cal.compare(d, to: maxDate, toGranularity: .month) == .orderedDescending {
            d = cal.dateInterval(of: .month, for: maxDate)?.start ?? d
        }
        if let minDate, cal.compare(d, to: minDate, toGranularity: .month) == .orderedAscending {
            d = cal.dateInterval(of: .month, for: minDate)?.start ?? d
        }
        month = d
    }

    private func dayCell(_ day: Date) -> some View {
        let isSel = cal.isDate(day, inSameDayAs: date)
        let isToday = cal.isDateInToday(day)
        let belowMin = minDate.map { day < cal.startOfDay(for: $0) } ?? false
        let aboveMax = maxDate.map { day > cal.startOfDay(for: $0) } ?? false
        let disabled = belowMin || aboveMax
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
        AppDateFormat.monthYear(month)
    }
    private func step(_ delta: Int) {
        guard let m = cal.date(byAdding: .month, value: delta, to: month) else { return }
        // Don't navigate past the capped month (forward only — minDate keeps existing
        // behaviour where earlier months are reachable but their days are disabled).
        if let maxDate, delta > 0, cal.compare(m, to: maxDate, toGranularity: .month) == .orderedDescending { return }
        month = m
    }
    /// 42-slot grid (leading blanks + days of `month`).
    private var gridDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        // Shared layout math (#196); this picker uses nil for the blank cells.
        let layout = monthGridLayout(monthStart: first, calendar: cal)
        var out: [Date?] = Array(repeating: nil, count: layout.leadingBlanks)
        for d in 0..<layout.dayCount { out.append(cal.date(byAdding: .day, value: d, to: first)) }
        // Always a full 6-week (42-cell) grid so the calendar height is FIXED — the
        // weekday row, first week, and Go button don't shift as month row counts vary. [owner]
        while out.count < 42 { out.append(nil) }
        return out
    }
}


/// Card-less date value (app font, no capsule) that opens the calendar popup. [#13]
struct DSDateField: View {
    @Binding var date: Date
    var minDate: Date? = nil
    var fontSize: CGFloat = 17
    /// Override the displayed value format (defaults to "Jun 1, 2026").
    var format: (Date) -> String = { AppDateFormat.monthDayYear($0) }
    @State private var show = false

    private var label: String {
        format(date)
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
    private var is24: Bool { TimeFormatSetting.is24Hour }
    /// Displayed hour 1…12 (12h mode), preserving the current AM/PM. [#50]
    private var hour12: Binding<Int> {
        Binding(get: { let h = cal.component(.hour, from: date) % 12; return h == 0 ? 12 : h },
                set: { newH12 in
                    let isPM = cal.component(.hour, from: date) >= 12
                    let h = (newH12 % 12) + (isPM ? 12 : 0)
                    date = cal.date(bySettingHour: h, minute: cal.component(.minute, from: date), second: 0, of: date) ?? date
                })
    }
    private var isPM: Binding<Bool> {
        Binding(get: { cal.component(.hour, from: date) >= 12 },
                set: { pm in
                    let h = (cal.component(.hour, from: date) % 12) + (pm ? 12 : 0)
                    date = cal.date(bySettingHour: h, minute: cal.component(.minute, from: date), second: 0, of: date) ?? date
                })
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
                        if is24 {
                            Picker("", selection: hour) {
                                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).font(appFont(20)).tag($0) }
                            }.pickerStyle(.wheel).frame(maxWidth: .infinity)
                            DSText(":").dsTextStyle(.title2)
                            Picker("", selection: minute) {
                                ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).font(appFont(20)).tag($0) }
                            }.pickerStyle(.wheel).frame(maxWidth: .infinity)
                        } else {
                            // 12-hour: 1–12 : minute + AM/PM, matching the 12h label.
                            Picker("", selection: hour12) {
                                ForEach(1...12, id: \.self) { Text("\($0)").font(appFont(20)).tag($0) }
                            }.pickerStyle(.wheel).frame(maxWidth: .infinity)
                            DSText(":").dsTextStyle(.title2)
                            Picker("", selection: minute) {
                                ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).font(appFont(20)).tag($0) }
                            }.pickerStyle(.wheel).frame(maxWidth: .infinity)
                            Picker("", selection: isPM) {
                                Text("AM").font(appFont(20)).tag(false)
                                Text("PM").font(appFont(20)).tag(true)
                            }.pickerStyle(.wheel).frame(maxWidth: .infinity)
                        }
                    }
                    Spacer()
                }
                .padding(20)
            }
            .presentationDetents([.height(300)])
        }
    }
}
