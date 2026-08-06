import XCTest
@testable import ADultingHD

/// Coverage for `DataStore` task-mutation methods that don't fit the pure
/// `HouseholdTask`/`Recurrence` model tests (`ModelTests`, `RecurrenceTests`)
/// or the `TaskStore` round-trip tests (`StorageTests`) — specifically the
/// interaction between a manual drag-to-reschedule override and a real
/// schedule edit made afterward (issue #25).
@MainActor
final class DataStoreTests: XCTestCase {

    private func makeTask(frequency: TaskFrequency = .weekly, scheduledWeekdays: [Int] = [Weekday.monday.rawValue]) -> HouseholdTask {
        var task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: frequency, estimatedMinutes: 10, difficulty: .easy,
            supplies: [], isActive: true
        )
        task.scheduledWeekdays = scheduledWeekdays
        return task
    }

    func testUpdateTaskClearsOverrideWhenRecurrenceRuleChanges() async {
        let dataStore = DataStore()
        let original = makeTask()
        dataStore.tasks = [original]

        // Simulate a manual drag-to-reschedule (issue #25): the override is
        // set without touching the recurring schedule.
        var rescheduled = original
        rescheduled.scheduledOverrideDate = Date()
        await dataStore.updateTask(rescheduled)
        XCTAssertNotNil(dataStore.tasks.first?.scheduledOverrideDate)

        // A real schedule edit afterward — changing the scheduled weekday —
        // must supersede the stale override, not silently lose to it.
        var edited = dataStore.tasks[0]
        edited.scheduledWeekdays = [Weekday.friday.rawValue]
        await dataStore.updateTask(edited)

        XCTAssertNil(dataStore.tasks.first?.scheduledOverrideDate, "editing the recurring schedule should clear a stale manual override")
        XCTAssertEqual(dataStore.tasks.first?.scheduledWeekdays, [Weekday.friday.rawValue])
    }

    func testUpdateTaskPreservesOverrideWhenRecurrenceRuleUnchanged() async {
        let dataStore = DataStore()
        let original = makeTask()
        dataStore.tasks = [original]

        var rescheduled = original
        rescheduled.scheduledOverrideDate = Date()
        await dataStore.updateTask(rescheduled)

        // An edit that doesn't touch the recurrence rule (e.g. renaming the
        // task, or `rescheduleTask` itself) should leave the override alone.
        var renamed = dataStore.tasks[0]
        renamed.name = "Renamed"
        await dataStore.updateTask(renamed)

        XCTAssertNotNil(dataStore.tasks.first?.scheduledOverrideDate)
        XCTAssertEqual(dataStore.tasks.first?.name, "Renamed")
    }
}
