import XCTest
@testable import ADultingHD

/// Coverage for `DataStore` task-mutation methods that don't fit the pure
/// `HouseholdTask`/`Recurrence` model tests (`ModelTests`, `RecurrenceTests`)
/// or the `TaskStore` round-trip tests (`StorageTests`) — specifically
/// `rescheduleTask` (the drag-to-reschedule entry point, issue #25) and its
/// interaction with a real schedule edit made afterward via `updateTask`.
@MainActor
final class DataStoreTests: XCTestCase {

    /// A fixed, UTC-based calendar so weekday math doesn't depend on the
    /// machine running the test — matches `RecurrenceTests`' fixture.
    private let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeTask(frequency: TaskFrequency = .weekly, scheduledWeekdays: [Int] = [Weekday.monday.rawValue], createdAt: Date = Date()) -> HouseholdTask {
        var task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: frequency, estimatedMinutes: 10, difficulty: .easy,
            supplies: [], isActive: true
        )
        task.scheduledWeekdays = scheduledWeekdays
        task.createdAt = createdAt
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

    // MARK: - rescheduleTask (the drag-to-reschedule entry point)

    func testRescheduleTaskSetsOverrideForDifferentDay() async {
        let dataStore = DataStore()
        // Created Monday, scheduled for Monday: first occurrence is that Monday.
        let monday = utcDate(2024, 3, 4)
        let task = makeTask(scheduledWeekdays: [Weekday.monday.rawValue], createdAt: monday)
        dataStore.tasks = [task]

        let wednesday = utcDate(2024, 3, 6)
        await dataStore.rescheduleTask(task, to: wednesday, on: monday, calendar: utc)

        XCTAssertEqual(dataStore.tasks.first?.scheduledOverrideDate, utc.startOfDay(for: wednesday))
        // The underlying recurring schedule is untouched.
        XCTAssertEqual(dataStore.tasks.first?.scheduledWeekdays, [Weekday.monday.rawValue])
    }

    func testRescheduleTaskOntoCurrentOccurrenceDayIsNoOp() async {
        let dataStore = DataStore()
        let monday = utcDate(2024, 3, 4)
        let task = makeTask(scheduledWeekdays: [Weekday.monday.rawValue], createdAt: monday)
        dataStore.tasks = [task]

        // Dropping the task back onto the day it's already occurring on
        // should not create an override at all.
        await dataStore.rescheduleTask(task, to: monday, on: monday, calendar: utc)

        XCTAssertNil(dataStore.tasks.first?.scheduledOverrideDate)
    }

    func testRescheduleTaskOntoTodayIsNoOpForOverdueTaskShownViaCarryForward() async {
        let dataStore = DataStore()
        // Scheduled for Monday 3/4, never completed — that Monday is its
        // fixed occurrence. Ten days later it's well overdue and shown on
        // "today"'s card via carry-forward, not because today IS 3/4.
        let occurrenceDay = utcDate(2024, 3, 4)
        let today = utcDate(2024, 3, 14)
        let task = makeTask(scheduledWeekdays: [Weekday.monday.rawValue], createdAt: occurrenceDay)
        dataStore.tasks = [task]

        // Dragging the task and dropping it back onto the "today" card it's
        // already carried forward into should be a no-op, exactly like
        // dropping it back onto its raw occurrence day.
        await dataStore.rescheduleTask(task, to: today, on: today, calendar: utc)

        XCTAssertNil(dataStore.tasks.first?.scheduledOverrideDate)
    }

    func testRescheduleTaskRejectsDateBeforeToday() async {
        let dataStore = DataStore()
        let occurrenceDay = utcDate(2024, 3, 4)
        let today = utcDate(2024, 3, 14)
        let task = makeTask(scheduledWeekdays: [Weekday.monday.rawValue], createdAt: occurrenceDay)
        dataStore.tasks = [task]

        // The week view lets you browse past weeks via the date picker, but
        // rescheduling into the past isn't a supported drop target.
        let pastDay = utcDate(2024, 3, 10)
        await dataStore.rescheduleTask(task, to: pastDay, on: today, calendar: utc)

        XCTAssertNil(dataStore.tasks.first?.scheduledOverrideDate)
    }
}
