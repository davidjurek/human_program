import SwiftUI

// MARK: - ExerciseRecurrenceRuleEditorView
// Variant of RecurrenceRuleEditorView tailored for exercise routines.
// Frequencies: Every day | Selected days | Every other day | Every N days | 4-day split
// (everyNWeeks is excluded for exercise)

struct ExerciseRecurrenceRuleEditorView: View {
    @Binding var rule: RecurrenceRule

    @State private var showBounds = false
    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var hasEndDate = false
    @State private var hasOccurrenceLimit = false
    @State private var occurrenceLimit = 1

    private let frequencies: [(label: String, frequency: RecurrenceFrequency)] = [
        ("Every day",       .everyDay),
        ("Selected days",   .selectedWeekdays),
        ("Every other day", .everyOtherDay),
        ("Every N days",    .everyNDays),
        ("4-day split",     .fourDaySplit),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            frequencySection
            Divider().padding(.horizontal, 16)

            conditionalSection

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
                        FrequencyCapsuleButtonEx(
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

        case .everyOtherDay:
            VStack(alignment: .leading, spacing: 0) {
                anchorDateRow
                Divider().padding(.horizontal, 16)
            }

        case .fourDaySplit:
            fourDaySplitInfo
            Divider().padding(.horizontal, 16)

        default:
            EmptyView()
        }
    }

    // MARK: - 4-day split info

    private var fourDaySplitInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CYCLE")
                .padding(.horizontal, 16)

            // Cycle diagram
            HStack(spacing: 0) {
                cycleLabel("Workout A", color: AppColors.accent)
                cycleSeparator
                cycleLabel("Workout B", color: AppColors.accentGreen)
                cycleSeparator
                cycleLabel("Workout C", color: AppColors.accentOrange)
                cycleSeparator
                cycleLabel("Rest", color: AppColors.textTertiary)
            }
            .padding(.horizontal, 16)

            Text("The cycle repeats automatically. Set a start date below to align the first workout.")
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 16)

            // Cycle anchor date
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("CYCLE START (WORKOUT A)")
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
            .padding(.bottom, 12)
        }
        .padding(.top, 14)
    }

    private func cycleLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var cycleSeparator: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, 3)
    }

    // MARK: - Day toggle row

    private func dayToggleRow(label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
                .padding(.horizontal, 16)
            HStack(spacing: 6) {
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
            sectionLabel("STARTING FROM")
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
            HStack {
                sectionLabel("START DATE")
                Spacer()
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .accentColor(AppColors.accent)
                    .onChange(of: startDate) { _, new in rule.startDate = new }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 16)

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
                DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .accentColor(AppColors.accent)
                    .padding(.horizontal, 16)
                    .onChange(of: endDate) { _, new in rule.endDate = new }
            }

            Divider().padding(.horizontal, 16)

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
                        .onChange(of: occurrenceLimit) { _, new in rule.occurrenceLimit = new }
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
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let idx = weekday - 1
        guard idx >= 0, idx < letters.count else { return "?" }
        return letters[idx]
    }

    private func selectFrequency(_ frequency: RecurrenceFrequency) {
        rule.frequency = frequency
        switch frequency {
        case .selectedWeekdays:
            if rule.weekdays.isEmpty { rule.weekdays = [2] }
        case .everyNDays:
            if rule.interval < 2 { rule.interval = 2 }
            if rule.anchorDate == nil { rule.anchorDate = Calendar.current.startOfDay(for: Date()) }
        case .everyOtherDay, .fourDaySplit:
            if rule.anchorDate == nil { rule.anchorDate = Calendar.current.startOfDay(for: Date()) }
        default:
            break
        }
    }

    private func toggleWeekday(_ weekday: Int) {
        if rule.weekdays.contains(weekday) {
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

// MARK: - FrequencyCapsuleButtonEx
// Private copy to avoid naming collision with the one in RecurrenceRuleEditorView.

private struct FrequencyCapsuleButtonEx: View {
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
