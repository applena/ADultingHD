import Foundation

/// A merge adds missing household chores while preserving destination edits.
/// Stable chore IDs make a retry safe even after a partially completed upload.
struct HouseholdMerge {
    let tasks: [HouseholdTask]
    let addedTasks: [HouseholdTask]
    let supplyStock: [String: SupplyStock]

    init(
        sourceTasks: [HouseholdTask],
        sourceStock: [String: SupplyStock],
        destinationTasks: [HouseholdTask],
        destinationStock: [String: SupplyStock],
        destinationMemberIDs: Set<UUID>,
        privateTaskIDs: Set<UUID> = []
    ) {
        var knownIDs = Set(destinationTasks.map(\.id))
        var knownChores = Set(destinationTasks.map { TaskDuplicates.key(for: $0) })
        var additions: [HouseholdTask] = []
        for var task in sourceTasks where !task.isPersonal && !privateTaskIDs.contains(task.id) {
            guard knownIDs.insert(task.id).inserted else { continue }
            guard knownChores.insert(TaskDuplicates.key(for: task)).inserted else { continue }
            if let assignee = task.defaultAssigneeId, !destinationMemberIDs.contains(assignee) {
                task.defaultAssigneeId = nil
            }
            additions.append(task)
        }
        addedTasks = additions
        tasks = destinationTasks + additions
        let sharedSupplies = Set(sourceTasks.filter {
            !$0.isPersonal && !privateTaskIDs.contains($0.id)
        }.flatMap(\.supplies))
        supplyStock = destinationStock.merging(sourceStock.filter { sharedSupplies.contains($0.key) }) {
            destination, _ in destination
        }
    }
}

/// A chore in a room represents one recurring task, even if it was created
/// independently on two devices before those households were merged.
enum TaskDuplicates {
    static func key(for task: HouseholdTask) -> String {
        let name = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let room = HouseholdTask.roomIdentity(task.room) ?? ""
        return "\(task.isPersonal)|\(room)|\(name)"
    }

    static func groups(in tasks: [HouseholdTask]) -> [[HouseholdTask]] {
        let grouped = Dictionary(grouping: tasks, by: key(for:))
        return grouped.values.filter { $0.count > 1 }
            .sorted { ($0.first?.name ?? "") < ($1.first?.name ?? "") }
    }
}
