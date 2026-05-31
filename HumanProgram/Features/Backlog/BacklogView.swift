import SwiftUI
import SwiftData
import DSKit

// Backlog, rebuilt on DSKit. One screen with a VIEW TOGGLE between Task View
// (all backlog items) and Project View (project buckets incl. the virtual
// "Unorganized"). Toolbar: view-toggle, sort, +, select. Deletion is swipe-left
// trash or select-mode trash (no red-minus). In select mode the whole row is the
// selector; tapping a title never opens it.
struct BacklogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BacklogItem.createdAt) private var allItems: [BacklogItem]
    @Query(sort: \ProjectBucket.name) private var projects: [ProjectBucket]

    @State private var mode: Mode = .tasks
    @State private var taskSort: TaskSort = .az
    @State private var projectSort: ProjectSort = .az
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var swipeOpen: String?

    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectError: String?
    @State private var showMove = false
    @State private var showDeleteProjectConfirm: ProjectBucket?
    @State private var pushEditorForNew = false

    enum Mode { case tasks, projects }
    enum TaskSort: String, CaseIterable { case az = "A–Z", za = "Z–A", date = "Assigned date" }
    enum ProjectSort: String, CaseIterable { case az = "A–Z", za = "Z–A" }

    private var repo: BacklogRepository { BacklogRepository(context: context) }

    var body: some View {
        ZStack {
            SettingsBackground()
            content
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .overlay { overlays }
        .navigationDestination(isPresented: $pushEditorForNew) {
            BacklogTaskDetailView(item: nil, startInEdit: true)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if mode == .tasks {
                    taskRows(items: sortedTasks)
                } else {
                    projectRows
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .background(ScrollIndicatorInset(right: 7))
        }
    }

    private var sortedTasks: [BacklogItem] {
        let active = allItems.filter { $0.status == .backlog }
        switch taskSort {
        case .az: return active.sorted { $0.title.lowercased() < $1.title.lowercased() }
        case .za: return active.sorted { $0.title.lowercased() > $1.title.lowercased() }
        case .date: return active.sorted {
            ($0.assignedDate ?? .distantFuture) < ($1.assignedDate ?? .distantFuture)
        }
        }
    }

    @ViewBuilder
    private func taskRows(items: [BacklogItem]) -> some View {
        if items.isEmpty {
            DSText("No items in backlog").dsTextStyle(.subheadline)
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 60)
        } else {
            ForEach(items, id: \.id) { item in
                BacklogRow(
                    title: item.title,
                    subtitle: taskSubtitle(item),
                    selecting: selecting,
                    isSelected: selected.contains(item.id),
                    swipeOpen: swipeOpen == item.id,
                    onTapSelect: { toggleSelected(item.id) },
                    onOpenSwipe: { swipeOpen = item.id },
                    onCloseSwipe: { if swipeOpen == item.id { swipeOpen = nil } },
                    onDelete: { delete(item) },
                    destination: { BacklogTaskDetailView(item: item, startInEdit: false) }
                )
            }
        }
    }

    private func taskSubtitle(_ item: BacklogItem) -> String? {
        var parts: [String] = []
        if let p = item.project?.name { parts.append(p) }
        if let d = item.assignedDate {
            let f = DateFormatter(); f.dateFormat = "MMM d"
            parts.append(f.string(from: d))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Projects

    private var sortedProjects: [ProjectBucket] {
        switch projectSort {
        case .az: return projects.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .za: return projects.sorted { $0.name.lowercased() > $1.name.lowercased() }
        }
    }

    private var unassignedCount: Int {
        allItems.filter { $0.status == .backlog && $0.project == nil }.count
    }

    @ViewBuilder
    private var projectRows: some View {
        // "Unorganized" virtual bucket — always visible, never deletable, no select.
        NavigationLink {
            BacklogFolderView(project: nil)
        } label: {
            projectRowContent(name: "Unorganized", count: unassignedCount)
        }
        .buttonStyle(.plain)
        .disabled(selecting)

        ForEach(sortedProjects, id: \.id) { project in
            BacklogRow(
                title: project.name,
                subtitle: "\(project.items.filter { $0.status == .backlog }.count) items",
                selecting: selecting,
                isSelected: selected.contains(project.id),
                swipeOpen: swipeOpen == project.id,
                onTapSelect: { toggleSelected(project.id) },
                onOpenSwipe: { swipeOpen = project.id },
                onCloseSwipe: { if swipeOpen == project.id { swipeOpen = nil } },
                onDelete: { attemptDeleteProject(project) },
                destination: { BacklogFolderView(project: project) }
            )
        }
    }

    private func projectRowContent(name: String, count: Int) -> some View {
        HStack(spacing: 14) {
            DSImageView(systemName: "folder", size: .font(.title3), tint: .color(.primary))
            VStack(alignment: .leading, spacing: 2) {
                DSText(name).dsTextStyle(.title3)
                DSText("\(count) items").dsTextStyle(.subheadline)
            }
            Spacer()
            DSChevronView()
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .onTapGesture { dismiss() }
            Spacer()
            if selecting {
                iconButton("arrow.right.arrow.left") { if !selected.isEmpty { showMove = true } }
                iconButton("trash", tint: .red) { deleteSelected() }
                Button { selecting = false; selected = [] } label: {
                    DSText("Done").dsTextStyle(.headline)
                }.buttonStyle(.plain).padding(.horizontal, 6)
            } else {
                iconButton(mode == .tasks ? "folder" : "checklist") {
                    mode = mode == .tasks ? .projects : .tasks
                }
                sortMenu
                iconButton("plus") { addTapped() }
                Button { selecting = true } label: {
                    DSText("Select").dsTextStyle(.headline)
                }.buttonStyle(.plain).padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func iconButton(_ icon: String, tint: Color = .primary, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint).frame(width: 40, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var sortMenu: some View {
        Menu {
            if mode == .tasks {
                ForEach(TaskSort.allCases, id: \.self) { s in
                    Button { taskSort = s } label: {
                        if taskSort == s { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) }
                    }
                }
            } else {
                ForEach(ProjectSort.allCases, id: \.self) { s in
                    Button { projectSort = s } label: {
                        if projectSort == s { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary).frame(width: 40, height: 44).contentShape(Rectangle())
        }
    }

    private func addTapped() {
        if mode == .tasks {
            pushEditorForNew = true
        } else {
            newProjectName = ""; newProjectError = nil; showNewProject = true
        }
    }

    // MARK: - Overlays (popups)

    @ViewBuilder
    private var overlays: some View {
        if showNewProject {
            NewProjectPopup(name: $newProjectName, error: $newProjectError,
                            onCreate: createProject,
                            onCancel: { showNewProject = false })
        }
        if showMove {
            MoveToProjectPopup(projects: sortedProjects,
                               onPick: { moveSelected(to: $0) },
                               onCancel: { showMove = false })
        }
        if let project = showDeleteProjectConfirm {
            ConfirmPopup(
                message: "Delete “\(project.name)” and its tasks?",
                confirmTitle: "Delete",
                onConfirm: { confirmDeleteProject(project) },
                onCancel: { showDeleteProjectConfirm = nil }
            )
        }
    }

    // MARK: - Actions

    private func toggleSelected(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func delete(_ item: BacklogItem) {
        try? repo.delete(item)
        swipeOpen = nil
    }

    private func deleteSelected() {
        if mode == .tasks {
            for item in allItems where selected.contains(item.id) { try? repo.delete(item) }
        } else {
            for project in projects where selected.contains(project.id) {
                if project.items.contains(where: { $0.status == .backlog }) {
                    showDeleteProjectConfirm = project
                    return
                }
                try? repo.deleteProject(project)
            }
        }
        selected = []; selecting = false
    }

    private func attemptDeleteProject(_ project: ProjectBucket) {
        swipeOpen = nil
        if project.items.contains(where: { $0.status == .backlog }) {
            showDeleteProjectConfirm = project
        } else {
            try? repo.deleteProject(project)
        }
    }

    private func confirmDeleteProject(_ project: ProjectBucket) {
        // "Yes, delete the project and its tasks": delete the tasks too.
        for item in project.items { try? repo.delete(item) }
        try? repo.deleteProject(project)
        showDeleteProjectConfirm = nil
        selected = []; selecting = false
    }

    private func moveSelected(to destination: ProjectBucket?) {
        if mode == .tasks {
            for item in allItems where selected.contains(item.id) { item.project = destination }
        } else {
            // Move ALL tasks of selected projects into the destination.
            for project in projects where selected.contains(project.id) {
                for item in project.items { item.project = destination }
            }
        }
        try? context.save()
        showMove = false; selected = []; selecting = false
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if projects.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            newProjectError = "A project with that name already exists."
            return
        }
        try? repo.createProject(name: name)
        showNewProject = false
    }
}

// ── Folder (a project's tasks — same behavior as Task View) ──────────────────────
struct BacklogFolderView: View {
    let project: ProjectBucket?   // nil = Unorganized
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BacklogItem.createdAt) private var allItems: [BacklogItem]
    @Query(sort: \ProjectBucket.name) private var projects: [ProjectBucket]

    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var swipeOpen: String?
    @State private var showMove = false
    @State private var pushEditorForNew = false

    private var repo: BacklogRepository { BacklogRepository(context: context) }

    private var items: [BacklogItem] {
        allItems.filter { $0.status == .backlog && $0.project?.id == project?.id }
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    var body: some View {
        ZStack {
            SettingsBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    DSText(project?.name ?? "Unorganized").dsTextStyle(.title2)
                        .padding(.bottom, 4)
                    if items.isEmpty {
                        DSText("No items").dsTextStyle(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 40)
                    } else {
                        ForEach(items, id: \.id) { item in
                            BacklogRow(
                                title: item.title,
                                subtitle: item.assignedDate.map { d in
                                    let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
                                },
                                selecting: selecting,
                                isSelected: selected.contains(item.id),
                                swipeOpen: swipeOpen == item.id,
                                onTapSelect: { toggle(item.id) },
                                onOpenSwipe: { swipeOpen = item.id },
                                onCloseSwipe: { if swipeOpen == item.id { swipeOpen = nil } },
                                onDelete: { try? repo.delete(item); swipeOpen = nil },
                                destination: { BacklogTaskDetailView(item: item, startInEdit: false) }
                            )
                        }
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 20).padding(.top, 8)
                .background(ScrollIndicatorInset(right: 7))
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if showMove {
                MoveToProjectPopup(projects: projects.filter { $0.id != project?.id },
                                   onPick: moveSelected, onCancel: { showMove = false })
            }
        }
        .navigationDestination(isPresented: $pushEditorForNew) {
            BacklogTaskDetailView(item: nil, startInEdit: true, defaultProject: project)
        }
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                .onTapGesture { dismiss() }
            Spacer()
            if selecting {
                Button { if !selected.isEmpty { showMove = true } } label: {
                    Image(systemName: "arrow.right.arrow.left").font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary).frame(width: 40, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { deleteSelected() } label: {
                    Image(systemName: "trash").font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.red).frame(width: 40, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { selecting = false; selected = [] } label: { DSText("Done").dsTextStyle(.headline) }
                    .buttonStyle(.plain).padding(.horizontal, 6)
            } else {
                Button { pushEditorForNew = true } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary).frame(width: 40, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { selecting = true } label: { DSText("Select").dsTextStyle(.headline) }
                    .buttonStyle(.plain).padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    private func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
    private func deleteSelected() {
        for item in allItems where selected.contains(item.id) { try? repo.delete(item) }
        selected = []; selecting = false
    }
    private func moveSelected(to destination: ProjectBucket?) {
        for item in allItems where selected.contains(item.id) { item.project = destination }
        try? context.save(); showMove = false; selected = []; selecting = false
    }
}
