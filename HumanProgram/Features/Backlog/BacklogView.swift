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

    // View mode and task sort persist across visits (owner request). [#2/#7]
    @AppStorage(DefaultsKey.backlogViewMode) private var mode: Mode = .tasks
    @AppStorage(DefaultsKey.backlogTaskSort) private var taskSort: TaskSort = .created
    @State private var projectSort: ProjectSort = .az
    @State private var selecting = false
    @State private var selected: Set<String> = []

    // Shared gesture engine (tap / scroll / swipe-left-to-delete), reorder OFF — Backlog
    // is a sorted list. Same engine as Today/Schedule/Exercise/Routines. [owner]
    @State private var rows = RowGestureCoordinator<String>(rowHeight: BacklogMetrics.rowHeight, trashWidth: BacklogMetrics.trashWidth, reorderEnabled: false)
    @State private var route: Route?

    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectError: String?
    @State private var showMove = false
    @State private var projectsPendingDelete: [ProjectBucket] = []
    @State private var pushEditorForNew = false

    enum Mode: String { case tasks, projects }
    enum TaskSort: String, CaseIterable {
        case created = "Date created", az = "A–Z", za = "Z–A", date = "Assigned date"
    }
    enum ProjectSort: String, CaseIterable { case az = "A–Z", za = "Z–A" }

    /// Programmatic destination for a tapped row (replaces in-row NavigationLink so a
    /// tap that began as a swipe / edge-back never fires it). [owner]
    enum Route: Identifiable, Hashable {
        case task(String), folder(String?)   // folder(nil) = Unorganized
        var id: String {
            switch self {
            case .task(let i):   return "t-\(i)"
            case .folder(let p): return "f-\(p ?? "_")"
            }
        }
    }

    private var repo: BacklogRepository { BacklogRepository(context: context) }

    var body: some View {
        rows.canInteract = { !selecting }
        rows.deleteRow = { handleDelete(id: $0) }

        return ZStack {
            SettingsBackground()
            content
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .overlay { overlays }
        .navigationDestination(isPresented: $pushEditorForNew) {
            BacklogTaskDetailView(item: nil, startInEdit: true)
        }
        .navigationDestination(item: $route) { route in
            switch route {
            case .task(let id):
                if let item = allItems.first(where: { $0.id == id }) {
                    BacklogTaskDetailView(item: item, startInEdit: false)
                }
            case .folder(let pid):
                BacklogFolderView(project: pid.flatMap { id in projects.first(where: { $0.id == id }) })
            }
        }
        .onChange(of: mode) { _, _ in rows.swipeOpenId = nil; selecting = false; selected = [] }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {        // [#43] 48 + 7 = 55pt pitch
                let data = backlogData                       // one pass per render [#41]
                if mode == .tasks {
                    taskRows(items: data.tasks)
                } else {
                    projectRows(unassignedCount: data.unassignedCount, counts: data.projectCounts)
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .rowGestures(rows)                              // shared tap/swipe engine [owner]
        }
        .scrollDismissesKeyboard(.interactively)           // [#46] drag-to-dismiss
        .scrollDisabled(rows.isInteracting)                // suspend scroll only mid-swipe
    }

    /// All per-render backlog derivations in ONE pass: the active+sorted task list,
    /// the unassigned count, and a project→count map (so project rows read a count
    /// from the map instead of each re-scanning all items). [#41]
    private struct BacklogData {
        var tasks: [BacklogItem] = []
        var unassignedCount = 0
        var projectCounts: [PersistentIdentifier: Int] = [:]
    }

    private var backlogData: BacklogData {
        var data = BacklogData()
        var active: [BacklogItem] = []
        for item in allItems where item.status == .backlog {
            active.append(item)
            if let pid = item.project?.persistentModelID {
                data.projectCounts[pid, default: 0] += 1
            } else {
                data.unassignedCount += 1
            }
        }
        switch taskSort {
        // Creation order, newest at the BOTTOM (default). [owner]
        case .created: data.tasks = active.sorted { $0.createdAt < $1.createdAt }
        case .az: data.tasks = active.sorted { $0.title.lowercased() < $1.title.lowercased() }
        case .za: data.tasks = active.sorted { $0.title.lowercased() > $1.title.lowercased() }
        case .date: data.tasks = active.sorted {
            ($0.assignedDate ?? .distantFuture) < ($1.assignedDate ?? .distantFuture)
        }
        }
        return data
    }

    @ViewBuilder
    private func taskRows(items: [BacklogItem]) -> some View {
        if items.isEmpty {
            DSText("No items in backlog").dsTextStyle(.subheadline)
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 60)
        } else {
            ForEach(items, id: \.id) { item in
                BacklogRow(coordinator: rows, id: item.id, glyph: .bullet,
                           title: item.title, subtitle: taskSubtitle(item),
                           selecting: selecting, isSelected: selected.contains(item.id),
                           onTap: { if selecting { toggleSelected(item.id) } else { route = .task(item.id) } })
            }
        }
    }

    private func taskSubtitle(_ item: BacklogItem) -> String? {
        var parts: [String] = []
        if let p = item.project?.name { parts.append(p) }
        if let d = item.assignedDate {
            parts.append(AppDateFormat.monthDay(d))
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

    @ViewBuilder
    private func projectRows(unassignedCount: Int, counts: [PersistentIdentifier: Int]) -> some View {
        // "Unorganized" sorts by its name among the real projects (not pinned first). [owner]
        let isAZ = projectSort == .az
        let before = sortedProjects.filter {
            isAZ ? $0.name.lowercased() < "unorganized" : $0.name.lowercased() > "unorganized"
        }
        let after = sortedProjects.filter {
            isAZ ? $0.name.lowercased() >= "unorganized" : $0.name.lowercased() <= "unorganized"
        }
        ForEach(before, id: \.id) { projectRow($0, counts: counts) }
        // "Unorganized" virtual bucket — always visible, never deletable, no select.
        Button { if !selecting { route = .folder(nil) } } label: {
            projectRowContent(name: "Unorganized", count: unassignedCount)
        }
        .buttonStyle(.plain)
        .a11yTapBorder(Rectangle())
        .disabled(selecting)
        ForEach(after, id: \.id) { projectRow($0, counts: counts) }
    }

    private func projectRow(_ project: ProjectBucket, counts: [PersistentIdentifier: Int]) -> some View {
        BacklogRow(coordinator: rows, id: project.id, glyph: .folder,
                   title: project.name,
                   subtitle: "\(counts[project.persistentModelID] ?? 0) items",
                   selecting: selecting, isSelected: selected.contains(project.id),
                   onTap: { if selecting { toggleSelected(project.id) } else { route = .folder(project.id) } })
    }

    private func projectRowContent(name: String, count: Int) -> some View {
        // Match BacklogRow: centre the folder icon on the title's FIRST line. [owner]
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if selecting {
                // Match the other rows' rightward shift (a circle-sized slot) but show
                // nothing — Unorganized has no circle and isn't selectable. [owner]
                Color.clear.frame(width: 28, height: 28)
                    .alignmentGuide(.firstTextBaseline) { _ in BacklogMetrics.glyphSize / 2 + 7 }
            } else {
                DSImageView(systemName: "folder", size: .size(.custom(BacklogMetrics.glyphSize)), tint: .color(.secondary))
                    .alignmentGuide(.firstTextBaseline) { d in d.height / 2 + 7 }
            }
            VStack(alignment: .leading, spacing: 2) {
                DSText(name).dsTextStyle(.title3).longTitle()
                DSText("\(count) items").dsTextStyle(.subheadline)
            }
            Spacer(minLength: 8)
        }
        // Match BacklogRow's sizing exactly so the gap below Unorganized equals the
        // gaps between the other project rows. [owner]
        .padding(.vertical, 8)
        .frame(minHeight: BacklogMetrics.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            BackChevronButton { dismiss() }
            Spacer()
            if selecting {
                BacklogBarButton(icon: "arrow.right.arrow.left") { if !selected.isEmpty { showMove = true } }
                BacklogBarButton(icon: "trash", tint: .red) { deleteSelected() }
                BacklogTextBarButton(title: "Done") { selecting = false; selected = [] }
            } else {
                // View toggle shows the CURRENT view as a word. Sized to its text
                // (no fixed width) so there's no empty space to the right of the
                // label, which also nudges it rightward toward the sort button.
                Button { mode = mode == .tasks ? .projects : .tasks } label: {
                    DSText(mode == .tasks ? "Task" : "Project").dsTextStyle(.headline)
                        .frame(height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).a11yTapBorder(Rectangle())
                sortMenu
                BacklogBarButton(icon: "plus") { addTapped() }
                BacklogTextBarButton(title: "Select") { selecting = true }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .topBarFrost()                                       // [#47]
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
            DSImageView(systemName: "arrow.up.arrow.down", size: 17, tint: .color(.primary))   // [#199]
                .frame(width: 40, height: 44).contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
        }
        .tint(.primary)   // keep the glyph black, not the menu accent (blue)
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
        if !projectsPendingDelete.isEmpty {
            ConfirmPopup(
                message: projectsPendingDelete.count == 1
                    ? "Delete “\(projectsPendingDelete[0].name)” and its tasks?"
                    : "Delete \(projectsPendingDelete.count) projects and their tasks?",
                confirmTitle: "Delete",
                onConfirm: confirmDeleteProjects,
                onCancel: { projectsPendingDelete = [] }
            )
        }
    }

    // MARK: - Actions

    private func toggleSelected(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Routed from the shared coordinator's trash tap (task id in Task view, project id
    /// in Project view).
    private func handleDelete(id: String) {
        if mode == .tasks {
            if let item = allItems.first(where: { $0.id == id }) { delete(item) }
        } else {
            if let project = projects.first(where: { $0.id == id }) { attemptDeleteProject(project) }
        }
    }

    private func delete(_ item: BacklogItem) {
        try? repo.delete(item)
    }

    private func deleteSelected() {
        if mode == .tasks {
            for item in allItems where selected.contains(item.id) { try? repo.delete(item) }
            selected = []; selecting = false
        } else {
            let chosen = projects.filter { selected.contains($0.id) }
            let nonEmpty = chosen.filter { $0.items.contains(where: { $0.status == .backlog }) }
            let nonEmptyIds = Set(nonEmpty.map { $0.id })
            // Empty projects (no active tasks) delete immediately; the rest are queued
            // into ONE confirmation covering all of them, so none are silently dropped.
            for project in chosen where !nonEmptyIds.contains(project.id) {
                try? repo.deleteProject(project)
            }
            if nonEmpty.isEmpty {
                selected = []; selecting = false
            } else {
                projectsPendingDelete = nonEmpty
            }
        }
    }

    /// Deleting a project: an EMPTY project (no active tasks) is removed straight away
    /// (nothing to lose), while a NON-EMPTY one routes through a confirmation that
    /// deletes its tasks too. This keep-vs-destroy split is deliberate, not a bug. [#130]
    private func attemptDeleteProject(_ project: ProjectBucket) {
        if project.items.contains(where: { $0.status == .backlog }) {
            projectsPendingDelete = [project]
        } else {
            try? repo.deleteProject(project)
        }
    }

    private func confirmDeleteProjects() {
        // "Yes, delete the project(s) and their tasks": delete the tasks too.
        for project in projectsPendingDelete {
            for item in project.items { try? repo.delete(item) }
            try? repo.deleteProject(project)
        }
        projectsPendingDelete = []
        selected = []; selecting = false
    }

    private func moveSelected(to destination: ProjectBucket?) {
        if mode == .tasks {
            try? repo.move(allItems.filter { selected.contains($0.id) }, to: destination)
        } else {
            // Move ALL tasks of selected projects into the destination.
            let items = projects.filter { selected.contains($0.id) }.flatMap { $0.items }
            try? repo.move(items, to: destination)
        }
        showMove = false; selected = []; selecting = false
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Uniqueness is enforced by the repository (#131); surface its rejection.
        do {
            try repo.createProject(name: name)
            showNewProject = false
        } catch {
            newProjectError = "A project with that name already exists."
        }
    }
}

// ── Folder (a project's tasks) ───────────────────────────────────────────────────
// Mirrors Task View's rows/gestures, but always uses the default creation-order sort
// (newest at the bottom) — there is no in-folder sort menu by design. [#132]
struct BacklogFolderView: View {
    let project: ProjectBucket?   // nil = Unorganized
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BacklogItem.createdAt) private var allItems: [BacklogItem]
    @Query(sort: \ProjectBucket.name) private var projects: [ProjectBucket]

    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var showMove = false
    @State private var pushEditorForNew = false

    // Same shared gesture engine as the main backlog (tap/scroll/swipe-left, no reorder).
    @State private var rows = RowGestureCoordinator<String>(rowHeight: BacklogMetrics.rowHeight, trashWidth: BacklogMetrics.trashWidth, reorderEnabled: false)
    @State private var taskRoute: TaskRoute?
    struct TaskRoute: Identifiable, Hashable { let id: String }

    private var repo: BacklogRepository { BacklogRepository(context: context) }

    private var items: [BacklogItem] {
        // Creation order, newest at the bottom — same as the main Task view default.
        allItems.filter { $0.status == .backlog && $0.project?.id == project?.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        rows.canInteract = { !selecting }
        rows.deleteRow = { id in if let it = allItems.first(where: { $0.id == id }) { try? repo.delete(it) } }

        return ZStack {
            SettingsBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    DSText(project?.name ?? "Unorganized").dsTextStyle(.title2)
                        .padding(.bottom, 4)
                    if items.isEmpty {
                        DSText("No items").dsTextStyle(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 40)
                    } else {
                        ForEach(items, id: \.id) { item in
                            BacklogRow(coordinator: rows, id: item.id, glyph: .bullet,
                                       title: item.title,
                                       subtitle: item.assignedDate.map { AppDateFormat.monthDay($0) },
                                       selecting: selecting, isSelected: selected.contains(item.id),
                                       onTap: { if selecting { toggleSelected(item.id) } else { taskRoute = TaskRoute(id: item.id) } })
                        }
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 20).padding(.top, 8)
                .rowGestures(rows)
            }
            .scrollDisabled(rows.isInteracting)
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .overlay {
            if showMove {
                MoveToProjectPopup(projects: projects.filter { $0.id != project?.id },
                                   onPick: moveSelected, onCancel: { showMove = false })
            }
        }
        .navigationDestination(isPresented: $pushEditorForNew) {
            BacklogTaskDetailView(item: nil, startInEdit: true, defaultProject: project)
        }
        .navigationDestination(item: $taskRoute) { r in
            if let item = allItems.first(where: { $0.id == r.id }) {
                BacklogTaskDetailView(item: item, startInEdit: false)
            }
        }
    }

    private func toggleSelected(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            BackChevronButton { dismiss() }
            Spacer()
            if selecting {
                BacklogBarButton(icon: "arrow.right.arrow.left") { if !selected.isEmpty { showMove = true } }
                BacklogBarButton(icon: "trash", tint: .red) { deleteSelected() }
                BacklogTextBarButton(title: "Done") { selecting = false; selected = [] }
            } else {
                BacklogBarButton(icon: "plus") { pushEditorForNew = true }
                BacklogTextBarButton(title: "Select") { selecting = true }
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
        .topBarFrost()                                       // [#47]
    }

    private func deleteSelected() {
        for item in allItems where selected.contains(item.id) { try? repo.delete(item) }
        selected = []; selecting = false
    }
    private func moveSelected(to destination: ProjectBucket?) {
        try? repo.move(allItems.filter { selected.contains($0.id) }, to: destination)
        showMove = false; selected = []; selecting = false
    }
}
