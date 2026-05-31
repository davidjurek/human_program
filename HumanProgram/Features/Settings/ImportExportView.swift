import SwiftUI
import SwiftData
import DSKit
import UniformTypeIdentifiers

// Import and Export, split into two DSKit pages. Import offers three options
// (text backlog, CSV backlog, restore .hprgm); Export offers one (.hprgm full
// backup). Every step is a real pushed page.

// MARK: - Import flow coordinator

/// Drives the text/CSV import push stack from one place so "Done" on the final
/// summary page can pop ALL the way back to the Import menu in one tap.
@Observable final class ImportFlow {
    enum Mode { case text, csv }
    var mode: Mode? = nil
    var showSelection = false
    var showSummary = false
    var rows: [ParsedBacklogRow] = []
    var skipped = 0
    var summary: ImportSummary? = nil

    func openSelection(rows: [ParsedBacklogRow], skipped: Int) {
        self.rows = rows; self.skipped = skipped; showSelection = true
    }
    func openSummary(_ summary: ImportSummary) {
        self.summary = summary; showSummary = true
    }
    /// Pops summary + selection + importer in one shot, back to the menu.
    func backToMenu() { showSummary = false; showSelection = false; mode = nil }
}

// MARK: - Import menu

struct ImportView: View {
    @State private var flow = ImportFlow()

    var body: some View {
        @Bindable var flow = flow
        SettingsScreen {
            SettingsGroup(title: "Backlog") {
                SettingsButtonRow(label: "Import from Text", systemImage: "text.alignleft") {
                    flow.mode = .text
                }
                SettingsButtonRow(label: "Import from CSV", systemImage: "tablecells") {
                    flow.mode = .csv
                }
            }
            SettingsGroup(title: "Full Backup") {
                SettingsNavRow(label: "Restore from .hprgm", systemImage: "arrow.down.doc") {
                    HprgmRestoreChooseView()
                }
            }
        }
        .environment(flow)
        .navigationDestination(isPresented: Binding(
            get: { flow.mode != nil },
            set: { if !$0 { flow.mode = nil } })) {
                switch flow.mode {
                case .text: TextBacklogImportView()
                case .csv:  CSVBacklogImportView()
                case .none: EmptyView()
                }
        }
    }
}

// MARK: - Export menu

struct ExportView: View {
    @Environment(\.modelContext) private var context
    @State private var shareURL: URL?
    @State private var error: String?

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Full Backup") {
                SettingsButtonRow(label: "Export Backup", systemImage: "square.and.arrow.up") {
                    exportBackup()
                }
            }
            DSText("Export a full app state.")
                .dsTextStyle(.subheadline)
            if let error { DSText(error).dsTextStyle(.subheadline, Color.red) }
        }
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
    }

    private func exportBackup() {
        do {
            shareURL = try HprgmExportService().export(context: context)
        } catch {
            self.error = "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Text backlog import (input → select → summary)

struct TextBacklogImportView: View {
    @Environment(ImportFlow.self) private var flow
    @State private var text = ""

    var body: some View {
        @Bindable var flow = flow
        SettingsScreen(centered: true, trailing: {
            Button {
                let rows = BacklogImportParser.parseText(text)
                if !rows.isEmpty { flow.openSelection(rows: rows, skipped: 0) }
            } label: {
                Text("Load").font(appFont(18)).foregroundStyle(.primary).frame(height: 44).padding(.horizontal, 6)
            }
        }) {
            SettingsSectionLabel(title: "Paste titles — one per line")
            TextEditor(text: $text)
                .font(appFont(17))
                .scrollContentBackground(.hidden)
                .frame(height: 280)
                .padding(8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .navigationDestination(isPresented: $flow.showSelection) {
            ImportSelectionView()
        }
    }
}

// MARK: - CSV backlog import

struct CSVBacklogImportView: View {
    @Environment(ImportFlow.self) private var flow
    @State private var error: String?
    @State private var showPicker = false
    @State private var shareTemplate: URL?

    var body: some View {
        @Bindable var flow = flow
        SettingsScreen(centered: true) {
            SettingsGroup(title: "CSV") {
                SettingsButtonRow(label: "Download template", systemImage: "arrow.down.doc") {
                    shareTemplate = writeTemplate()
                }
                SettingsButtonRow(label: "Choose CSV file", systemImage: "folder") {
                    showPicker = true
                }
            }
            DSText("Requirements:\n•  Date must be formatted YYYY-MM-DD with padded zeroes\n•  Each row must have the title")
                .dsTextStyle(.subheadline)
            if let error { DSText(error).dsTextStyle(.subheadline, Color.red) }
        }
        .sheet(item: $shareTemplate) { url in ShareSheet(items: [url]) }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.commaSeparatedText, .text, .plainText]) { result in
            handle(result)
        }
        .navigationDestination(isPresented: $flow.showSelection) {
            ImportSelectionView()
        }
    }

    private func writeTemplate() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backlog-template.csv")
        try? BacklogImportParser.csvTemplate.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func handle(_ result: Result<URL, Error>) {
        error = nil
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            error = "Couldn't read the file."; return
        }
        switch BacklogImportParser.parseCSV(content) {
        case .rejected(let reason):
            error = "Import rejected: \(reason)"
        case .parsed(let parsed, let skippedNoTitle):
            if parsed.isEmpty { error = "No valid rows found." }
            else { flow.openSelection(rows: parsed, skipped: skippedNoTitle) }
        }
    }
}

// MARK: - Selection page (all selected, deselect, import)

struct ImportSelectionView: View {
    @Environment(ImportFlow.self) private var flow
    @Environment(\.modelContext) private var context
    @State private var selected: Set<UUID> = []

    var body: some View {
        @Bindable var flow = flow
        SettingsScreen(centered: true, trailing: {
            Button { runImport() } label: {
                Text("Import").font(appFont(18)).foregroundStyle(.primary).frame(height: 44).padding(.horizontal, 6)
            }
        }) {
            SettingsSectionLabel(title: "\(selected.count) of \(flow.rows.count) selected")
            ForEach(flow.rows) { row in
                Button {
                    if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
                } label: {
                    HStack(spacing: 12) {
                        SelectionCircle(isOn: selected.contains(row.id))
                        VStack(alignment: .leading, spacing: 2) {
                            DSText(row.title).dsTextStyle(.body).lineLimit(1)
                            if let sub = subtitle(row) { DSText(sub).dsTextStyle(.subheadline) }
                        }
                        Spacer()
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .onAppear { if selected.isEmpty { selected = Set(flow.rows.map { $0.id }) } }
        .navigationDestination(isPresented: $flow.showSummary) {
            ImportSummaryView()
        }
    }

    private func subtitle(_ row: ParsedBacklogRow) -> String? {
        var parts: [String] = []
        if let p = row.project { parts.append(p) }
        if let d = row.date { let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; parts.append(f.string(from: d)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func runImport() {
        let result = BacklogImporter.run(rows: flow.rows, selected: selected,
                                         skippedNoTitle: flow.skipped, context: context)
        flow.openSummary(result)
    }
}

// MARK: - Summary page (expandable categories)

struct ImportSummaryView: View {
    @Environment(ImportFlow.self) private var flow

    var body: some View {
        SettingsScreen(centered: true, trailing: {
            Button { flow.backToMenu() } label: {
                Text("Done").font(appFont(18)).foregroundStyle(.primary).frame(height: 44).padding(.horizontal, 6)
            }
        }) {
            SettingsSectionLabel(title: "Import complete")
            disclosure("Imported", flow.summary?.imported ?? [], color: .green)
            disclosure("Not imported", flow.summary?.notImported ?? [], color: .secondary)
            disclosure("Rejected", flow.summary?.rejected ?? [], color: .red)
        }
    }

    private func disclosure(_ title: String, _ items: [String], color: Color) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { DSText($0).dsTextStyle(.subheadline) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            HStack {
                DSText(title).dsTextStyle(.title3)
                Spacer()
                Text("\(items.count)").font(appFont(18)).foregroundStyle(color)
            }
        }
        .tint(.primary)
    }
}

// MARK: - hprgm restore (choose file → confirm)

/// Step 1: pick the .hprgm file. Choosing one auto-advances to the warning screen.
struct HprgmRestoreChooseView: View {
    @State private var showPicker = false
    @State private var pickedURL: URL?
    @State private var push = false

    var body: some View {
        SettingsScreen(centered: true) {
            SettingsGroup(title: "Restore") {
                SettingsButtonRow(label: "Choose .hprgm file", systemImage: "folder") {
                    showPicker = true
                }
            }
        }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [UTType(filenameExtension: "hprgm") ?? .data, .json, .data]) { result in
            if case .success(let url) = result { pickedURL = url; push = true }
        }
        .navigationDestination(isPresented: $push) {
            if let pickedURL { HprgmRestoreConfirmView(url: pickedURL) }
        }
    }
}

/// Step 2: warning + type RESTORE to confirm.
struct HprgmRestoreConfirmView: View {
    let url: URL
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var confirm = ""
    @State private var error: String?

    private var canRestore: Bool { confirm.uppercased() == "RESTORE" }

    var body: some View {
        // Manual keyboard avoidance + upper-anchored block so the keyboard never
        // covers the red button.
        SettingsScreen(centered: true, manualKeyboardAvoidance: true) {
            VStack(spacing: 14) {
                DSImageView(systemName: "exclamationmark.triangle.fill", size: 48, tint: .color(.red))
                    .padding(.top, 8)
                DSText("Restore Backup").dsTextStyle(.title2)
                DSText("Restoring REPLACES all current data with the backup. This cannot be undone. Your PIN and Face ID stay as they are.")
                    .dsTextStyle(.body).multilineTextAlignment(.center)

                DSText("Type RESTORE to confirm").dsTextStyle(.subheadline).padding(.top, 8)
                TextField("", text: $confirm, prompt: Text("RESTORE").foregroundStyle(.tertiary))
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                    .font(appFont(18)).multilineTextAlignment(.center)
                    .padding(.vertical, 14).padding(.horizontal, 20)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                if let error { DSText(error).dsTextStyle(.subheadline, Color.red) }

                Button { restore() } label: {
                    Text("Restore Everything").font(appFont(18)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(canRestore ? Color.red : Color.red.opacity(0.35), in: Capsule())
                }.buttonStyle(.plain).disabled(!canRestore)
            }
            .frame(maxWidth: .infinity).padding(.horizontal, 8)
        }
    }

    private func restore() {
        guard canRestore else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bundle = try HprgmImportService().preview(fileURL: url)
            try HprgmImportService().importData(bundle, context: context)
            // Full-screen "backup restored" interstitial → Today.
            appState.pendingInterstitial = .restored
        } catch {
            self.error = "Restore failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Importer + summary model

public struct ImportSummary {
    public var imported: [String]
    public var notImported: [String]
    public var rejected: [String]
}

enum BacklogImporter {
    @MainActor
    static func run(rows: [ParsedBacklogRow], selected: Set<UUID>, skippedNoTitle: Int,
                    context: ModelContext) -> ImportSummary {
        let repo = BacklogRepository(context: context)
        let existing = (try? repo.fetchAll()) ?? []
        var seenTitles = Set(existing.map { $0.title.lowercased() })
        var projectsByName: [String: ProjectBucket] = [:]
        for p in (try? repo.fetchProjects()) ?? [] { projectsByName[p.name.lowercased()] = p }

        var imported: [String] = [], notImported: [String] = [], rejected: [String] = []

        for row in rows {
            guard selected.contains(row.id) else { notImported.append(row.title); continue }
            let key = row.title.lowercased()
            if seenTitles.contains(key) { rejected.append("\(row.title) — duplicate title"); continue }
            seenTitles.insert(key)

            var project: ProjectBucket? = nil
            if let pname = row.project {
                if let existing = projectsByName[pname.lowercased()] {
                    project = existing
                } else if let created = try? repo.createProject(name: pname) {
                    project = created
                    projectsByName[pname.lowercased()] = created
                }
            }
            try? repo.create(title: row.title, notes: row.notes, project: project, assignedDate: row.date)
            imported.append(row.title)
        }
        if skippedNoTitle > 0 { rejected.append("\(skippedNoTitle) row(s) with no title") }
        return ImportSummary(imported: imported, notImported: notImported, rejected: rejected)
    }
}

// MARK: - Share sheet + URL Identifiable

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
