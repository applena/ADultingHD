import XCTest
import CloudKit
@testable import ADultingHD

// CKRecord ↔ model round-trip tests. These create CKRecord objects entirely
// in-memory — no CKContainer, no network — so they run in any build
// environment including unsigned CI builds (CODE_SIGNING_ALLOWED=NO).
final class CloudKitRecordTests: XCTestCase {

    private let zone = CKRecordZone(zoneName: "TestZone")

    // MARK: - HouseholdTask

    func testTaskRoundTrip_minimal() {
        let task = HouseholdTask(
            id: UUID(), name: "Wash dishes", description: "Clean all dishes",
            category: .kitchen, frequency: .daily, estimatedMinutes: 20,
            difficulty: .easy, supplies: [], isActive: true
        )
        let record = task.toCKRecord(zone: zone)
        guard let decoded = HouseholdTask(from: record) else {
            XCTFail("decode returned nil"); return
        }
        XCTAssertEqual(decoded.id, task.id)
        XCTAssertEqual(decoded.name, task.name)
        XCTAssertEqual(decoded.description, task.description)
        XCTAssertEqual(decoded.category, task.category)
        XCTAssertEqual(decoded.frequency, task.frequency)
        XCTAssertEqual(decoded.estimatedMinutes, task.estimatedMinutes)
        XCTAssertEqual(decoded.difficulty, task.difficulty)
        XCTAssertEqual(decoded.isActive, true)
        XCTAssertNil(decoded.lastCompleted)
        XCTAssertNil(decoded.defaultAssigneeId)
        XCTAssertFalse(decoded.isPersonal)
        XCTAssertTrue(decoded.scheduledWeekdays.isEmpty)
        XCTAssertTrue(decoded.checklist.isEmpty)
    }

    func testTaskRoundTrip_allOptionalFields() {
        let assigneeId = UUID()
        let checklist = [
            ChecklistItem(id: UUID(), text: "Step 1", instructions: "Do this"),
            ChecklistItem(id: UUID(), text: "Step 2", instructions: "Then that"),
        ]
        var task = HouseholdTask(
            id: UUID(), name: "Mow lawn", description: "Cut the grass",
            category: .outdoor, frequency: .weekly, estimatedMinutes: 45,
            difficulty: .medium, supplies: ["Fuel", "Ear protection"],
            isActive: false, lastCompleted: Date(timeIntervalSince1970: 1_700_000_000)
        )
        task.defaultAssigneeId = assigneeId
        task.isPersonal = true
        task.scheduledWeekdays = [2, 6]
        task.checklist = checklist

        let record = task.toCKRecord(zone: zone)
        guard let decoded = HouseholdTask(from: record) else {
            XCTFail("decode returned nil"); return
        }
        XCTAssertEqual(decoded.supplies, ["Fuel", "Ear protection"])
        XCTAssertEqual(decoded.isActive, false)
        XCTAssertNotNil(decoded.lastCompleted)
        XCTAssertEqual(decoded.defaultAssigneeId, assigneeId)
        XCTAssertTrue(decoded.isPersonal)
        XCTAssertEqual(decoded.scheduledWeekdays, [2, 6])
        XCTAssertEqual(decoded.checklist.count, 2)
        XCTAssertEqual(decoded.checklist[0].text, "Step 1")
        XCTAssertEqual(decoded.checklist[1].instructions, "Then that")
    }

    func testTaskRoundTrip_customRoomAndNoScheduleUsesAdditiveFields() throws {
        var task = HouseholdTask(
            id: UUID(), name: "Sort costumes", description: "",
            category: .general, frequency: .unscheduled, estimatedMinutes: 20,
            difficulty: .medium, supplies: [], isActive: true
        )
        task.room = "Costume Closet"

        let record = task.toCKRecord(zone: zone)
        let decoded = try XCTUnwrap(HouseholdTask(from: record))

        XCTAssertEqual(record["room"] as? String, "Costume Closet")
        XCTAssertEqual(record["category"] as? String, "General")
        XCTAssertEqual(record["scheduleFrequency"] as? String, "No Schedule")
        XCTAssertEqual(record["frequency"] as? String, "Weekly")
        XCTAssertEqual(decoded.room, "Costume Closet")
        XCTAssertEqual(decoded.frequency, .unscheduled)
    }

    func testTaskDecode_legacyUnknownCategoryRemainsReadable() throws {
        let record = CKRecord(
            recordType: RecordType.task,
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID)
        )
        record["name"] = "Sweep the conservatory" as CKRecordValue
        record["category"] = "Conservatory" as CKRecordValue
        record["frequency"] = "Monthly" as CKRecordValue
        record["difficulty"] = Difficulty.easy.rawValue as CKRecordValue

        let decoded = try XCTUnwrap(HouseholdTask(from: record))

        XCTAssertEqual(decoded.room, "Conservatory")
        XCTAssertEqual(decoded.frequency, .monthly)
    }

    func testTaskDecode_prefersLegacyPlanningFieldsWhenOlderClientEditsThem() throws {
        var task = HouseholdTask(
            id: UUID(), name: "Clean studio", description: "",
            category: .office, frequency: .unscheduled, estimatedMinutes: 20,
            difficulty: .medium, supplies: [], isActive: true
        )
        task.room = "Art Studio"
        let record = task.toCKRecord(zone: zone)

        // Simulate a legacy client's `.changedKeys` save. It knows only these
        // fields, so the additive values and their snapshots remain untouched.
        record["category"] = TaskCategory.garage.rawValue as CKRecordValue
        record["frequency"] = TaskFrequency.monthly.rawValue as CKRecordValue

        let decoded = try XCTUnwrap(HouseholdTask(from: record))

        XCTAssertEqual(decoded.room, TaskCategory.garage.rawValue)
        XCTAssertEqual(decoded.frequency, .monthly)
    }

    func testTaskDecode_keepsAdditivePlanningFieldsWhenLegacySnapshotsMatch() throws {
        var task = HouseholdTask(
            id: UUID(), name: "Sort costumes", description: "",
            category: .general, frequency: .unscheduled, estimatedMinutes: 20,
            difficulty: .medium, supplies: [], isActive: true
        )
        task.room = "Costume Closet"

        let decoded = try XCTUnwrap(HouseholdTask(from: task.toCKRecord(zone: zone)))

        XCTAssertEqual(decoded.room, "Costume Closet")
        XCTAssertEqual(decoded.frequency, .unscheduled)
    }

    func testTaskRoundTrip_monthlyScheduledDay() {
        var task = HouseholdTask(
            id: UUID(), name: "Pay bills", description: "",
            category: .office, frequency: .monthly, estimatedMinutes: 30,
            difficulty: .easy, supplies: [], isActive: true
        )
        task.scheduledDayOfMonth = 15
        let decoded = HouseholdTask(from: task.toCKRecord(zone: zone))
        XCTAssertEqual(decoded?.scheduledDayOfMonth, 15)
        XCTAssertNil(decoded?.scheduledMonth)
    }

    func testTaskRoundTrip_yearlyScheduledDayAndMonth() {
        var task = HouseholdTask(
            id: UUID(), name: "Clean gutters", description: "",
            category: .outdoor, frequency: .yearly, estimatedMinutes: 90,
            difficulty: .hard, supplies: [], isActive: true
        )
        task.scheduledDayOfMonth = 1
        task.scheduledMonth = 4
        let decoded = HouseholdTask(from: task.toCKRecord(zone: zone))
        XCTAssertEqual(decoded?.scheduledDayOfMonth, 1)
        XCTAssertEqual(decoded?.scheduledMonth, 4)
    }

    func testTaskRecord_omitsScheduledOverrideDate() {
        var task = HouseholdTask(
            id: UUID(), name: "Vacuum", description: "",
            category: .livingRoom, frequency: .weekly, estimatedMinutes: 15,
            difficulty: .easy, supplies: [], isActive: true
        )
        task.scheduledWeekdays = [Weekday.monday.rawValue]
        task.scheduledOverrideDate = Date(timeIntervalSince1970: 1_700_500_000)

        let decoded = HouseholdTask(from: task.toCKRecord(zone: zone))
        XCTAssertNil(decoded?.scheduledOverrideDate)
        XCTAssertEqual(decoded?.scheduledWeekdays, [Weekday.monday.rawValue])
    }

    func testTaskRoundTrip_nilScheduledOverrideDate() {
        let task = HouseholdTask(
            id: UUID(), name: "Dust shelves", description: "",
            category: .livingRoom, frequency: .weekly, estimatedMinutes: 10,
            difficulty: .easy, supplies: [], isActive: true
        )
        let decoded = HouseholdTask(from: task.toCKRecord(zone: zone))
        XCTAssertNil(decoded?.scheduledOverrideDate)
    }

    func testTaskDecode_missingRequiredField_returnsNil() {
        let record = CKRecord(
            recordType: RecordType.task,
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID)
        )
        XCTAssertNil(HouseholdTask(from: record))
    }

    func testTaskRecordID_usesTaskUUID() {
        let id = UUID()
        let task = HouseholdTask(
            id: id, name: "Test", description: "", category: .general,
            frequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
            supplies: [], isActive: true
        )
        XCTAssertEqual(task.toCKRecord(zone: zone).recordID.recordName, id.uuidString)
    }

    func testPersonalTaskTombstoneRoundTrip() {
        let id = UUID()
        let record = PersonalTaskTombstone(taskID: id).toCKRecord(zoneID: zone.zoneID)

        XCTAssertEqual(record.recordType, RecordType.personalTaskTombstone)
        XCTAssertNotEqual(record.recordID.recordName, id.uuidString)
        XCTAssertEqual(PersonalTaskTombstone.taskID(from: record), id)
        XCTAssertNil(PersonalTaskTombstone.taskID(from: CKRecord(recordType: RecordType.task)))
    }

    func testTaskRecord_omitsUndeployedRecurrenceFields() {
        var task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .general,
            frequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
            supplies: [], isActive: true
        )
        task.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        task.scheduledOverrideDate = Date(timeIntervalSince1970: 1_700_500_000)

        let record = task.toCKRecord(zone: zone)
        let decoded = HouseholdTask(from: record)

        XCTAssertNil(record["createdAt"])
        XCTAssertNil(record["scheduledOverrideDate"])
        XCTAssertNil(decoded?.scheduledOverrideDate)
    }

    func testTaskDecode_readsLegacyChecklistArray() throws {
        let task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .general,
            frequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
            supplies: [], isActive: true
        )
        let record = task.toCKRecord(zone: zone)
        let checklist = [ChecklistItem(text: "Step 1")]
        record["checklist"] = try JSONEncoder().encode(checklist) as CKRecordValue

        let decoded = try XCTUnwrap(HouseholdTask(from: record))

        XCTAssertEqual(decoded.checklist, checklist)
    }

    // MARK: - TaskCompletion

    func testCompletionRoundTrip() {
        let profileId = UUID()
        let oneTimeDueDate = Date(timeIntervalSince1970: 1_699_900_000)
        let completion = TaskCompletion(
            id: UUID(), taskId: UUID(), taskName: "Vacuum living room",
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            xpEarned: 25, streakBonus: 5, notes: "Did the stairs too",
            profileId: profileId,
            oneTimeDueDate: oneTimeDueDate
        )
        let record = completion.toCKRecord(zone: zone)
        guard let decoded = TaskCompletion(from: record) else {
            XCTFail("decode returned nil"); return
        }
        XCTAssertEqual(decoded.id, completion.id)
        XCTAssertEqual(decoded.taskId, completion.taskId)
        XCTAssertEqual(decoded.taskName, completion.taskName)
        XCTAssertEqual(decoded.completedAt, completion.completedAt)
        XCTAssertEqual(decoded.xpEarned, completion.xpEarned)
        XCTAssertEqual(decoded.streakBonus, completion.streakBonus)
        XCTAssertEqual(decoded.notes, completion.notes)
        XCTAssertEqual(decoded.profileId, profileId)
        XCTAssertEqual(decoded.oneTimeDueDate, oneTimeDueDate)
    }

    func testCompletionRoundTrip_nilOptionals() {
        let completion = TaskCompletion(
            id: UUID(), taskId: UUID(), taskName: "Take out trash",
            completedAt: Date(), xpEarned: 10, streakBonus: 0,
            notes: nil, profileId: nil
        )
        let decoded = TaskCompletion(from: completion.toCKRecord(zone: zone))
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.notes)
        XCTAssertNil(decoded?.profileId)
    }

    func testCompletionRecordID_usesCompletionUUID() {
        let id = UUID()
        let completion = TaskCompletion(
            id: id, taskId: UUID(), taskName: "Test", completedAt: Date(),
            xpEarned: 10, streakBonus: 0, notes: nil, profileId: nil
        )
        XCTAssertEqual(completion.toCKRecord(zone: zone).recordID.recordName, id.uuidString)
    }

    // MARK: - UserProfile

    func testProfileRoundTrip() {
        var profile = UserProfile()
        profile.id = UUID()
        profile.name = "Alice"
        profile.avatar = "cat"
        profile.totalXP = 1500
        profile.coins = 42
        profile.currentStreak = 7
        profile.longestStreak = 21
        profile.totalTasksCompleted = 55
        profile.joinDate = Date(timeIntervalSince1970: 1_600_000_000)
        profile.lastActiveDate = Date(timeIntervalSince1970: 1_700_000_000)
        profile.unlockedAchievements = ["first_task", "streak_7", "level_5"]

        guard let decoded = UserProfile(from: profile.toCKRecord(zone: zone)) else {
            XCTFail("decode returned nil"); return
        }
        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.name, profile.name)
        XCTAssertEqual(decoded.avatar, profile.avatar)
        XCTAssertEqual(decoded.totalXP, profile.totalXP)
        XCTAssertEqual(decoded.coins, profile.coins)
        XCTAssertEqual(decoded.currentStreak, profile.currentStreak)
        XCTAssertEqual(decoded.longestStreak, profile.longestStreak)
        XCTAssertEqual(decoded.totalTasksCompleted, profile.totalTasksCompleted)
        XCTAssertEqual(decoded.unlockedAchievements, profile.unlockedAchievements)
        XCTAssertNotNil(decoded.lastActiveDate)
    }

    func testProfileRoundTrip_nilLastActiveDate() {
        var profile = UserProfile()
        profile.id = UUID()
        profile.name = "Bob"
        profile.lastActiveDate = nil
        let decoded = UserProfile(from: profile.toCKRecord(zone: zone))
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.lastActiveDate)
    }

    func testProfileDecode_missingRequiredFields_returnsNil() {
        let record = CKRecord(
            recordType: RecordType.profile,
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID)
        )
        XCTAssertNil(UserProfile(from: record))
    }
}
