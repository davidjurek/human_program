import SwiftUI
import SwiftData

struct TaskHistoryExportSheet: View {
    let pages: [DailyPage]

    @Environment(\.dismiss) private var dismiss

    // MARK: - Preset options

    private enum Preset: String, CaseIterable, Identifiable {
        case last7   = "Last 7 days"
        case last30  = "Last 30 days"
        case last60  = "Last 60 days"
        case last90  = "Last 90 days"
        case custom  = "Custom"

        var id: String { rawValue }
    }

    @State private var selectedPreset: Preset = .last30
    @State private var customFrom: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customTo: Date = Date()
    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false
    @State private var errorMessage: String? = nil

    // MARK: - Computed dates

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var effectiveFrom: Date {
        switch selectedPreset {
        case .last7:  return Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        case .last30: return Calendar.current.date(byAdding: .day, value: -29, to: today) ?? today
        case .last60: return Calendar.current.date(byAdding: .day, value: -59, to: today) ?? today
        case .last90: return Calendar.current.date(byAdding: .day, value: -89, to: today) ?? today
        case .custom: return Calendar.current.startOfDay(for: customFrom)
        }
    }

    private var effectiveTo: Date {
        switch selectedPreset {
        case .last7, .last30, .last60, .last90: return today
        case .custom: return Calendar.current.startOfDay(for: max(customTo, customFrom))
        }
    }

    private var selectedDaysCount: Int {
        let from = Calendar.current.startOfDay(for: effectiveFrom)
        let to   = Calendar.current.startOfDay(for: effectiveTo)
        let components = Calendar.current.dateComponents([.day], from: from, to: to)
        return (components.day ?? 0) + 1
    }

    private var filteredPages: [DailyPage] {
        let from = Calendar.current.startOfDay(for: effectiveFrom)
        let to   = Calendar.current.startOfDay(for: effectiveTo)
        return pages.filter { page in
            let day = Calendar.current.startOfDay(for: page.date)
            return day >= from && day <= to
        }
    }

    private var totalTaskCount: Int {
        filteredPages.reduce(0) { $0 + $1.tasks.count }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {

                        // MARK: Preset Picker
                        sectionHeader("Date Range")

                        VStack(spacing: 1) {
                            ForEach(Preset.allCases) { preset in
                                presetRow(preset)
                                if preset != Preset.allCases.last {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                        // MARK: Custom Date Pickers (visible only when Custom is selected)
                        if selectedPreset == .custom {
                            sectionHeader("Custom Range")

                            VStack(spacing: 1) {
                                DatePicker(
                                    "From",
                                    selection: $customFrom,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .font(AppTypography.bodyText())
                                .foregroundStyle(AppColors.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .tint(AppColors.accent)

                                Divider().padding(.leading, 16)

                                DatePicker(
                                    "To",
                                    selection: Binding(
                                        get: { max(customTo, customFrom) },
                                        set: { customTo = $0 }
                                    ),
                                    in: customFrom...,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .font(AppTypography.bodyText())
                                .foregroundStyle(AppColors.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .tint(AppColors.accent)
                            }
                            .background(AppColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }

                        // MARK: Summary Line
                        HStack(spacing: 0) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.textTertiary)
                                .padding(.trailing, 6)

                            Text("\(selectedDaysCount) day\(selectedDaysCount == 1 ? "" : "s") selected")
                                .font(AppTypography.caption())
                                .foregroundStyle(AppColors.textTertiary)

                            Text(" · ")
                                .font(AppTypography.caption())
                                .foregroundStyle(AppColors.textTertiary)

                            Text("\(totalTaskCount) task row\(totalTaskCount == 1 ? "" : "s")")
                                .font(AppTypography.caption())
                                .foregroundStyle(AppColors.textTertiary)

                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)

                        // MARK: Export Button
                        Button {
                            exportCSV()
                        } label: {
                            Text("Export CSV")
                                .font(AppTypography.bodyMediumText())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(totalTaskCount > 0 ? AppColors.accent : AppColors.textTertiary)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(totalTaskCount == 0)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(AppTypography.bodyMediumText())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.surface)
                                .foregroundStyle(AppColors.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Task History")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
                    .ignoresSafeArea()
            }
        }
        .alert("Export Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            if let msg = errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(AppTypography.sectionHeader())
                .foregroundStyle(AppColors.sectionHeader)
                .padding(.leading, 24)
                .padding(.bottom, 6)
            Spacer()
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: Preset) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedPreset = preset
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: presetIcon(preset))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 24, alignment: .center)

                Text(preset.rawValue)
                    .font(AppTypography.bodyText())
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if selectedPreset == preset {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func presetIcon(_ preset: Preset) -> String {
        switch preset {
        case .last7:  return "7.square"
        case .last30: return "30.square"
        case .last60: return "60.square"
        case .last90: return "90.square"
        case .custom: return "calendar.badge.plus"
        }
    }

    // MARK: - Export

    private func exportCSV() {
        let exporter = TaskHistoryCSVExporter()
        let csv = exporter.export(pages: filteredPages)
        let filename = exporter.suggestedFilename(from: effectiveFrom, to: effectiveTo)

        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
