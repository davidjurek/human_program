import SwiftUI
import SwiftData

// MARK: - SleepBlockEditorSheet

struct SleepBlockEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let template: ScheduleTemplate
    let initialBedtime: Int   // minutes from midnight
    let initialWake: Int      // minutes from midnight

    // Wheel picker state — stored as Date for DatePicker compatibility
    @State private var bedtimeDate: Date = Date()
    @State private var wakeDate: Date = Date()

    @State private var saveError: String? = nil

    // Reference date for building DatePicker times (date portion doesn't matter)
    private static let referenceDate: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Bedtime
                        bedtimeSection
                        divider()

                        // Wake time
                        wakeSection
                        divider()

                        // Duration display
                        durationRow
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Sleep Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveSleepBlock()
                    }
                    .font(AppTypography.bodyMediumText())
                    .foregroundStyle(AppColors.accent)
                }
            }
            .alert("Save Error", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveError ?? "An unknown error occurred.")
            }
        }
        .onAppear {
            bedtimeDate = minutesToDate(initialBedtime)
            wakeDate = minutesToDate(initialWake)
        }
    }

    // MARK: - Bedtime section

    private var bedtimeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("BEDTIME")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            DatePicker(
                "Bedtime",
                selection: $bedtimeDate,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .accentColor(AppColors.accent)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Wake section

    private var wakeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("WAKE TIME")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            DatePicker(
                "Wake time",
                selection: $wakeDate,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .accentColor(AppColors.accent)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Duration row

    private var durationRow: some View {
        HStack {
            sectionLabel("SLEEP DURATION")
            Spacer()
            Text(sleepDurationString)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: - Helpers

    private var sleepDurationString: String {
        let bedMinute = dateToMinutes(bedtimeDate)
        let wakeMinute = dateToMinutes(wakeDate)
        let duration: Int
        if wakeMinute > bedMinute {
            duration = wakeMinute - bedMinute
        } else {
            duration = (1440 - bedMinute) + wakeMinute
        }
        return formatDuration(duration) + " of sleep"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.sectionHeader())
            .foregroundStyle(AppColors.textTertiary)
            .kerning(0.4)
    }

    private func divider() -> some View {
        Divider()
            .padding(.leading, 16)
            .foregroundStyle(AppColors.separator)
    }

    /// Convert a minute-of-day value to a Date on the reference day.
    private func minutesToDate(_ minutes: Int) -> Date {
        let normalised = ((minutes % 1440) + 1440) % 1440
        let h = normalised / 60
        let m = normalised % 60
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Self.referenceDate)
        comps.hour = h
        comps.minute = m
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Self.referenceDate
    }

    /// Convert a Date back to minutes from midnight.
    private func dateToMinutes(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - Save

    private func saveSleepBlock() {
        let bedMinute = dateToMinutes(bedtimeDate)
        let wakeMinute = dateToMinutes(wakeDate)

        do {
            let repo = ScheduleRepository(context: context)
            try repo.updateSleepBlock(in: template, bedtimeMinute: bedMinute, wakeMinute: wakeMinute)
            try PageRefreshService.refresh(context: context)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
