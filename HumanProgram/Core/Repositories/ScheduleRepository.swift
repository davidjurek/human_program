import Foundation
import SwiftData

// A conflict detected between two enabled schedule templates.
public struct ScheduleConflict: Sendable {
    public let conflictingTemplateName: String
    public let reason: String

    public init(conflictingTemplateName: String, reason: String) {
        self.conflictingTemplateName = conflictingTemplateName
        self.reason = reason
    }
}

@MainActor
public final class ScheduleRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - fetchAll

    /// Fetch all schedule templates sorted by name.
    public func fetchAll() throws -> [ScheduleTemplate] {
        let descriptor = FetchDescriptor<ScheduleTemplate>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - create

    /// Create a new schedule template with the Sleep block pre-inserted.
    @discardableResult
    public func create(name: String) throws -> ScheduleTemplate {
        let template = ScheduleTemplate(name: name)
        template.blocks = [Self.defaultSleepBlock()]
        context.insert(template)
        try context.save()
        return template
    }

    // MARK: - save

    /// Persist changes to an existing template after running conflict detection.
    /// Returns a ScheduleConflict if the template would conflict with another enabled template.
    /// Does NOT save if a conflict is found — caller retains the unsaved state.
    public func save(_ template: ScheduleTemplate) throws -> ScheduleConflict? {
        // Normalise blocks before saving.
        normalizeBlocks(in: template)

        // Only run conflict detection when the template is enabled.
        if template.isEnabled {
            let allTemplates = try fetchAll()
            if let conflict = detectConflict(for: template, among: allTemplates) {
                return conflict
            }
        }

        template.updatedAt = Date()
        try context.save()
        return nil
    }

    // MARK: - delete

    /// Delete a schedule template from the store.
    public func delete(_ template: ScheduleTemplate) throws {
        context.delete(template)
        try context.save()
    }

    // MARK: - addBlock

    /// Add a new block to a template, maintaining the Sleep-first invariant.
    /// If the template has no blocks yet, a Sleep block is inserted first.
    /// The new block starts where the last block ends.
    public func addBlock(
        title: String,
        durationMinutes: Int,
        to template: ScheduleTemplate
    ) throws {
        // Ensure there is at least a Sleep block.
        if template.blocks.isEmpty {
            template.blocks.append(Self.defaultSleepBlock())
        }

        let lastBlock = template.blocks.sorted { $0.sortOrder < $1.sortOrder }.last!
        let startMinute = lastBlock.endMinuteOfDay
        let endMinute = (startMinute + durationMinutes) % 1440
        let nextSortOrder = lastBlock.sortOrder + 1

        let newBlock = ScheduleBlock(
            title: title,
            startMinuteOfDay: startMinute,
            endMinuteOfDay: endMinute,
            sortOrder: nextSortOrder
        )
        template.blocks.append(newBlock)
        normalizeBlocks(in: template)
        template.updatedAt = Date()
        try context.save()
    }

    // MARK: - updateSleepBlock

    /// Update the Sleep block's bed time and wake time (both expressed as minutes from midnight).
    /// The Sleep block always spans from bedtimeMinute to wakeMinute (overnight is allowed).
    public func updateSleepBlock(
        in template: ScheduleTemplate,
        bedtimeMinute: Int,
        wakeMinute: Int
    ) throws {
        guard let sleepIndex = template.blocks.firstIndex(where: { $0.title == "Sleep" }) else {
            // No Sleep block — insert one then update.
            let sleep = ScheduleBlock(
                title: "Sleep",
                startMinuteOfDay: bedtimeMinute,
                endMinuteOfDay: wakeMinute,
                sortOrder: 0
            )
            template.blocks.insert(sleep, at: 0)
            normalizeBlocks(in: template)
            template.updatedAt = Date()
            try context.save()
            return
        }

        template.blocks[sleepIndex].startMinuteOfDay = bedtimeMinute
        template.blocks[sleepIndex].endMinuteOfDay = wakeMinute
        normalizeBlocks(in: template)
        template.updatedAt = Date()
        try context.save()
    }

    // MARK: - deleteBlock

    /// Delete a non-Sleep block from a template.
    /// Attempting to delete the Sleep block is a no-op (enforced silently).
    public func deleteBlock(_ block: ScheduleBlock, from template: ScheduleTemplate) throws {
        guard block.title != "Sleep" else { return }
        template.blocks.removeAll { $0.id == block.id }
        normalizeBlocks(in: template)
        template.updatedAt = Date()
        try context.save()
    }

    // MARK: - reorderBlocks

    /// Reorder non-Sleep blocks within a template.
    /// Accepts the caller's desired order for non-Sleep blocks only.
    /// Recomputes all start/end times preserving each block's duration.
    /// The Sleep block always stays first.
    public func reorderBlocks(
        _ nonSleepBlocks: [ScheduleBlock],
        in template: ScheduleTemplate
    ) throws {
        // Pull out the Sleep block (must stay at position 0).
        guard let sleepBlock = template.blocks.first(where: { $0.title == "Sleep" }) else {
            // No Sleep block — just assign the passed-in order and normalize.
            template.blocks = nonSleepBlocks.enumerated().map { idx, block in
                var b = block
                b.sortOrder = idx + 1
                return b
            }
            normalizeBlocks(in: template)
            template.updatedAt = Date()
            try context.save()
            return
        }

        // Rebuild blocks array: Sleep first, then non-Sleep in the new order.
        var newBlocks: [ScheduleBlock] = [sleepBlock]
        for (index, block) in nonSleepBlocks.enumerated() {
            var b = block
            b.sortOrder = index + 1
            newBlocks.append(b)
        }
        template.blocks = newBlocks
        normalizeBlocks(in: template)
        template.updatedAt = Date()
        try context.save()
    }

    // MARK: - updateBlock

    /// Update a block's title and/or duration by its id.
    /// Passing nil for a parameter leaves that field unchanged.
    /// After updating duration, start/end times are recomputed via normalizeBlocks.
    public func updateBlock(
        _ blockId: String,
        title: String? = nil,
        durationMinutes: Int? = nil,
        in template: ScheduleTemplate
    ) throws {
        guard let index = template.blocks.firstIndex(where: { $0.id == blockId }) else { return }

        // Cannot rename or change duration of the Sleep block via this method.
        // Sleep block is managed through updateSleepBlock.
        guard template.blocks[index].title != "Sleep" || title == nil else { return }

        if let title = title {
            template.blocks[index].title = title
        }
        if let duration = durationMinutes {
            // Recompute endMinuteOfDay from startMinuteOfDay + new duration.
            // normalizeBlocks will cascade start times for subsequent blocks.
            let start = template.blocks[index].startMinuteOfDay
            template.blocks[index].endMinuteOfDay = (start + duration) % 1440
        }

        normalizeBlocks(in: template)
        template.updatedAt = Date()
        try context.save()
    }

    // MARK: - Private Helpers

    /// Ensure Sleep is first (sortOrder 0), then recompute start times cascading from wake time.
    private func normalizeBlocks(in template: ScheduleTemplate) {
        guard !template.blocks.isEmpty else { return }

        // Sort current blocks: Sleep first, then by sortOrder.
        var sorted = template.blocks.sorted { lhs, rhs in
            if lhs.title == "Sleep" { return true }
            if rhs.title == "Sleep" { return false }
            return lhs.sortOrder < rhs.sortOrder
        }

        // Guarantee Sleep is present at index 0.
        if sorted.first?.title != "Sleep" {
            let sleep = Self.defaultSleepBlock()
            sorted.insert(sleep, at: 0)
        }

        // Assign sortOrders.
        for i in sorted.indices {
            sorted[i].sortOrder = i
        }

        // Cascade start/end times from the wake time of the Sleep block forward.
        // Sleep block keeps its own start/end (bed time → wake time).
        // Each subsequent block starts where the previous one ended.
        if sorted.count > 1 {
            let wakeMinute = sorted[0].endMinuteOfDay
            var cursor = wakeMinute
            for i in 1..<sorted.count {
                let duration = sorted[i].durationMinutes
                sorted[i].startMinuteOfDay = cursor
                sorted[i].endMinuteOfDay = (cursor + duration) % 1440
                cursor = sorted[i].endMinuteOfDay
            }
        }

        template.blocks = sorted
    }

    /// Check whether enabling `template` would conflict with any other currently-enabled template.
    /// Returns the first conflict found, or nil if no conflict.
    private func detectConflict(
        for template: ScheduleTemplate,
        among allTemplates: [ScheduleTemplate]
    ) -> ScheduleConflict? {
        let isCustomDate = template.customDateStart != nil

        for other in allTemplates {
            // Skip self.
            guard other.id != template.id else { continue }
            // Only enabled templates can conflict.
            guard other.isEnabled else { continue }

            let otherIsCustomDate = other.customDateStart != nil

            // Rule: custom-date templates and weekday templates do NOT conflict with each other.
            if isCustomDate != otherIsCustomDate { continue }

            if isCustomDate {
                // Both are custom-date templates — conflict if date ranges overlap.
                guard
                    let tStart = template.customDateStart,
                    let tEnd = template.customDateEnd,
                    let oStart = other.customDateStart,
                    let oEnd = other.customDateEnd
                else {
                    continue
                }
                let tStartDay = Calendar.current.startOfDay(for: tStart)
                let tEndDay = Calendar.current.startOfDay(for: tEnd)
                let oStartDay = Calendar.current.startOfDay(for: oStart)
                let oEndDay = Calendar.current.startOfDay(for: oEnd)

                // Ranges overlap if one starts before the other ends.
                let overlaps = tStartDay <= oEndDay && oStartDay <= tEndDay
                if overlaps {
                    return ScheduleConflict(
                        conflictingTemplateName: other.name,
                        reason: "Date range overlaps with \"\(other.name)\"."
                    )
                }
            } else {
                // Both are weekday templates — conflict if any weekday is shared.
                let sharedWeekdays = Set(template.assignedWeekdays)
                    .intersection(Set(other.assignedWeekdays))
                if !sharedWeekdays.isEmpty {
                    let dayNames = sharedWeekdays
                        .sorted()
                        .map { weekdayName(for: $0) }
                        .joined(separator: ", ")
                    return ScheduleConflict(
                        conflictingTemplateName: other.name,
                        reason: "Shares \(dayNames) with \"\(other.name)\"."
                    )
                }
            }
        }

        return nil
    }

    /// Default Sleep block: 21:30 (1290) to 05:30 (330), sortOrder 0.
    private static func defaultSleepBlock() -> ScheduleBlock {
        ScheduleBlock(
            title: "Sleep",
            startMinuteOfDay: 21 * 60 + 30,  // 21:30 = 1290
            endMinuteOfDay: 5 * 60 + 30,     // 05:30 = 330
            sortOrder: 0
        )
    }

    /// Human-readable weekday name for conflict messages. 1=Sun … 7=Sat.
    private func weekdayName(for weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return "Day \(weekday)"
        }
    }
}
