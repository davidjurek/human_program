import SwiftUI
import SwiftData

// MARK: - ScheduleBlockEditorSheet

/// Sheet for adding a new block or editing an existing (non-Sleep) block.
struct ScheduleBlockEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let template: ScheduleTemplate
    /// nil = creating a new block; non-nil = editing an existing block
    let existingBlock: ScheduleBlock?
    /// The computed start minute for this block (previous block's end time).
    let startMinuteOfDay: Int

    @State private var title: String = ""
    @State private var selectedDurationIndex: Int = 3  // default: 1h (index 3)

    @State private var saveError: String? = nil
    @FocusState private var titleFocused: Bool

    private var isNew: Bool { existingBlock == nil }
    private var isTitleValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    // Preset duration options (minutes)
    private static let presetDurations: [(label: String, minutes: Int)] = [
        ("15 min",  15),
        ("30 min",  30),
        ("45 min",  45),
        ("1h",      60),
        ("1h 30m",  90),
        ("2h",      120),
        ("2h 30m",  150),
        ("3h",      180),
        ("4h",      240),
        ("5h",      300),
        ("6h",      360),
        ("7h",      420),
        ("8h",      480),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title
                        titleSection
                        divider()

                        // Start time (read-only)
                        startTimeRow
                        divider()

                        // Duration picker
                        durationSection
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(isNew ? "New Block" : "Edit Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .font(AppTypography.bodyMediumText())
                    .foregroundStyle(isTitleValid ? AppColors.accent : AppColors.textTertiary)
                    .disabled(!isTitleValid)
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
            if let block = existingBlock {
                title = block.title
                // Find the closest preset duration index
                let duration = block.durationMinutes
                if let idx = Self.presetDurations.firstIndex(where: { $0.minutes == duration }) {
                    selectedDurationIndex = idx
                } else {
                    // Default to 1h if no exact match
                    selectedDurationIndex = 3
                }
            }
            titleFocused = isNew
        }
    }

    // MARK: - Title section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("TITLE")
                .padding(.horizontal, 16)
                .padding(.top, 14)
            TextField("Block name", text: $title)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
                .focused($titleFocused)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .submitLabel(.done)
        }
    }

    // MARK: - Start time row (read-only)

    private var startTimeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("STARTS AT")
                Text(minutesToTimeString(startMinuteOfDay))
                    .font(AppTypography.bodyText())
                    .foregroundStyle(AppColors.textPrimary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Duration section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("DURATION")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Picker("Duration", selection: $selectedDurationIndex) {
                ForEach(Self.presetDurations.indices, id: \.self) { idx in
                    Text(Self.presetDurations[idx].label)
                        .tag(idx)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 180)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Computed end time preview
            let endMinute = (startMinuteOfDay + selectedDurationMinutes) % 1440
            HStack {
                sectionLabel("ENDS AT")
                Spacer()
                Text(minutesToTimeString(endMinute))
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Helpers

    private var selectedDurationMinutes: Int {
        guard selectedDurationIndex >= 0,
              selectedDurationIndex < Self.presetDurations.count else {
            return 60
        }
        return Self.presetDurations[selectedDurationIndex].minutes
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

    // MARK: - Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let duration = selectedDurationMinutes

        do {
            let repo = ScheduleRepository(context: context)
            if let block = existingBlock {
                try repo.updateBlock(
                    block.id,
                    title: trimmedTitle,
                    durationMinutes: duration,
                    in: template
                )
            } else {
                try repo.addBlock(
                    title: trimmedTitle,
                    durationMinutes: duration,
                    to: template
                )
            }
            try PageRefreshService.refresh(context: context)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
