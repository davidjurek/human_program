import SwiftUI
import SwiftData

struct BacklogProjectView: View {
    @Environment(\.modelContext) private var context

    /// Display name of this bucket (may be "Unorganized").
    let projectName: String
    /// Nil when this is the "Unorganized" virtual bucket.
    let project: ProjectBucket?

    @Query(sort: \BacklogItem.createdAt) private var allItems: [BacklogItem]

    @State private var isEditMode: Bool = false
    @State private var selectedItems: Set<String> = []
    @State private var showAddSheet: Bool = false
    @State private var showRenameAlert: Bool = false
    @State private var newName: String = ""

    // MARK: - Computed

    private var bucketItems: [BacklogItem] {
        allItems.filter { item in
            guard item.status == .backlog else { return false }
            if let proj = project {
                return item.project?.id == proj.id
            } else {
                return item.project == nil
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Large project name header below nav bar
                HStack {
                    Text(projectName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                if bucketItems.isEmpty {
                    Spacer()
                    Text("No items in this project")
                        .font(AppTypography.caption())
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            if isEditMode {
                                selectAllBar
                            }
                            ForEach(bucketItems) { item in
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

            if isEditMode && !selectedItems.isEmpty {
                bulkDeleteBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddSheet) {
            BacklogTaskEditorView(defaultProject: project)
        }
        .alert("Rename Project", isPresented: $showRenameAlert) {
            TextField("Project name", text: $newName)
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, let proj = project else { return }
                proj.name = trimmed
                proj.updatedAt = Date()
                try? context.save()
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
    }

    // MARK: - Select All Bar

    private var selectAllBar: some View {
        HStack {
            let allSelected = Set(bucketItems.map(\.id)) == selectedItems
            Button {
                if allSelected {
                    selectedItems = []
                } else {
                    selectedItems = Set(bucketItems.map(\.id))
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

    // MARK: - Bulk Delete Bar

    private var bulkDeleteBar: some View {
        HStack {
            Spacer()
            Button {
                deleteSelectedItems()
            } label: {
                Label("Delete Selected", systemImage: "trash")
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(AppColors.accentRed)
            }
            .buttonStyle(.plain)
            Spacer()
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Rename button (only for real projects)
            if project != nil {
                Button {
                    newName = projectName
                    showRenameAlert = true
                } label: {
                    Image(systemName: "pencil")
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
                showAddSheet = true
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
}
