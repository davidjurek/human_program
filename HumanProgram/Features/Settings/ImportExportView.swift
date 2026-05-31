import SwiftUI
import SwiftData
import DSKit
import UniformTypeIdentifiers

// Import and Export, split into two DSKit pages. Import offers three options
// (text backlog, CSV backlog, restore .hprgm); Export offers one (.hprgm full
// backup). Every step is a real pushed page.

// MARK: - Import menu

struct ImportView: View {
    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Backlog") {
                SettingsNavRow(label: "Import from Text", systemImage: "text.alignleft") {
                    TextBacklogImportView()
                }
                SettingsNavRow(label: "Import from CSV", systemImage: "tablecells") {
                    CSVBacklogImportView()
                }
            }
            SettingsGroup(title: "Full Backup") {
                SettingsNavRow(label: "Restore from .hprgm", systemImage: "arrow.down.doc") {
                    HprgmRestoreView()
                }
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
                SettingsButtonRow(label: "Export .hprgm", systemImage: "square.and.arrow.up") {
                    exportBackup()
                }
            }
            DSText("Exports your full app state — backlog, schedules, recurring tasks, exercise, daily pages, settings — except the game and your PIN/Face ID.")
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
    @State private var text = ""
    @State private var rows: [ParsedBacklogRow] = []
    @State private var pushSelect = false

    var body: some View {
        SettingsScreen(centered: true) {
            SettingsSectionLabel(title: "Paste titles — one per line")
            TextEditor(text: $text)
                .font(appFont(17))
                .scrollContentBackground(.hidden)
                .frame(height: 280)
                .padding(8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            SettingsButtonRow(label: "Load", systemImage: "arrow.right.circle") {
                rows = BacklogImportParser.parseText(text)
                if !rows.isEmpty { pushSelect = true }
            }
        }
        .navigationDestination(isPresented: $pushSelect) {
            ImportSelectionView(rows: rows, skippedNoTitle: 0)
        }
    }
}

// MARK: - CSV backlog import

struct CSVBacklogImportView: View {
    @State private var rows: [ParsedBacklogRow] = []
    @State private var skipped = 0
    @State private var pushSelect = false
    @State private var error: String?
    @State private var showPicker = false
    @State private var shareTemplate: URL?

    var body: some View {
        SettingsScreen(centered: true) {
            SettingsGroup(title: "CSV") {
                SettingsButtonRow(label: "Download template", systemImage: "arrow.down.doc") {
                    shareTemplate = writeTemplate()
                }
                SettingsButtonRow(label: "Choose CSV file", systemImage: "folder") {
                    showPicker = true
                }
            }
            DSText("The file must be headerless: columns are title, project, date (YYYY-MM-DD), notes. Rows with no title are skipped; a bad date or wrong column count rejects the whole file.")
                .dsTextStyle(.subheadline)
            if let error { DSText(error).dsTextStyle(.subheadline, Color.red) }
        }
        .sheet(item: $shareTemplate) { url in ShareSheet(items: [url]) }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.commaSeparatedText, .text, .plainText]) { result in
            handle(result)
        }
        .navigationDestination(isPresented: $pushSelect) {
            ImportSelectionView(rows: rows, skippedNoTitle: skipped)
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
            rows = parsed; skipped = skippedNoTitle
            if rows.isEmpty { error = "No valid rows found." } else { pushSelect = true }
        }
    }
}

// MARK: - Selection page (all selected, deselect, import)

struct ImportSelectionView: View {
    let rows: [ParsedBacklogRow]
    let skippedNoTitle: Int
    @Environment(\.modelContext) private var context

    @State private var selected: Set<UUID> = []
    @State private var summary: ImportSummary?
    @State private var pushSummary = false

    var body: some View {
        SettingsScreen(centered: true, trailing: {
            Button { runImport() } label: {
                Text("Import").font(appFont(18)).foregroundStyle(.primary).frame(height: 44).padding(.horizontal, 6)
            }
        }) {
            SettingsSectionLabel(title: "\(selected.count) of \(rows.count) selected")
            ForEach(rows) { row in
                Button {
                    if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundStyle(selected.contains(row.id) ? Color.green : Color.secondary)
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
        .onAppear { if selected.isEmpty { selected = Set(rows.map { $0.id }) } }
        .navigationDestination(isPresented: $pushSummary) {
            if let summary { ImportSummaryView(summary: summary) }
        }
    }

    private func subtitle(_ row: ParsedBacklogRow) -> String? {
        var parts: [String] = []
        if let p = row.project { parts.append(p) }
        if let d = row.date { let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; parts.append(f.string(from: d)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func runImport() {
        summary = BacklogImporter.run(rows: rows, selected: selected, skippedNoTitle: skippedNoTitle, context: context)
        pushSummary = true
    }
}

// MARK: - Summary page (expandable categories)

struct ImportSummaryView: View {
    let summary: ImportSummary

    var body: some View {
        SettingsScreen(centered: true) {
            SettingsSectionLabel(title: "Import complete")
            disclosure("Imported", summary.imported, color: .green)
            disclosure("Not imported", summary.notImported, color: .secondary)
            disclosure("Rejected", summary.rejected, color: .red)
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

// MARK: - hprgm restore

struct HprgmRestoreView: View {
    @Environment(\.modelContext) private var context
    @State private var showPicker = false
    @State private var pickedURL: URL?
    @State private var confirm = ""
    @State private var error: String?
    @State private var done = false

    private var canRestore: Bool { pickedURL != nil && confirm.uppercased() == "RESET" }

    var body: some View {
        SettingsScreen(centered: true) {
            VStack(spacing: 16) {
                DSImageView(systemName: "exclamationmark.triangle.fill", size: 48, tint: .color(.red))
                    .padding(.top, 12)
                DSText("Restore Backup").dsTextStyle(.title2)
                DSText("Restoring REPLACES all current data with the backup. This cannot be undone. Your PIN and Face ID stay as they are.")
                    .dsTextStyle(.body).multilineTextAlignment(.center)

                SettingsButtonRow(label: pickedURL == nil ? "Choose .hprgm file" : "File selected ✓",
                                  systemImage: "folder") { showPicker = true }

                DSText("Type RESET to confirm").dsTextStyle(.subheadline).padding(.top, 8)
                TextField("", text: $confirm, prompt: Text("RESET").foregroundStyle(.tertiary))
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                    .font(appFont(18)).multilineTextAlignment(.center)
                    .padding(.vertical, 14).padding(.horizontal, 20)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                if let error { DSText(error).dsTextStyle(.subheadline, Color.red) }
                if done { DSText("Restore complete.").dsTextStyle(.subheadline, Color.green) }

                Button { restore() } label: {
                    Text("Restore Everything").font(appFont(18)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(canRestore ? Color.red : Color.red.opacity(0.35), in: Capsule())
                }.buttonStyle(.plain).disabled(!canRestore)
            }
            .frame(maxWidth: .infinity).padding(.horizontal, 8)
        }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [UTType(filenameExtension: "hprgm") ?? .data, .json, .data]) { result in
            if case .success(let url) = result { pickedURL = url; error = nil }
        }
    }

    private func restore() {
        guard let url = pickedURL, canRestore else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bundle = try HprgmImportService().preview(fileURL: url)
            try HprgmImportService().importData(bundle, context: context)
            done = true
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
