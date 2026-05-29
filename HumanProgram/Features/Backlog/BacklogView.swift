import SwiftUI
import SwiftData

// MARK: - Supporting Enums

enum BacklogViewMode: String, CaseIterable {
    case task = "Tasks"
    case project = "Projects"
}

enum BacklogSortMode: String, CaseIterable {
    case createdDate = "Date Created"
    case assignedDate = "Assigned Date"
    case alphaAZ = "A → Z"
    case alphaZA = "Z → A"
}

// MARK: - BacklogView

struct BacklogView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \BacklogItem.createdAt) private var allItems: [BacklogItem]
    @Query(sort: \ProjectBucket.name)   private var projects: [ProjectBucket]

    @State private var viewMode: BacklogViewMode = .task
    @State private var sortMode: BacklogSortMode = .createdDate
    @State private var isEditMode: Bool = false
    @State private var selectedItems: Set<String> = []
    @State private var showAddSheet: Bool = false
    @State private var showAddProjectAlert: Bool = false
    @State private var newProjectName: String = ""
    @State private var searchText: String = ""
    @State private var searchActive: Bool = false
    @State private var showBulkDatePicker: Bool = false
    @State private var showBulkProjectPicker: Bool = false
    @State private var bulkAssignDate: Date = Date()
    @State private var bulkAssignProjectID: String = ""

    // MARK: - Computed

    var activeItems: [BacklogItem] {
        let filtered = allItems.filter { item in
            guard item.status == .backlog else { return false }
            if searchActive && !searchText.isEmpty {
                return item.title.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
        switch sortMode {
        case .createdDate:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .assignedDate:
            return filtered.sorted {
                let lhs = $0.assignedDate ?? .distantFuture
                let rhs = $1.assignedDate ?? .distantFuture
                return lhs < rhs
            }
        case .alphaAZ:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .alphaZA:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
    }

    var groupedByProject: [(bucket: String, items: [BacklogItem])] {
        let active = activeItems
        var result: [(bucket: String, items: [BacklogItem])] = []

        // "Unorganized" first — items with no project
        let unorganized = active.filter { $0.project == nil }
        result.append((bucket: "Unorganized", items: unorganized))

        // Each project in alphabetical order
        for project in projects.sorted(by: { $0.name < $1.name }) {
            let bucket = active.filter { $0.project?.id == project.id }
            result.append((bucket: project.name, items: bucket))
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if searchActive {
                    searchBar
                }

                if viewMode == .task {
                    taskView
                } else {
                    projectView
                }
            }

            if isEditMode && !selectedItems.isEmpty {
                bulkActionsBar
            }
        }
        .navigationTitle("Backlog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddSheet) {
            BacklogTaskEditorView(defaultProject: nil)
        }
        .alert("New Project", isPresented: $showAddProjectAlert) {
            TextField("Project name", text: $newProjectName)
            Button("Create") {
                let trimmed = newProjectName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let repo = BacklogRepository(context: context)
                try? repo.createProject(name: trimmed)
                newProjectName = ""
            }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        }
        .sheet(isPresented: $showBulkDatePicker) { bulkDateSheet }
        .sheet(isPresented: $showBulkProjectPicker) { bulkProjectSheet }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
                .font(.system(size: 14))
            TextField("Search backlog", text: $searchText)
                .font(AppTypography.taskTitle())
                .foregroundStyle(AppColors.textPrimary)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.surfaceSunken)
    }

    // MARK: - Task View

    @ViewBuilder
    private var taskView: some View {
        if activeItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    if isEditMode {
                        selectAllBar
                    }
                    ForEach(activeItems) { item in
                        BacklogRowView(
                            item: item,
                            isEditMode: isEditMode,
                            isSelected: selectedItems.contains(item.id),
                            onToggleSelect: { toggleSelect(item) },
                            onDelete: { deleteItem(item) }
                        )
                        Divider()
                            .padding(.leading, isEditMode ? 60 : 16)
                    }
                }
                .padding(.bottom, isEditMode && !selectedItems.isEmpty ? 80 : 0)
            }
        }
    }

    // MARK: - Project View

    @ViewBuilder
    private var projectView: some View {
        let groups = groupedByProject
        let hasAny = groups.contains { !$0.items.isEmpty } || !projects.isEmpty

        if !hasAny {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(groups, id: \.bucket) { group in
                        NavigationLink(destination: BacklogProjectView(
                            projectName: group.bucket,
                            project: projects.first(where: { $0.name == group.bucket })
                        )) {
                            ProjectRowView(
                                name: group.bucket,
                                count: group.items.count,
                                isEditMode: isEditMode,
                                isDeletable: group.bucket != "Unorganized",
                                onDelete: {
                                    if let proj = projects.first(where: { $0.name == group.bucket }) {
                                        deleteProject(proj)
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No items in backlog")
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
        }
    }

    // MARK: - Select All Bar

    private var selectAllBar: some View {
        HStack {
            let allSelected = Set(activeItems.map(\.id)) == selectedItems
            Button {
                if allSelected {
                    selectedItems = []
                } else {
                    selectedItems = Set(activeItems.map(\.id))
                }
            } label: {
                Text(allSelected ? "Deselect All" : "Select All")
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("\(selectedItems.count) selected")
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Bulk Actions Bar

    private var bulkActionsBar: some View {
        HStack(spacing: 16) {
            Button {
                showBulkDatePicker = true
            } label: {
                Label("Assign Date", systemImage: "calendar")
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 20)

            Button {
                showBulkProjectPicker = true
            } label: {
                Label("Assign Project", systemImage: "folder")
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                deleteSelectedItems()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(AppColors.accentRed)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(AppColors.separator)
        }
    }

    // MARK: - Bulk Date Sheet

    private var bulkDateSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                DatePicker("Assign Date", selection: $bulkAssignDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(AppColors.accent)
                Spacer()
            }
            .padding()
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Assign Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBulkDatePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyBulkDate(bulkAssignDate)
                        showBulkDatePicker = false
                    }
                    .font(AppTypography.buttonLabel())
                }
            }
        }
    }

    // MARK: - Bulk Project Sheet

    private var bulkProjectSheet: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        Button {
                            applyBulkProject(nil)
                            showBulkProjectPicker = false
                        } label: {
                            HStack {
                                Text("No Project")
                                    .font(AppTypography.taskTitle())
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                        ForEach(projects) { project in
                            Button {
                                applyBulkProject(project)
                                showBulkProjectPicker = false
                            } label: {
                                HStack {
                                    Text(project.name)
                                        .font(AppTypography.taskTitle())
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .navigationTitle("Assign Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBulkProjectPicker = false }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if isEditMode {
                Button {
                    isEditMode = false
                    selectedItems = []
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Search toggle
            Button {
                searchActive.toggle()
                if !searchActive { searchText = "" }
            } label: {
                Image(systemName: searchActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .foregroundStyle(searchActive ? AppColors.accent : AppColors.textPrimary)
            }

            // View mode menu
            Menu {
                ForEach(BacklogViewMode.allCases, id: \.self) { mode in
                    Button {
                        viewMode = mode
                        isEditMode = false
                        selectedItems = []
                    } label: {
                        Label(mode.rawValue, systemImage: mode == .task ? "checklist" : "folder")
                    }
                }
            } label: {
                Image(systemName: viewMode == .task ? "checklist" : "folder")
                    .foregroundStyle(AppColors.textPrimary)
            }

            // Sort menu (task view only)
            if viewMode == .task {
                Menu {
                    ForEach(BacklogSortMode.allCases, id: \.self) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            if sortMode == mode {
                                Label(mode.rawValue, systemImage: "checkmark")
                            } else {
                                Text(mode.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }

            // Edit / Done
            Button {
                if isEditMode {
                    isEditMode = false
                    selectedItems = []
                } else {
                    isEditMode = true
                }
            } label: {
                Text(isEditMode ? "Done" : "Edit")
                    .foregroundStyle(AppColors.accent)
            }

            // Add
            Button {
                if viewMode == .project {
                    showAddProjectAlert = true
                } else {
                    showAddSheet = true
                }
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
    }

    // MARK: - Actions

    private func toggleSelect(_ item: BacklogItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }

    private func deleteItem(_ item: BacklogItem) {
        let repo = BacklogRepository(context: context)
        try? repo.delete(item)
        try? PageRefreshService.refresh(context: context)
    }

    private func deleteProject(_ project: ProjectBucket) {
        let repo = BacklogRepository(context: context)
        try? repo.deleteProject(project)
    }

    private func deleteSelectedItems() {
        let repo = BacklogRepository(context: context)
        let toDelete = allItems.filter { selectedItems.contains($0.id) }
        for item in toDelete {
            try? repo.delete(item)
        }
        selectedItems = []
        isEditMode = false
        try? PageRefreshService.refresh(context: context)
    }

    private func applyBulkDate(_ date: Date) {
        let toUpdate = allItems.filter { selectedItems.contains($0.id) }
        let start = Calendar.current.startOfDay(for: date)
        for item in toUpdate {
            item.assignedDate = start
            item.updatedAt = Date()
        }
        try? context.save()
        try? PageRefreshService.refresh(context: context)
    }

    private func applyBulkProject(_ project: ProjectBucket?) {
        let toUpdate = allItems.filter { selectedItems.contains($0.id) }
        for item in toUpdate {
            item.project = project
            item.updatedAt = Date()
        }
        try? context.save()
        try? PageRefreshService.refresh(context: context)
    }
}

// MARK: - BacklogRowView

struct BacklogRowView: View {
    let item: BacklogItem
    let isEditMode: Bool
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if isEditMode {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.checkboxBorder)
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .frame(width: 44)
            }

            NavigationLink(destination: BacklogDetailView(item: item)) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(AppTypography.taskTitle())
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            if let project = item.project {
                                Text(project.name)
                                    .font(AppTypography.taskMeta())
                                    .foregroundStyle(AppColors.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.accent.opacity(0.1))
                                    .clipShape(Capsule())
                            }

                            if let date = item.assignedDate {
                                HStack(spacing: 3) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 11))
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(AppTypography.taskMeta())
                                }
                                .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditMode {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(AppColors.accentRed)
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .frame(width: 44)
            }
        }
        .background(AppColors.background)
    }
}

// MARK: - ProjectRowView

struct ProjectRowView: View {
    let name: String
    let count: Int
    let isEditMode: Bool
    let isDeletable: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if isEditMode && isDeletable {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(AppColors.accentRed)
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .frame(width: 44)
            } else if isEditMode {
                // placeholder spacer so rows align
                Color.clear.frame(width: 44)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(AppTypography.taskTitle())
                        .foregroundStyle(AppColors.textPrimary)
                    Text("\(count) item\(count == 1 ? "" : "s")")
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppColors.background)
    }
}
