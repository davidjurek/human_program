import SwiftUI
import SwiftData

struct HprgmImportPreviewView: View {
    let bundle: HprgmBundle
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var onImported: () -> Void

    @State private var isImporting = false
    @State private var errorMessage: String? = nil

    private static let exportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {

                        // MARK: Warning Banner
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(AppColors.warning)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("This replaces current planner data.")
                                    .font(AppTypography.bodyMediumText())
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("Past locked pages are always kept. Everything else — recurring tasks, schedule, backlog, exercise routines, and reminders — will be replaced.")
                                    .font(AppTypography.bodySmallText())
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .padding(16)
                        .background(AppColors.warningTint)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 24)

                        // MARK: File Info
                        sectionHeader("File Details")

                        VStack(spacing: 1) {
                            infoRow(label: "Exported", value: Self.exportDateFormatter.string(from: bundle.exportedAt))
                            Divider().padding(.leading, 16)
                            infoRow(label: "App version", value: bundle.appVersion)
                            Divider().padding(.leading, 16)
                            infoRow(label: "Format version", value: String(bundle.formatVersion))
                        }
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                        // MARK: Contents Summary
                        sectionHeader("What Will Be Imported")

                        VStack(spacing: 1) {
                            countRow(
                                icon: "list.bullet",
                                label: "Recurring Tasks",
                                count: bundle.recurringTaskTemplates.count
                            )
                            Divider().padding(.leading, 52)
                            countRow(
                                icon: "tray.full",
                                label: "Backlog Items",
                                count: bundle.backlogItems.count
                            )
                            Divider().padding(.leading, 52)
                            countRow(
                                icon: "folder",
                                label: "Projects",
                                count: bundle.projectBuckets.count
                            )
                            Divider().padding(.leading, 52)
                            countRow(
                                icon: "clock",
                                label: "Schedule Templates",
                                count: bundle.scheduleTemplates.count
                            )
                            Divider().padding(.leading, 52)
                            countRow(
                                icon: "figure.run",
                                label: "Exercise Routines",
                                count: bundle.exerciseRoutines.count
                            )
                            Divider().padding(.leading, 52)
                            countRow(
                                icon: "bell",
                                label: "Reminders",
                                count: bundle.notifications.count
                            )
                            Divider().padding(.leading, 52)
                            countRow(
                                icon: "calendar",
                                label: "Daily Pages (non-locked)",
                                count: bundle.dailyPages.filter { !$0.isPastLocked }.count
                            )
                        }
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)

                        // MARK: Action Buttons
                        VStack(spacing: 12) {
                            Button {
                                performImport()
                            } label: {
                                HStack {
                                    if isImporting {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(.white)
                                            .padding(.trailing, 4)
                                    }
                                    Text(isImporting ? "Importing…" : "Import and Replace")
                                        .font(AppTypography.bodyMediumText())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.accentRed)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isImporting)

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
                            .disabled(isImporting)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Import Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Import Failed", isPresented: Binding(
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
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func countRow(icon: String, label: String, count: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.accent)
                .frame(width: 24, alignment: .center)

            Text(label)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Text("\(count)")
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Import Action

    private func performImport() {
        isImporting = true
        Task { @MainActor in
            do {
                let service = HprgmImportService()
                try service.importData(bundle, context: context)
                try PageRefreshService.refresh(context: context)
                isImporting = false
                onImported()
                dismiss()
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
