import SwiftUI
import SwiftData

// MARK: - Import Mode

private enum ImportMode: String, CaseIterable {
    case text = "Text"
    case csv  = "CSV"
}

// MARK: - Parsed CSV Row

private struct CSVRow: Identifiable {
    let id = UUID()
    var title: String
    var dateString: String
    var projectName: String
    var note: String
    var isError: Bool          // true = title was blank
    var isSelected: Bool = true

    var parsedDate: Date? {
        guard !dateString.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

// MARK: - BacklogImportView

struct BacklogImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ProjectBucket.name) private var projects: [ProjectBucket]

    @State private var importMode: ImportMode = .text

    // Text import state
    @State private var textInput: String = ""

    // CSV import state
    @State private var csvInput: String = ""
    @State private var parsedRows: [CSVRow] = []
    @State private var showParsedPreview: Bool = false
    @State private var selectedRowIDs: Set<UUID> = []

    // Feedback
    @State private var importResultMessage: String = ""
    @State private var showImportResult: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Mode picker
                    Picker("Import Mode", selection: $importMode) {
                        ForEach(ImportMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider()

                    ScrollView {
                        if importMode == .text {
                            textImportContent
                        } else {
                            csvImportContent
                        }
                    }
                }
            }
            .navigationTitle("Import Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Import Complete", isPresented: $showImportResult) {
                Button("OK") { dismiss() }
            } message: {
                Text(importResultMessage)
            }
        }
    }

    // MARK: - Text Import Content

    private var textImportContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste or type your tasks below. Each line becomes one backlog item.")
                .font(AppTypography.bodySmallText())
                .foregroundStyle(AppColors.textSecondary)

            TextEditor(text: $textInput)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
                .frame(minHeight: 200)
                .padding(10)
                .background(AppColors.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()

            let lineCount = nonBlankLines(textInput).count
            if lineCount > 0 {
                Text("\(lineCount) item\(lineCount == 1 ? "" : "s") will be added.")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.accent)
            }

            Button {
                importText()
            } label: {
                Text("Import")
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(lineCount > 0 ? AppColors.accent : AppColors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(lineCount == 0)
        }
        .padding(20)
    }

    // MARK: - CSV Import Content

    private var csvImportContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paste CSV below. Required header row:")
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textSecondary)
                Text("title,date,project_bucket,note")
                    .font(AppTypography.monoText())
                    .foregroundStyle(AppColors.accent)
                    .padding(8)
                    .background(AppColors.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Date format: yyyy-MM-dd (e.g. 2026-05-29). Leave blank to skip.")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.textTertiary)
            }

            TextEditor(text: $csvInput)
                .font(AppTypography.monoText())
                .foregroundStyle(AppColors.textPrimary)
                .frame(minHeight: 160)
                .padding(10)
                .background(AppColors.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .autocapitalization(.none)

            Button {
                parseCSV()
            } label: {
                Text("Parse")
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(csvInput.isEmpty ? AppColors.textTertiary : AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(csvInput.isEmpty)

            if showParsedPreview {
                csvPreviewSection
            }
        }
        .padding(20)
    }

    // MARK: - CSV Preview Section

    @ViewBuilder
    private var csvPreviewSection: some View {
        let goodRows = parsedRows.filter { !$0.isError }
        let errorRows = parsedRows.filter { $0.isError }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(AppTypography.sectionHeader())
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(.uppercase)
                Spacer()
                if !goodRows.isEmpty {
                    Button {
                        // Toggle all good rows
                        let allSelected = goodRows.allSatisfy { selectedRowIDs.contains($0.id) }
                        if allSelected {
                            for row in goodRows { selectedRowIDs.remove(row.id) }
                        } else {
                            for row in goodRows { selectedRowIDs.insert(row.id) }
                        }
                    } label: {
                        Text(goodRows.allSatisfy { selectedRowIDs.contains($0.id) } ? "Deselect All" : "Select All")
                            .font(AppTypography.buttonLabel())
                            .foregroundStyle(AppColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !goodRows.isEmpty {
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 32)
                        Text("Title")
                            .font(AppTypography.taskMeta())
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Date")
                            .font(AppTypography.taskMeta())
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 90, alignment: .leading)
                        Text("Project")
                            .font(AppTypography.taskMeta())
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 80, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.surfaceSunken)

                    ForEach(goodRows) { row in
                        csvPreviewRow(row: row)
                        Divider().padding(.leading, 44)
                    }
                }
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border, lineWidth: 0.5)
                )
            }

            if !errorRows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(errorRows.count) row\(errorRows.count == 1 ? "" : "s") skipped — missing title")
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.accentRed)
                }
            }

            let selectedCount = goodRows.filter { selectedRowIDs.contains($0.id) }.count

            Button {
                importSelectedCSVRows()
            } label: {
                Text(selectedCount > 0 ? "Import \(selectedCount) Selected" : "Import Selected")
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(selectedCount > 0 ? AppColors.accent : AppColors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
        }
    }

    private func csvPreviewRow(row: CSVRow) -> some View {
        let isSelected = selectedRowIDs.contains(row.id)
        return HStack(spacing: 0) {
            Button {
                if isSelected {
                    selectedRowIDs.remove(row.id)
                } else {
                    selectedRowIDs.insert(row.id)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.checkboxBorder)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .frame(width: 32)

            Text(row.title)
                .font(AppTypography.taskMeta())
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.dateString.isEmpty ? "—" : row.dateString)
                .font(AppTypography.taskMeta())
                .foregroundStyle(row.dateString.isEmpty ? AppColors.textTertiary : AppColors.textSecondary)
                .frame(width: 90, alignment: .leading)

            Text(row.projectName.isEmpty ? "—" : row.projectName)
                .font(AppTypography.taskMeta())
                .foregroundStyle(row.projectName.isEmpty ? AppColors.textTertiary : AppColors.accent)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.surface)
    }

    // MARK: - Helpers

    private func nonBlankLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Import Text

    private func importText() {
        let lines = nonBlankLines(textInput)
        guard !lines.isEmpty else { return }
        let repo = BacklogRepository(context: context)
        for line in lines {
            try? repo.create(title: line)
        }
        try? PageRefreshService.refresh(context: context)
        importResultMessage = "Added \(lines.count) item\(lines.count == 1 ? "" : "s") to the backlog."
        showImportResult = true
    }

    // MARK: - Parse CSV

    private func parseCSV() {
        let lines = csvInput.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.isEmpty else { return }

        // Find header line
        let headerIndex = lines.firstIndex(where: {
            $0.lowercased().hasPrefix("title")
        }) ?? 0

        let dataLines = Array(lines.dropFirst(headerIndex + 1))
            .filter { !$0.isEmpty }

        parsedRows = dataLines.map { line in
            let cols = parseCSVLine(line)
            let title = cols.count > 0 ? cols[0].trimmingCharacters(in: .whitespaces) : ""
            let date  = cols.count > 1 ? cols[1].trimmingCharacters(in: .whitespaces) : ""
            let proj  = cols.count > 2 ? cols[2].trimmingCharacters(in: .whitespaces) : ""
            let note  = cols.count > 3 ? cols[3].trimmingCharacters(in: .whitespaces) : ""
            return CSVRow(
                title: title,
                dateString: date,
                projectName: proj,
                note: note,
                isError: title.isEmpty,
                isSelected: !title.isEmpty
            )
        }

        // Auto-select all valid rows
        selectedRowIDs = Set(parsedRows.filter { !$0.isError }.map(\.id))
        showParsedPreview = true
    }

    /// Simple CSV line parser that handles quoted fields.
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iter = line.makeIterator()

        while let char = iter.next() {
            switch char {
            case "\"":
                inQuotes.toggle()
            case ",":
                if inQuotes {
                    current.append(char)
                } else {
                    result.append(current)
                    current = ""
                }
            default:
                current.append(char)
            }
        }
        result.append(current)
        return result
    }

    // MARK: - Import Selected CSV Rows

    private func importSelectedCSVRows() {
        let toImport = parsedRows.filter { !$0.isError && selectedRowIDs.contains($0.id) }
        guard !toImport.isEmpty else { return }

        let repo = BacklogRepository(context: context)
        var createdCount = 0

        for row in toImport {
            // Find or create project
            var project: ProjectBucket? = nil
            if !row.projectName.isEmpty {
                if let existing = projects.first(where: {
                    $0.name.localizedCaseInsensitiveCompare(row.projectName) == .orderedSame
                }) {
                    project = existing
                } else {
                    project = try? repo.createProject(name: row.projectName)
                }
            }

            try? repo.create(
                title: row.title,
                notes: row.note,
                project: project,
                assignedDate: row.parsedDate
            )
            createdCount += 1
        }

        try? PageRefreshService.refresh(context: context)
        importResultMessage = "Added \(createdCount) item\(createdCount == 1 ? "" : "s") to the backlog."
        showImportResult = true
    }
}
