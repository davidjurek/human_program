import SwiftUI
import EventKit
import SwiftData

/// Sheet showing event detail with local override controls.
/// Does NOT modify the underlying EKEvent — all local state goes through CalendarLocalStateRepository.
struct CalendarEventDetailSheet: View {

    @Environment(\.dismiss) private var dismiss

    let event: EKEvent
    let date: Date
    let context: ModelContext

    // Repository is @MainActor, so it's safe to create on the main thread
    private var stateRepo: CalendarLocalStateRepository {
        CalendarLocalStateRepository(context: context)
    }

    @State private var localState: CalendarEventLocalState? = nil
    @State private var titleOverride: String = ""
    @State private var isHidden: Bool = false
    @State private var isComplete: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isEditingTitle: Bool = false
    @FocusState private var titleFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Calendar color bar + event header
                    eventHeader
                    Divider()

                    // Event metadata
                    eventMetadata
                    Divider()

                    // Local override section
                    localOverrideSection
                }
            }
            .background(AppColors.background)
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.accent)
                }
            }
            .task { await loadLocalState() }
        }
    }

    // MARK: - Header

    private var eventHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Calendar color indicator
                Rectangle()
                    .fill(Color(cgColor: event.calendar.cgColor))
                    .frame(width: 4)
                    .clipShape(Capsule())
                    .frame(height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    // Title: use override if set, otherwise event title
                    let displayTitle = titleOverride.isEmpty ? (event.title ?? "(No title)") : titleOverride
                    Text(displayTitle)
                        .font(AppTypography.pageTitle())
                        .foregroundStyle(AppColors.textPrimary)

                    Text(event.calendar.title)
                        .font(AppTypography.caption())
                        .foregroundStyle(Color(cgColor: event.calendar.cgColor))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Metadata

    private var eventMetadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date / time
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 20)

                if event.isAllDay {
                    Text("All day · \(event.startDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())")
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textPrimary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.startDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                            .font(AppTypography.bodySmallText())
                            .foregroundStyle(AppColors.textPrimary)
                        Text("\(event.startDate, format: .dateTime.hour().minute()) – \(event.endDate, format: .dateTime.hour().minute())")
                            .font(AppTypography.timeLabel())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            // Notes (original or override)
            let notes = localState?.notesOverride ?? event.notes
            if let notes = notes, !notes.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 20)
                    Text(notes)
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textPrimary)
                }
            }

            // Location
            if let location = event.location, !location.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "location")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 20)
                    Text(location)
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: - Local override section

    private var localOverrideSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text("TODAY OVERRIDES")
                    .font(AppTypography.sectionHeader())
                    .foregroundStyle(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Text("Affects Today only")
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            VStack(spacing: 0) {

                // Override title row
                VStack(alignment: .leading, spacing: 6) {
                    Text("Display title")
                        .font(AppTypography.caption())
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    HStack(spacing: 8) {
                        TextField("Same as event title", text: $titleOverride)
                            .font(AppTypography.taskTitle())
                            .focused($titleFieldFocused)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.surfaceSunken)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .submitLabel(.done)
                            .onSubmit { saveTitleOverride() }

                        if !titleOverride.isEmpty {
                            Button {
                                titleOverride = ""
                                saveTitleOverride()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    if !titleOverride.isEmpty {
                        Button("Save title") { saveTitleOverride() }
                            .font(AppTypography.buttonLabel())
                            .foregroundStyle(AppColors.accent)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }
                }
                .padding(.bottom, 12)

                Divider().padding(.leading, 16)

                // Hide from Today
                OverrideToggleRow(
                    icon: "eye.slash",
                    label: "Hide from Today",
                    caption: "This event won't appear in your task list",
                    isOn: $isHidden
                )
                .onChange(of: isHidden) { _, newValue in
                    toggleHidden(newValue)
                }

                Divider().padding(.leading, 16)

                // Mark complete in Today
                OverrideToggleRow(
                    icon: "checkmark.circle",
                    label: "Mark complete in Today",
                    caption: "Counts toward day completion",
                    isOn: $isComplete
                )
                .onChange(of: isComplete) { _, newValue in
                    toggleComplete(newValue)
                }
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            if let error = errorMessage {
                Text(error)
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.accentRed)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            Spacer(minLength: 40)
        }
    }

    // MARK: - Actions

    private func loadLocalState() async {
        do {
            let state = try stateRepo.getOrCreate(eventId: event.eventIdentifier, date: date)
            localState = state
            titleOverride = state.titleOverride ?? ""
            isHidden = state.hidden
            isComplete = state.completed
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTitleOverride() {
        titleFieldFocused = false
        do {
            let trimmed = titleOverride.trimmingCharacters(in: .whitespaces)
            let override = trimmed.isEmpty ? nil : trimmed
            try stateRepo.setTitleOverride(override, eventId: event.eventIdentifier, date: date)
            titleOverride = override ?? ""
            localState?.titleOverride = override
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleHidden(_ hidden: Bool) {
        do {
            try stateRepo.setHidden(hidden, eventId: event.eventIdentifier, date: date)
            localState?.hidden = hidden
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleComplete(_ complete: Bool) {
        do {
            try stateRepo.toggleCompletion(eventId: event.eventIdentifier, date: date)
            localState?.completed = complete
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Reusable toggle row

private struct OverrideToggleRow: View {
    let icon: String
    let label: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)
                Text(caption)
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColors.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
