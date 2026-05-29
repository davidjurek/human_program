import SwiftUI

// MARK: - RecurrenceRuleEditorView
// Reusable recurrence rule editor for recurring tasks (and future exercise routines).
// fourDaySplit and everyOtherDay are intentionally excluded — use ExerciseRecurrenceRuleEditorView for those.

struct RecurrenceRuleEditorView: View {
    @Binding var rule: RecurrenceRule

    @State private var showBounds = false

    // Local copies of optional/computed state
    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var hasEndDate = false
    @State private var hasOccurrenceLimit = false
    @State private var occurrenceLimit = 1

    // Available frequencies (exercise-specific ones excluded)
    private let frequencies: [(label: String, frequency: RecurrenceFrequency)] = [
        ("Every day",      .everyDay),
        ("Weekdays",       .weekdays),
        ("Weekends",       .weekends),
        ("Selected days",  .selectedWeekdays),
        ("Every N days",   .everyNDays),
        ("Every N weeks",  .everyNWeeks),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Frequency picker section
            frequencySection
            Divider().padding(.horizontal, 16)

            // Conditional controls
            conditionalSection

            // Optional bounds section
            boundsToggleRow
            if showBounds {
                boundsSection
            }
        }
        .onAppear { syncFromRule() }
    }

    // MARK: - Frequency section

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("REPEAT")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(frequencies, id: \.frequency) { item in
                        FrequencyCapsuleButton(
                            label: item.label,
                            isSelected: rule.frequency == item.frequency,
                            action: { selectFrequency(item.frequency) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Conditional controls

    @ViewBuilder
    private var conditionalSection: some View {
        switch rule.frequency {
        case .selectedWeekdays:
            dayToggleRow(label: "ON DAYS")
                .padding(.top, 14)
                .padding(.bottom, 4)
            Divider().padding(.horizontal, 16)

        case .everyNDays:
            VStack(alignment: .leading, spacing: 0) {
                intervalStepperRow(
                    label: "EVERY",
                    suffix: { n in n == 1 ? "day" : "days" },
                    range: 2...90
                )
                Divider().padding(.horizontal, 16)
                anchorDateRow
                Divider().padding(.horizontal, 16)
            }

        case .everyNWeeks:
            VStack(alignment: .leading, spacing: 0) {
                intervalStepperRow(
                    label: "EVERY",
                    suffix: { n in n == 1 ? "week" : "weeks" },
                    range: 2...26
                )
                Divider().padding(.horizontal, 16)
                dayToggleRow(label: "ON DAYS")
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                Divider().padding(.horizontal, 16)
                anchorDateRow
                Divider().padding(.horizontal, 16)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Day toggle row

    private func dayToggleRow(label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
                .padding(.horizontal, 16)
            HStack(spacing: 6) {
                // Weekdays 1-7 (Sun=1 ... Sat=7)
                ForEach(1...7, id: \.self) { wd in
                    DayToggleButton(
                        label: singleDayLetter(wd),
                        isSelected: rule.weekdays.contains(wd),
                        action: { toggleWeekday(wd) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Interval stepper row

    private func intervalStepperRow(label: String, suffix: (Int) -> String, range: ClosedRange<Int>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel(label)
                Text("\(rule.interval) \(suffix(rule.interval))")
                    .font(AppTypography.bodyText())
                    .foregroundStyle(AppColors.textPrimary)
            }
            Spacer()
            Stepper("", value: Binding(
                get: { rule.interval },
                set: { rule.interval = max(range.lowerBound, min($0, range.upperBound)) }
            ), in: range)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Anchor date row

    private var anchorDateRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("STARTING FROM")
            }
            Spacer()
            DatePicker(
                "",
                selection: Binding(
                    get: { rule.anchorDate ?? Calendar.current.startOfDay(for: Date()) },
                    set: { rule.anchorDate = $0 }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .accentColor(AppColors.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Bounds toggle row

    private var boundsToggleRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showBounds.toggle()
            }
        } label: {
            HStack {
                Text("Date bounds & limits")
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Image(systemName: showBounds ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bounds section

    @ViewBuilder
    private var boundsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Start date
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("START DATE")
                }
                Spacer()
                DatePicker(
                    "",
                    selection: $startDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .accentColor(AppColors.accent)
                .onChange(of: startDate) { _, new in
                    rule.startDate = new
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 16)

            // End date toggle + picker
            Toggle(isOn: $hasEndDate) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("END DATE")
                    if hasEndDate {
                        Text(endDate.formatted(date: .abbreviated, time: .omitted))
                            .font(AppTypography.bodySmallText())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: AppColors.accent))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .onChange(of: hasEndDate) { _, enabled in
                rule.endDate = enabled ? endDate : nil
            }

            if hasEndDate {
                DatePicker(
                    "End date",
                    selection: $endDate,
                    in: startDate...,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .accentColor(AppColors.accent)
                .padding(.horizontal, 16)
                .onChange(of: endDate) { _, new in
                    rule.endDate = new
                }
            }

            Divider().padding(.horizontal, 16)

            // Occurrence limit toggle + stepper
            Toggle(isOn: $hasOccurrenceLimit) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("OCCURRENCE LIMIT")
                    if hasOccurrenceLimit {
                        Text("\(occurrenceLimit) \(occurrenceLimit == 1 ? "time" : "times")")
                            .font(AppTypography.bodySmallText())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: AppColors.accent))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .onChange(of: hasOccurrenceLimit) { _, enabled in
                rule.occurrenceLimit = enabled ? occurrenceLimit : nil
            }

            if hasOccurrenceLimit {
                HStack {
                    Text("Max occurrences")
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Stepper("\(occurrenceLimit)", value: $occurrenceLimit, in: 1...365)
                        .font(AppTypography.bodySmallText())
                        .onChange(of: occurrenceLimit) { _, new in
                            rule.occurrenceLimit = new
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider().padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.sectionHeader())
            .foregroundStyle(AppColors.textTertiary)
            .kerning(0.4)
    }

    private func singleDayLetter(_ weekday: Int) -> String {
        // 1=S(Sun) 2=M 3=T 4=W 5=T 6=F 7=S(Sat)
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let idx = weekday - 1
        guard idx >= 0, idx < letters.count else { return "?" }
        return letters[idx]
    }

    private func selectFrequency(_ frequency: RecurrenceFrequency) {
        rule.frequency = frequency
        // Provide sensible defaults when switching
        switch frequency {
        case .selectedWeekdays:
            if rule.weekdays.isEmpty {
                // Default to Monday
                rule.weekdays = [2]
            }
        case .everyNDays:
            if rule.interval < 2 { rule.interval = 2 }
            if rule.anchorDate == nil { rule.anchorDate = Calendar.current.startOfDay(for: Date()) }
        case .everyNWeeks:
            if rule.interval < 2 { rule.interval = 2 }
            if rule.weekdays.isEmpty { rule.weekdays = [2] }
            if rule.anchorDate == nil { rule.anchorDate = Calendar.current.startOfDay(for: Date()) }
        default:
            break
        }
    }

    private func toggleWeekday(_ weekday: Int) {
        if rule.weekdays.contains(weekday) {
            // Must keep at least one selected
            if rule.weekdays.count > 1 {
                rule.weekdays.removeAll { $0 == weekday }
            }
        } else {
            rule.weekdays.append(weekday)
        }
    }

    private func syncFromRule() {
        startDate = rule.startDate ?? Calendar.current.startOfDay(for: Date())
        if let end = rule.endDate {
            hasEndDate = true
            endDate = end
        }
        if let limit = rule.occurrenceLimit {
            hasOccurrenceLimit = true
            occurrenceLimit = limit
        }
    }
}

// MARK: - FrequencyCapsuleButton

private struct FrequencyCapsuleButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppTypography.buttonLabel())
                .foregroundStyle(isSelected ? .white : AppColors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? AppColors.accent
                        : AppColors.surfaceSunken
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : AppColors.border,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - DayToggleButton

struct DayToggleButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : AppColors.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    isSelected
                        ? AppColors.accent
                        : AppColors.surfaceSunken
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.clear : AppColors.border,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
