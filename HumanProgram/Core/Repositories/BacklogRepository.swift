import Foundation
import SwiftData

@MainActor
public final class BacklogRepository {
    private let context: ModelContext
    private let maintenance = BacklogMaintenanceService()

    public init(context: ModelContext) {
        self.context = context
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
        item.assignedDate = assignedDate.map { Calendar.current.startOfDay(for: $0) }
        context.insert(item)
        try context.save()
        return item
    }

    /// Update mutable fields on an existing backlog item.
    public func update(
        _ item: BacklogItem,
        title: String? = nil,
        notes: String? = nil,
        project: ProjectBucket? = nil,
        assignedDate: Date? = nil
    ) throws {
        if let title = title { item.title = title }
        if let notes = notes { item.notes = notes }
        // project and assignedDate use explicit optionals; nil means "clear the field"
        // Use a sentinel approach: only change if the parameter was actually supplied.
        // Since Swift optional parameters default to nil, we use overloaded versions below.
        // However, per the signature, both project and assignedDate are optional — meaning
        // passing nil explicitly will NOT clear them; only a non-nil value changes them.
        // If callers need to clear, they should pass an explicit nil via the typed variant.
        // Per the contract in the header, we treat non-nil values as updates.
        if let project = project { item.project = project }
        if let assignedDate = assignedDate {
            item.assignedDate = Calendar.current.startOfDay(for: assignedDate)
        }
        item.updatedAt = Date()
        try context.save()
    }

    /// Delete a backlog item.
    public func delete(_ item: BacklogItem) throws {
        context.delete(item)
        try context.save()
    }

    // MARK: - Fetch

    /// Fetch active items (status == .backlog).
    public func fetchActive() throws -> [BacklogItem] {
        let descriptor = FetchDescriptor<BacklogItem>(
            predicate: #Predicate { $0.status == BacklogStatus.backlog },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetch all items including done.
    public func fetchAll() throws -> [BacklogItem] {
        let descriptor = FetchDescriptor<BacklogItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
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
        let descriptor = FetchDescriptor<ProjectBucket>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try context.fetch(descriptor)
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
