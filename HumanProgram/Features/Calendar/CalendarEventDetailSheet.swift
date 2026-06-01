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
            ZStack {
                Text("Event").font(appFont(17, bold: true)).foregroundStyle(Color.primary)
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Done").font(appFont(18)).foregroundStyle(Color.accentColor)
                            .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .a11yTapBorder(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
                    Text(displayTitle)
                        .font(appFont(24, bold: true))
                        .foregroundStyle(Color.primary)

                    Text(event.calendar.title)
                        .font(appFont(14))
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
                    .font(.system(size: 18))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 20)

                if event.isAllDay {
                    Text("All day · \(event.startDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())")
                        .font(appFont(17))
                        .foregroundStyle(Color.primary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.startDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                            .font(appFont(17))
                            .foregroundStyle(Color.primary)
                        Text("\(event.startDate, format: .dateTime.hour().minute()) – \(event.endDate, format: .dateTime.hour().minute())")
                            .font(appFont(14))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }

            // Notes (original or override)
            let notes = localState?.notesOverride ?? event.notes
            if let notes = notes, !notes.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 20)
                    Text(notes)
                        .font(appFont(17))
                        .foregroundStyle(Color.primary)
                }
            }

            // Location
            if let location = event.location, !location.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "location")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 20)
                    Text(location)
                        .font(appFont(17))
                        .foregroundStyle(Color.primary)
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
            Text("OVERRIDES")
                .font(appFont(13, bold: true))
                .foregroundStyle(Color.secondary)
                .kerning(0.5)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

            VStack(spacing: 0) {

                // Display title override — card-less plain field. [#33/#34]
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display title")
                        .font(appFont(15))
                        .foregroundStyle(Color.secondary)

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
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.secondary)
                                    .contentShape(Circle())
                            }
                            .a11yTapBorder(Circle())
                        }
                    }

                    if !titleOverride.isEmpty {
                        Button("Save title") { saveTitleOverride() }
                            .font(appFont(17))
                            .foregroundStyle(Color.accentColor)
                            .a11yTapBorder(cornerRadius: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

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
            }

            if let error = errorMessage {
                Text(error)
                    .font(appFont(14))
                    .foregroundStyle(Color.red)
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
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(appFont(17))
                    .foregroundStyle(Color.primary)
                Text(caption)
                    .font(appFont(14))
                    .foregroundStyle(Color.secondary)
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
