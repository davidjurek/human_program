import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportExportView: View {
    @Environment(\.modelContext) private var context
    @Query private var backlogItems: [BacklogItem]
    @Query private var dailyPages: [DailyPage]

    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false
    @State private var showFilePicker = false
    @State private var showImportPreview = false
    @State private var importBundle: HprgmBundle? = nil
    @State private var showHistorySheet = false
    @State private var errorMessage: String? = nil
    @State private var isExporting = false

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // MARK: Export Section
                    sectionHeader("Export")

                    VStack(spacing: 1) {
                        actionRow(
                            icon: "square.and.arrow.up",
                            title: "Export Full Backup (.hprgm)",
                            subtitle: "All tasks, schedules, backlog, and settings",
                            isDestructive: false
                        ) {
                            exportHprgm()
                        }

                        Divider()
                            .padding(.leading, 52)

                        actionRow(
                            icon: "tablecells",
                            title: "Export Backlog as CSV",
                            subtitle: "\(backlogItems.count) item\(backlogItems.count == 1 ? "" : "s")",
                            isDestructive: false
                        ) {
                            exportBacklogCSV()
                        }

                        Divider()
                            .padding(.leading, 52)

                        actionRow(
                            icon: "clock.arrow.circlepath",
                            title: "Export Task History as CSV",
                            subtitle: "Choose a date range",
                            isDestructive: false
                        ) {
                            showHistorySheet = true
                        }
                    }
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)

                    // MARK: Import Section
                    sectionHeader("Import")

                    VStack(spacing: 0) {
                        actionRow(
                            icon: "square.and.arrow.down",
                            title: "Import .hprgm Backup",
                            subtitle: "Replaces current planner data",
                            isDestructive: true
                        ) {
                            showFilePicker = true
                        }
                    }
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)

                    // MARK: Import Warning Note
                    Text("Importing a backup replaces your recurring tasks, schedules, backlog, and exercise routines. Past completed days are always preserved.")
                        .font(AppTypography.caption())
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle("Import / Export")
        .navigationBarTitleDisplayMode(.inline)

        // MARK: Share Sheet
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
                    .ignoresSafeArea()
            }
        }

        // MARK: File Picker for Import
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.hprgm],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result)
        }

        // MARK: Import Preview Sheet
        .sheet(isPresented: $showImportPreview) {
            if let bundle = importBundle {
                HprgmImportPreviewView(bundle: bundle) {
                    showImportPreview = false
                }
            }
        }

        // MARK: Task History Date Range Sheet
        .sheet(isPresented: $showHistorySheet) {
            TaskHistoryExportSheet(pages: dailyPages)
        }

        // MARK: Error Alert
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

    // MARK: - Section Header

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

    // MARK: - Action Row

    @ViewBuilder
    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isDestructive ? AppColors.accentRed : AppColors.accent)
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyText())
                        .foregroundStyle(isDestructive ? AppColors.accentRed : AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.caption())
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export Actions

    private func exportHprgm() {
        do {
            let service = HprgmExportService()
            let url = try service.export(context: context)
            exportURL = url
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportBacklogCSV() {
        let exporter = BacklogCSVExporter()
        let csv = exporter.export(items: backlogItems)
        let filename = exporter.suggestedFilename()

        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Import Actions

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let service = HprgmImportService()
                let bundle = try service.preview(fileURL: url)
                importBundle = bundle
                showImportPreview = true
            } catch {
                errorMessage = "Could not read the file: \(error.localizedDescription)"
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - UTType extension for .hprgm

extension UTType {
    static let hprgm = UTType(exportedAs: "com.humanprogram.hprgm")
}
