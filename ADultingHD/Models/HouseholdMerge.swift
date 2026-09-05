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
        var additions: [HouseholdTask] = []
        for var task in sourceTasks where !task.isPersonal && !privateTaskIDs.contains(task.id) {
            guard knownIDs.insert(task.id).inserted else { continue }
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
