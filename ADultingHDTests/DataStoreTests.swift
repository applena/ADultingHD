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

    func testMergeCloudTasksPreservesLocalRecurrenceMetadata() {
        let createdAt = utcDate(2024, 3, 4)
        var localTask = makeTask(createdAt: createdAt)
        localTask.scheduledOverrideDate = utcDate(2024, 3, 6)

        var cloudTask = localTask
        cloudTask.name = "Cloud name"
        cloudTask.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        cloudTask.scheduledOverrideDate = nil

        let merged = DataStore.mergeCloudTasks([cloudTask], preserving: [localTask])

        XCTAssertEqual(merged.first?.name, "Cloud name")
        XCTAssertEqual(merged.first?.createdAt, createdAt)
        XCTAssertEqual(merged.first?.scheduledOverrideDate, localTask.scheduledOverrideDate)
    }

    // `completeTask`'s daily/weekly/monthly consistency bonuses gate on
    // "already awarded" flags in the real `UserDefaults.standard` (there's
    // no injectable store), keyed by today's/this week's/this month's date —
    // so a flag left over from an earlier test run *today* would silently
    // suppress a bonus this run expects, and a bonus this run awards would
    // leak into a later run today. Clear them before and after every test in
    // this file so completeTask/uncompleteTask coverage is deterministic
    // regardless of when or how many times the suite has already run today.
    override func setUp() {
        super.setUp()
        clearPeriodBonusFlags()
    }

    override func tearDown() {
        clearPeriodBonusFlags()
        super.tearDown()
    }

    // `nonisolated` because it only touches `UserDefaults.standard` (thread-safe,
    // no actor affinity), letting `setUp()`/`tearDown()` call it synchronously
    // from XCTestCase's nonisolated hooks without hopping onto the main actor.
    private nonisolated func clearPeriodBonusFlags() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("bonus_awarded_") {
            defaults.removeObject(forKey: key)
        }
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

    func testSeedOnboardingTasksKeepsSelectedCatalogAndCustomTasks() async throws {
        let dataStore = DataStore()
        let customTask = try XCTUnwrap(makeOnboardingCustomTask(named: "Polish the moon"))

        await dataStore.seedOnboardingTasks(
            recommendedTasks: [taskCatalog[0]],
            customTasks: [customTask]
        )

        XCTAssertEqual(dataStore.tasks.map(\.name), [taskCatalog[0].name, "Polish the moon"])
        XCTAssertNil(dataStore.tasks.last?.room)
        XCTAssertEqual(dataStore.tasks.last?.frequency, .unscheduled)
        XCTAssertNil(dataStore.tasks.last?.nextOccurrence())
    }

    func testCompletingUnscheduledTaskRecordsProgressWithoutMakingItDue() async throws {
        let dataStore = DataStore()
        let task = try XCTUnwrap(makeOnboardingCustomTask(named: "Call the landlord"))
        dataStore.tasks = [task]

        await dataStore.completeTask(task)

        XCTAssertEqual(dataStore.completions.filter { $0.taskId == task.id }.count, 1)
        XCTAssertEqual(dataStore.tasks.first?.lastCompleted.map { Calendar.current.isDateInToday($0) }, true)
        XCTAssertFalse(dataStore.dueTasks.contains { $0.id == task.id })
    }

    func testUnscheduledTaskDoesNotBlockRecurringConsistencyBonuses() async throws {
        let dataStore = DataStore()
        let recurringTask = makeTask(frequency: .daily)
        let unscheduledTask = try XCTUnwrap(makeOnboardingCustomTask(named: "Organize someday"))
        dataStore.tasks = [recurringTask, unscheduledTask]

        await dataStore.completeTask(recurringTask)

        let completion = try XCTUnwrap(dataStore.completions.first)
        XCTAssertEqual(Set(completion.periodBonuses?.keys.map { $0 } ?? []), ["daily", "weekly", "monthly"])
        XCTAssertFalse(dataStore.completions.contains { $0.taskId == unscheduledTask.id })
    }

    func testCompletingOnlyUnscheduledWorkDoesNotAwardConsistencyBonuses() async throws {
        let dataStore = DataStore()
        let task = try XCTUnwrap(makeOnboardingCustomTask(named: "Organize someday"))
        dataStore.tasks = [task]

        await dataStore.completeTask(task)

        XCTAssertNil(dataStore.completions.first?.periodBonuses)
    }

    func testCompletingOneTimeDueWorkAwardsOnlyTheDailyClearBonus() async throws {
        let dataStore = DataStore()
        var task = try XCTUnwrap(makeOnboardingCustomTask(named: "Call the landlord"))
        task.scheduledOverrideDate = Date()
        dataStore.tasks = [task]

        await dataStore.completeTask(task)

        XCTAssertEqual(
            Set(dataStore.completions.first?.periodBonuses?.keys.map { $0 } ?? []),
            ["daily"]
        )
        XCTAssertNil(dataStore.tasks.first?.scheduledOverrideDate)
    }

    func testRoomGroupingDeduplicatesCaseAndDiacriticVariants() {
        let dataStore = DataStore()
        var first = makeTask()
        first.room = "Café"
        var second = makeTask()
        second.room = "cafe"
        dataStore.tasks = [first, second]

        XCTAssertEqual(dataStore.tasksByRoom.count, 1)
        XCTAssertEqual(dataStore.tasksByRoom.values.first?.count, 2)
        XCTAssertEqual(HouseholdTask.distinctRooms(["Kitchen", "kitchen", nil]), ["Kitchen"])
    }

    func testAddingPersonalTaskAssignsItToCurrentProfile() async {
        let dataStore = DataStore()
        var task = makeTask()
        task.isPersonal = true
        task.defaultAssigneeId = UUID()

        await dataStore.addCustomTask(task)

        XCTAssertEqual(dataStore.tasks.first?.defaultAssigneeId, dataStore.profile.id)
        XCTAssertTrue(dataStore.tasks.first?.isPersonal == true)
    }

    func testUpdatingPersonalTaskCannotAssignItToHousemate() async {
        let dataStore = DataStore()
        let original = makeTask()
        dataStore.tasks = [original]

        var updated = original
        updated.isPersonal = true
        updated.defaultAssigneeId = UUID()
        await dataStore.updateTask(updated)

        XCTAssertEqual(dataStore.tasks.first?.defaultAssigneeId, dataStore.profile.id)
    }

    func testPersonalTaskOwnershipSurvivesTaskDeletion() async throws {
        let dataStore = DataStore()
        await dataStore.createHousehold(name: "Personal task test")

        var task = makeTask()
        task.isPersonal = true
        await dataStore.addCustomTask(task)
        let storedTask = try XCTUnwrap(dataStore.tasks.first)

        await dataStore.deleteTask(storedTask)

        let household = try XCTUnwrap(dataStore.listHouseholds().first)
        XCTAssertTrue(household.personalTaskIDs.contains(task.id))
    }

    func testReturningPersonalTaskToHouseholdScopeReleasesOwnership() async throws {
        let dataStore = DataStore()
        await dataStore.createHousehold(name: "Scope transition test")

        var task = makeTask()
        task.isPersonal = true
        await dataStore.addCustomTask(task)
        var householdTask = try XCTUnwrap(dataStore.tasks.first)
        XCTAssertTrue(dataStore.listHouseholds().first?.personalTaskIDs.contains(task.id) == true)

        householdTask.isPersonal = false
        await dataStore.updateTask(householdTask)

        let household = try XCTUnwrap(dataStore.listHouseholds().first)
        XCTAssertFalse(household.personalTaskIDs.contains(task.id))
        XCTAssertTrue(household.pendingPersonalTaskReleases.contains(task.id))
        XCTAssertFalse(dataStore.tasks.first?.isPersonal == true)
    }

    func testResolveNameClashUsesTrimmedCaseInsensitiveComparison() async {
        let dataStore = DataStore()
        dataStore.pendingNameClash = DataStore.NameClash(
            householdName: "Maple House",
            existingNames: ["Alex"],
            currentName: "Player"
        )

        await dataStore.resolveNameClash(with: "  aLeX  ")
        XCTAssertNotNil(dataStore.pendingNameClash)

        await dataStore.resolveNameClash(with: "Taylor")
        XCTAssertNil(dataStore.pendingNameClash)
        XCTAssertEqual(dataStore.profile.name, "Taylor")
    }

    // MARK: - completeTask / uncompleteTask (Dashboard's Completed Tasks undo, issue #16)

    func testUncompleteTaskReversesXPCoinsAndCompletionCount() async {
        let dataStore = DataStore()
        let task = makeTask(frequency: .daily)
        // A second, never-completed due task keeps `dueTasks` non-empty so
        // completing `task` doesn't also trigger the daily consistency
        // bonus (see `testUncompleteTaskReversesPeriodBonus...` below) —
        // this test is only about the base per-completion XP/coins/count.
        var decoy = makeTask(frequency: .daily)
        decoy.name = "Decoy — stays due"
        dataStore.tasks = [task, decoy]

        await dataStore.completeTask(task)
        let completion = try! XCTUnwrap(dataStore.completions.first)
        let xpAfterComplete = dataStore.profile.totalXP
        let coinsAfterComplete = dataStore.profile.coins
        XCTAssertEqual(xpAfterComplete, completion.totalXP)
        XCTAssertEqual(dataStore.profile.totalTasksCompleted, 1)
        XCTAssertNil(completion.periodBonuses)

        await dataStore.uncompleteTask(completion)

        XCTAssertTrue(dataStore.completions.isEmpty)
        XCTAssertEqual(dataStore.profile.totalXP, xpAfterComplete - completion.totalXP)
        XCTAssertEqual(dataStore.profile.coins, coinsAfterComplete - completion.totalXP)
        XCTAssertEqual(dataStore.profile.totalTasksCompleted, 0)
        XCTAssertNil(dataStore.tasks.first?.lastCompleted)
    }

    func testUncompleteTaskReversesPeriodBonusesAndAllowsReearningThem() async {
        let dataStore = DataStore()
        let task = makeTask(frequency: .daily)
        dataStore.tasks = [task]

        // Completing the household's only active task simultaneously clears
        // the day, the week, and the month, earning all three consistency
        // bonuses on top of the completion's own XP — this is the exact
        // scenario issue #16's review turned up as a permanent XP leak:
        // undoing this completion must claw every one of those bonuses back
        // too, not just the completion's own XP.
        await dataStore.completeTask(task)
        let completion = try! XCTUnwrap(dataStore.completions.first)
        let periodBonuses = try! XCTUnwrap(completion.periodBonuses)
        XCTAssertEqual(Set(periodBonuses.keys), ["daily", "weekly", "monthly"])
        let periodBonusTotal = periodBonuses.values.reduce(0, +)
        XCTAssertGreaterThan(periodBonusTotal, 0)
        let xpAfterComplete = dataStore.profile.totalXP
        XCTAssertEqual(xpAfterComplete, completion.totalXP + periodBonusTotal)

        await dataStore.uncompleteTask(completion)

        XCTAssertEqual(dataStore.profile.totalXP, xpAfterComplete - completion.totalXP - periodBonusTotal)

        // Every "already awarded" gate must also be cleared — otherwise
        // completing the task again for real would silently grant none of
        // these bonuses.
        await dataStore.completeTask(task)
        let secondCompletion = try! XCTUnwrap(dataStore.completions.first)
        XCTAssertEqual(secondCompletion.periodBonuses?.values.reduce(0, +), periodBonusTotal)
    }

    func testUncompleteTaskUnwindsStreakWhenItWasTodaysOnlyCompletion() async {
        let dataStore = DataStore()
        let task = makeTask(frequency: .daily)
        dataStore.tasks = [task]

        await dataStore.completeTask(task)
        XCTAssertEqual(dataStore.profile.currentStreak, 1)
        let completion = try! XCTUnwrap(dataStore.completions.first)

        await dataStore.uncompleteTask(completion)

        XCTAssertEqual(dataStore.profile.currentStreak, 0)
        XCTAssertNil(dataStore.profile.lastActiveDate)
    }

    func testUncompleteTaskLeavesStreakAloneWhenOtherCompletionsRemainToday() async {
        let dataStore = DataStore()
        let taskA = makeTask(frequency: .daily)
        var taskB = makeTask(frequency: .daily)
        taskB.name = "Task B"
        dataStore.tasks = [taskA, taskB]

        await dataStore.completeTask(taskA)
        await dataStore.completeTask(taskB)
        XCTAssertEqual(dataStore.profile.currentStreak, 1)

        let completionA = try! XCTUnwrap(dataStore.completions.first { $0.taskId == taskA.id })
        await dataStore.uncompleteTask(completionA)

        // Task B is still completed today, so today still counts as active.
        XCTAssertEqual(dataStore.profile.currentStreak, 1)
        XCTAssertEqual(dataStore.completions.count, 1)
    }

    // MARK: - CloudKit cleanup gating (householdCloudKitCleanupTargets)
    //
    // This decision — which households need CloudKit cleanup before local
    // deletion — has been wrong three times: first gating on the device-wide
    // `isHouseholdSharingEnabled` flag alone (blocks deleting any OTHER,
    // never-shared household behind a flag that never clears), then gating
    // on `household.shareRecordName != nil` alone (silently skips cleanup
    // for households shared under a pre-this-feature build, which never
    // persisted that field — stranding a real collaborator), then narrowing
    // the fallback to `isHouseholdSharingEnabled` again (that flag is local
    // UserDefaults, not synced via iCloud, so a second device or a reinstall
    // starts with it unset even for a household genuinely shared elsewhere —
    // same stranding bug, different trigger). Tested here directly against
    // the pure function, not through `deleteHousehold`, because the
    // ambiguous case legitimately calls `ckSync.setup()`, which traps on an
    // unsigned test build — see `CloudKitIntegrationTests`.

    func testCloudKitCleanupTargetsFlagsUnconfirmedOwnedHouseholdsAsAmbiguousRegardlessOfDeviceFlag() async {
        let dataStore = DataStore()
        await dataStore.createHousehold(name: "First")
        await dataStore.createHousehold(name: "Second")
        let households = dataStore.listHouseholds()
        XCTAssertEqual(households.count, 2)

        // isHouseholdSharingEnabled is per-device UserDefaults and is never
        // set here — but it must NOT gate whether the ambiguous check even
        // happens: a household actually shared from another device (or
        // under a pre-this-feature build) would read exactly this same
        // local state, so both households must land in `ambiguous` for
        // `removeCloudKitDataBeforeLocalDeletion`'s best-effort check to
        // ever get a chance to run.
        let targets = dataStore.householdCloudKitCleanupTargets(from: households)
        XCTAssertTrue(targets.confirmed.isEmpty)
        XCTAssertEqual(Set(targets.ambiguous.map(\.id)), Set(households.map(\.id)))
    }

    func testCloudKitCleanupTargetsConfirmsHouseholdWithShareRecordNameWithoutAmbiguity() async throws {
        let dataStore = DataStore()
        await dataStore.createHousehold(name: "First")
        var household = try XCTUnwrap(dataStore.listHouseholds().first)
        household.shareRecordName = "cloudkit.share.record"

        let targets = dataStore.householdCloudKitCleanupTargets(from: [household])
        XCTAssertEqual(targets.confirmed.map(\.id), [household.id])
        XCTAssertTrue(targets.ambiguous.isEmpty)
    }

    func testCloudKitCleanupTargetsConfirmsJoinedHouseholdWithoutAmbiguity() async {
        let dataStore = DataStore()
        // A joined household only exists because it was shared with this
        // device — cleanup always applies, with no dependence on
        // shareRecordName or the device-wide sharing flag.
        let joined = Household.newJoined(
            name: "Shared", members: [], zoneName: "Household-owner-zone", ownerUserRecordName: "owner"
        )

        let targets = dataStore.householdCloudKitCleanupTargets(from: [joined])
        XCTAssertEqual(targets.confirmed.map(\.id), [joined.id])
        XCTAssertTrue(targets.ambiguous.isEmpty)
    }
}
