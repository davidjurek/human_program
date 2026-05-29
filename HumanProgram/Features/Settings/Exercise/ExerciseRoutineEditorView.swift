import SwiftUI
import SwiftData

struct ExerciseRoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let routine: ExerciseRoutine

    @State private var isEditing: Bool = false
    @State private var routineName: String = ""
    @State private var showAddForm: Bool = false
    @State private var newItemText: String = ""
    @State private var newItemSets: Int = 0
    @State private var newItemReps: Int = 0
    @State private var newItemHasSets: Bool = false
    @State private var newItemHasReps: Bool = false
    @FocusState private var addFieldFocused: Bool

    private static let fullWeekdayName: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
        5: "Thursday", 6: "Friday", 7: "Saturday"
    ]

    private var weekdayTitle: String {
        let weekday = routine.recurrenceRule.weekdays.first ?? 0
        return Self.fullWeekdayName[weekday] ?? "Exercise"
    }

    private var sortedItems: [ExerciseRoutineItem] {
        routine.items.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header: weekday title + editable routine name
                        headerSection

                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        // Items
                        itemsSection

                        // Add form (always visible, or only in edit — shown at bottom)
                        if isEditing {
                            addFormSection
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle(weekdayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        if isEditing { commitNameChange() }
                        dismiss()
                    }
                    .foregroundStyle(AppColors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing {
                            commitNameChange()
                        }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEditing.toggle()
                        }
                    }
                    .foregroundStyle(AppColors.accent)
                }
            }
        }
        .onAppear {
            routineName = routine.name
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(weekdayTitle.uppercased())
                .font(AppTypography.sectionHeader())
                .foregroundStyle(AppColors.textTertiary)
                .kerning(0.5)
                .padding(.top, 20)

            if isEditing {
                TextField("Routine name (optional)", text: $routineName)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(AppColors.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                let displayName = routineName.trimmingCharacters(in: .whitespaces)
                Text(displayName.isEmpty ? "Rest day" : displayName)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(displayName.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Items

    @ViewBuilder
    private var itemsSection: some View {
        if sortedItems.isEmpty {
            Text("No exercises added yet")
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sortedItems) { item in
                    itemRow(item)
                    Divider()
                        .padding(.leading, isEditing ? 56 : 16)
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: ExerciseRoutineItem) -> some View {
        HStack(spacing: 12) {
            if isEditing {
                // Delete button
                Button {
                    deleteItem(item)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.destructive)
                }
                .padding(.leading, 16)
            } else {
                // Bullet
                Text("•")
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.leading, 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)

                if let sets = item.sets, let reps = item.reps {
                    Text("\(sets)×\(reps)")
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.accentOrange)
                } else if let sets = item.sets {
                    Text("\(sets) sets")
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.accentOrange)
                } else if let reps = item.reps {
                    Text("\(reps) reps")
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.accentOrange)
                }
            }

            Spacer()

            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Add Form

    private var addFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Text("ADD EXERCISE")
                .font(AppTypography.sectionHeader())
                .foregroundStyle(AppColors.textTertiary)
                .kerning(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 4)

            // Text field
            TextField("Exercise name", text: $newItemText)
                .font(AppTypography.taskTitle())
                .foregroundStyle(AppColors.textPrimary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(AppColors.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused($addFieldFocused)
                .padding(.horizontal, 16)

            // Optional sets/reps
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Toggle("Sets", isOn: $newItemHasSets)
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textPrimary)
                        .tint(AppColors.accent)
                        .frame(maxWidth: 120, alignment: .leading)

                    if newItemHasSets {
                        Stepper(
                            "\(newItemSets)",
                            value: $newItemSets,
                            in: 1...99
                        )
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Toggle("Reps", isOn: $newItemHasReps)
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textPrimary)
                        .tint(AppColors.accent)
                        .frame(maxWidth: 120, alignment: .leading)

                    if newItemHasReps {
                        Stepper(
                            "\(newItemReps)",
                            value: $newItemReps,
                            in: 1...999
                        )
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Add button
            Button {
                submitNewItem()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                    Text("Add")
                        .font(AppTypography.buttonLabel())
                }
                .foregroundStyle(newItemText.trimmingCharacters(in: .whitespaces).isEmpty
                    ? AppColors.textTertiary : AppColors.accent)
            }
            .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Actions

    private func commitNameChange() {
        let repo = ExerciseRepository(context: context)
        let trimmed = routineName.trimmingCharacters(in: .whitespaces)
        guard trimmed != routine.name else { return }
        try? repo.update(routine, name: trimmed)
        try? PageRefreshService.refresh(context: context)
    }

    private func deleteItem(_ item: ExerciseRoutineItem) {
        let repo = ExerciseRepository(context: context)
        try? repo.deleteItem(item, from: routine)
        try? PageRefreshService.refresh(context: context)
    }

    private func submitNewItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let repo = ExerciseRepository(context: context)
        let sets = newItemHasSets ? newItemSets : nil
        let reps = newItemHasReps ? newItemReps : nil
        try? repo.addItem(to: routine, text: trimmed, sets: sets, reps: reps)
        try? PageRefreshService.refresh(context: context)
        // Reset form
        newItemText = ""
        newItemSets = 0
        newItemReps = 0
        newItemHasSets = false
        newItemHasReps = false
        addFieldFocused = true
    }
}
