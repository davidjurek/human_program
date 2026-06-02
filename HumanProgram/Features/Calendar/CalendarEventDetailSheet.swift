import SwiftUI
import EventKit
import SwiftData
import DSKit

/// Sheet showing event detail with local override controls.
/// Does NOT modify the underlying EKEvent — all local state goes through CalendarLocalStateRepository.
struct CalendarEventDetailSheet: View {

    @Environment(\.dismiss) private var dismiss

    let event: EKEvent
    let date: Date
    let context: ModelContext
    /// Called when the user taps "Edit" — the presenter opens the event editor.
    var onEdit: () -> Void = {}

    // Repository is @MainActor, so it's safe to create on the main thread
    private var stateRepo: CalendarLocalStateRepository {
        CalendarLocalStateRepository(context: context)
    }

    @State private var localState: CalendarEventLocalState? = nil
    @State private var titleOverride: String = ""
    @State private var isHidden: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isEditingTitle: Bool = false
    @FocusState private var titleFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        // Custom top bar instead of a NavigationStack toolbar — the toolbar item
        // forces the iOS-26 glass capsule even with .buttonStyle(.plain), so we
        // render a plain "Done" ourselves. [#36]
        ZStack {
            SettingsBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    eventHeader
                    Divider()
                    eventMetadata
                    Divider()
                    localOverrideSection
                }
            }
        }
        .safeAreaInset(edge: .top) {
            // No centered "Event" title (titles are hidden app-wide). Edit on the
            // left, Done on the right; pushed down from the top edge.
            HStack {
                Button { onEdit() } label: {
                    DSText("Edit").dsTextStyle(.body, Color.accentColor)
                        .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .a11yTapBorder(Rectangle())
                Spacer()
                Button { dismiss() } label: {
                    DSText("Done").dsTextStyle(.body, Color.accentColor)
                        .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .a11yTapBorder(Rectangle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .topBarFrost()
        }
        .task { await loadLocalState() }
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
                    DSText(displayTitle)
                        .dsTextStyle(.title2)

                    DSText(event.calendar.title)
                        .dsTextStyle(.subheadline, Color(cgColor: event.calendar.cgColor))
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
                DSImageView(systemName: "clock", size: 18, tint: .color(.secondary))
                    .frame(width: 20)

                if event.isAllDay {
                    DSText("All day · \(event.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))")
                        .dsTextStyle(.body)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        DSText(event.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                            .dsTextStyle(.body)
                        DSText("\(clockString(date: event.startDate)) – \(clockString(date: event.endDate))")
                            .dsTextStyle(.subheadline)
                    }
                }
            }

            // Notes (original or override)
            let notes = localState?.notesOverride ?? event.notes
            if let notes = notes, !notes.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    DSImageView(systemName: "note.text", size: 18, tint: .color(.secondary))
                        .frame(width: 20)
                    DSText(notes)
                        .dsTextStyle(.body)
                }
            }

            // Location
            if let location = event.location, !location.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    DSImageView(systemName: "location", size: 18, tint: .color(.secondary))
                        .frame(width: 20)
                    DSText(location)
                        .dsTextStyle(.body)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: - Local override section

    private var localOverrideSection: some View {
        // Card-less section (matches the Add-event editor look). [#31/#32/#34/#35]
        VStack(alignment: .leading, spacing: 0) {
            // Section header — "OVERRIDES" only (no "Affects Today only").
            DSText("OVERRIDES")
                .dsTextStyle(.caption1)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

            VStack(spacing: 0) {

                // Display title override — card-less plain field. [#33/#34]
                VStack(alignment: .leading, spacing: 8) {
                    DSText("Display title")
                        .dsTextStyle(.subheadline)

                    HStack(spacing: 8) {
                        TextField("Same as event title", text: $titleOverride)
                            .font(appFont(20))
                            .focused($titleFieldFocused)
                            .submitLabel(.done)
                            .onSubmit { saveTitleOverride() }

                        if !titleOverride.isEmpty {
                            Button {
                                titleOverride = ""
                                saveTitleOverride()
                            } label: {
                                DSImageView(systemName: "xmark.circle.fill", size: .font(.body),
                                            tint: .color(.secondary))
                                    .contentShape(Circle())
                            }
                            .a11yTapBorder(Circle())
                        }
                    }

                    if !titleOverride.isEmpty {
                        Button { saveTitleOverride() } label: {
                            DSText("Save title").dsTextStyle(.body, Color.accentColor)
                        }
                        .a11yTapBorder(cornerRadius: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

                // Hide from Today
                OverrideToggleRow(
                    icon: "eye.slash",
                    label: "Hide from Today",
                    isOn: $isHidden
                )
                .onChange(of: isHidden) { _, newValue in
                    toggleHidden(newValue)
                }
            }

            if let error = errorMessage {
                DSText(error)
                    .dsTextStyle(.subheadline, Color.red)
                    .padding(.horizontal, 20)
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

}

// MARK: - Reusable toggle row

private struct OverrideToggleRow: View {
    let icon: String
    let label: String
    var caption: String? = nil   // no-filler rule: usually just icon + label + toggle [#122]
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            DSImageView(systemName: icon, size: 18, tint: .color(.secondary))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                DSText(label)
                    .dsTextStyle(.body)
                if let caption, !caption.isEmpty {
                    DSText(caption)
                        .dsTextStyle(.subheadline)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.accentColor)
                .a11yTapBorder(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
