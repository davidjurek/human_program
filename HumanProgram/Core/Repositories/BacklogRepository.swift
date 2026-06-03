import Foundation
import SwiftData

@MainActor
public final class BacklogRepository {
    private let context: ModelContext
    private let maintenance = BacklogMaintenanceService()
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - CRUD

    /// Create a new backlog item.
    @discardableResult
    public func create(
        title: String,
        notes: String = "",
        project: ProjectBucket? = nil,
        assignedDate: Date? = nil
    ) throws -> BacklogItem {
        let item = BacklogItem(title: title)
        item.notes = notes
        item.project = project
        item.assignedDate = assignedDate.map { calendar.dayStart($0) }
        context.insert(item)
        try context.save()
        return item
    }

    /// Set all editable fields of an item in one save. `project`/`assignedDate` are set
    /// exactly as given — passing nil CLEARS the field (the edit form always supplies the
    /// full current state). Bumps `updatedAt`.
    public func setDetails(
        _ item: BacklogItem,
        title: String,
        notes: String,
        project: ProjectBucket?,
        assignedDate: Date?
    ) throws {
        item.title = title
        item.notes = notes
        item.project = project
        item.assignedDate = assignedDate.map { calendar.dayStart($0) }
        item.updatedAt = Date()
        try context.save()
    }

    /// Move items into a project bucket (nil = Unorganized). Bumps `updatedAt`.
    public func move(_ items: [BacklogItem], to destination: ProjectBucket?) throws {
        for item in items {
            item.project = destination
            item.updatedAt = Date()
        }
        try context.save()
    }

    /// Delete a backlog item.
    public func delete(_ item: BacklogItem) throws {
        context.delete(item)
        try context.save()
    }

    // MARK: - Fetch

    /// Fetch active items (status == .backlog).
    /// SwiftData #Predicate enum comparisons are unreliable — fetch all and filter in memory.
    /// TODO [#68]: at scale, store status as a raw String and filter in the store via
    /// a #Predicate. Left as-is for now (needs a migration + a verifying test first).
    public func fetchActive() throws -> [BacklogItem] {
        let all = try fetchAll()
        return all.filter { $0.status == .backlog }
    }

    /// Fetch all items including done.
    public func fetchAll() throws -> [BacklogItem] {
        try context.fetchSorted(by: [SortDescriptor(\.createdAt, order: .forward)])
    }

    // MARK: - Projects

    /// Create a new project bucket.
    @discardableResult
    public func createProject(name: String) throws -> ProjectBucket {
        let project = ProjectBucket(name: name)
        context.insert(project)
        try context.save()
        return project
    }

    /// Delete a project, optionally moving its items to another project bucket.
    public func deleteProject(_ project: ProjectBucket, moveItemsTo destination: ProjectBucket? = nil) throws {
        // Re-assign items before deletion so they are not null-ified unintentionally.
        for item in project.items {
            item.project = destination
            item.updatedAt = Date()
        }
        context.delete(project)
        try context.save()
    }

    /// Fetch all project buckets.
    public func fetchProjects() throws -> [ProjectBucket] {
        try context.fetchSorted(by: [SortDescriptor(\.name, order: .forward)])
    }

    // MARK: - Maintenance

    /// Clear overdue assignments (call on app startup).
    public func clearOverdueAssignments(today: Date) throws {
        let allItems = try fetchAll()
        maintenance.clearOverdueAssignments(items: allItems, today: today)
        try context.save()
    }

    // MARK: - Status Sync

    /// Mark a backlog item as done.
    public func markDone(_ item: BacklogItem) throws {
        item.status = .done
        item.updatedAt = Date()
        try context.save()
    }

    /// Mark a backlog item as backlog (undo done).
    public func markBacklog(_ item: BacklogItem) throws {
        item.status = .backlog
        item.updatedAt = Date()
        try context.save()
    }
}
