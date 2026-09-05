import XCTest
@testable import ADultingHD

final class HouseholdMergeTests: XCTestCase {
    private func task(_ name: String, supplies: [String]) -> HouseholdTask {
        HouseholdTask(id: UUID(), name: name, description: "", category: .general, frequency: .unscheduled,
                      estimatedMinutes: 15, difficulty: .medium, supplies: supplies, isActive: true)
    }

    func testMergePreservesDestinationStockFiltersPrivateSuppliesAndKeepsValidAssignees() {
        let memberID = UUID()
        var shared = task("Shared chore", supplies: ["Soap", "Sponges"])
        shared.defaultAssigneeId = memberID
        var personal = task("Personal chore", supplies: ["Private medicine"])
        personal.isPersonal = true
        let tombstoned = task("Formerly shared chore", supplies: ["Private journal"])
        let result = HouseholdMerge(
            sourceTasks: [shared, personal, tombstoned, shared],
            sourceStock: ["Soap": .out, "Sponges": .low, "Private medicine": .out, "Private journal": .low, "Unused": .out],
            destinationTasks: [],
            destinationStock: ["Soap": .inStock, "Destination supply": .low],
            destinationMemberIDs: [memberID], privateTaskIDs: [tombstoned.id]
        )

        XCTAssertEqual(result.tasks.map(\.id), [shared.id])
        XCTAssertEqual(result.addedTasks.map(\.id), [shared.id])
        XCTAssertEqual(result.tasks.first?.defaultAssigneeId, memberID)
        XCTAssertEqual(result.supplyStock, ["Soap": .inStock, "Sponges": .low, "Destination supply": .low])
        XCTAssertNil(result.supplyStock["Private medicine"])
        XCTAssertNil(result.supplyStock["Private journal"])
        XCTAssertNil(result.supplyStock["Unused"])
    }

    func testRetryKeepsDestinationEditsAndDoesNotAddDuplicates() {
        let source = task("Source wording", supplies: ["Soap"])
        let first = HouseholdMerge(sourceTasks: [source], sourceStock: ["Soap": .low], destinationTasks: [],
                                   destinationStock: [:], destinationMemberIDs: [])
        var edited = first.tasks[0]
        edited.name = "Edited in the shared home"
        let retry = HouseholdMerge(sourceTasks: [source], sourceStock: ["Soap": .out], destinationTasks: [edited],
                                   destinationStock: first.supplyStock, destinationMemberIDs: [])

        XCTAssertEqual(retry.tasks.map(\.id), [source.id])
        XCTAssertEqual(retry.tasks.first?.name, "Edited in the shared home")
        XCTAssertTrue(retry.addedTasks.isEmpty)
        XCTAssertEqual(retry.supplyStock, ["Soap": .low])
    }

    func testEmptyMergePreservesDestinationExactly() {
        let destination = task("Existing chore", supplies: ["Soap"])
        let result = HouseholdMerge(sourceTasks: [], sourceStock: ["Unrelated": .out],
                                    destinationTasks: [destination], destinationStock: ["Soap": .low],
                                    destinationMemberIDs: [])
        XCTAssertEqual(result.tasks.map(\.id), [destination.id])
        XCTAssertTrue(result.addedTasks.isEmpty)
        XCTAssertEqual(result.supplyStock, ["Soap": .low])
    }
}
