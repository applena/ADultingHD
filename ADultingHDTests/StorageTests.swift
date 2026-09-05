import XCTest
@testable import ADultingHD

final class StorageTests: XCTestCase {
    private func makeStore() throws -> TaskStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return TaskStore(directory: directory)
    }

    func testTaskRoundTrip() async throws {
        let store = try makeStore()
        let householdId = UUID()
        var task = HouseholdTask(
            id: UUID(), name: "Test Task", description: "A test",
            category: .kitchen, frequency: .weekly, estimatedMinutes: 10,
            difficulty: .easy, supplies: ["Sponge", "Soap"], isActive: true,
            lastCompleted: Date()
        )
        task.isPersonal = true
        task.room = "Galley"
        task.frequency = .unscheduled
        let tasks = [task]

        await store.saveTasks(tasks, for: householdId)
        let loaded = await store.loadTasks(for: householdId)

        XCTAssertEqual(loaded.count, tasks.count)
        XCTAssertEqual(loaded.first?.name, "Test Task")
        XCTAssertEqual(loaded.first?.supplies, ["Sponge", "Soap"])
        XCTAssertEqual(loaded.first?.room, "Galley")
        XCTAssertEqual(loaded.first?.frequency, .unscheduled)
        XCTAssertTrue(loaded.first?.isPersonal == true)
    }

    func testPlanningSidecarRestoresOlderWholeFileRewriteAndHonorsLegacyEdits() throws {
        let id = UUID()
        let sourceData = Data("""
        [{"id":"\(id.uuidString)","category":"General","frequency":"Weekly"}]
        """.utf8)
        let sourceFields = try JSONDecoder().decode(
            [TaskStore.StoredTaskPlanningFields].self,
            from: sourceData
        )
        let metadata = [TaskStore.TaskPlanningMetadata(
            id: id,
            room: "Costume Closet",
            scheduleFrequency: .unscheduled,
            legacyCategorySnapshot: "General",
            legacyFrequencySnapshot: "Weekly"
        )]
        let oldRewrite = HouseholdTask(
            id: id, name: "Sort costumes", description: "",
            category: .general, frequency: .weekly, estimatedMinutes: 15,
            difficulty: .medium, supplies: [], isActive: true
        )

        let restored = TaskStore.restoringPlanningMetadata(
            [oldRewrite], sourceFields: sourceFields, metadata: metadata
        )

        XCTAssertEqual(restored.first?.room, "Costume Closet")
        XCTAssertEqual(restored.first?.frequency, .unscheduled)

        let editedSourceData = Data("""
        [{"id":"\(id.uuidString)","category":"Kitchen","frequency":"Monthly"}]
        """.utf8)
        let editedFields = try JSONDecoder().decode(
            [TaskStore.StoredTaskPlanningFields].self,
            from: editedSourceData
        )
        let oldClientEdit = HouseholdTask(
            id: id, name: "Sort costumes", description: "",
            category: .kitchen, frequency: .monthly, estimatedMinutes: 15,
            difficulty: .medium, supplies: [], isActive: true
        )
        let preservedEdit = TaskStore.restoringPlanningMetadata(
            [oldClientEdit], sourceFields: editedFields, metadata: metadata
        )

        XCTAssertEqual(preservedEdit.first?.room, "Kitchen")
        XCTAssertEqual(preservedEdit.first?.frequency, .monthly)
    }

    func testProfileRoundTrip() async throws {
        let store = try makeStore()
        var profile = UserProfile()
        profile.totalXP = 500
        profile.currentStreak = 7
        profile.longestStreak = 14
        profile.totalTasksCompleted = 42
        profile.unlockedAchievements = ["first_task", "streak_7"]

        await store.saveProfile(profile)
        let loaded = await store.loadProfile()

        XCTAssertEqual(loaded.totalXP, 500)
        XCTAssertEqual(loaded.currentStreak, 7)
        XCTAssertEqual(loaded.longestStreak, 14)
        XCTAssertEqual(loaded.totalTasksCompleted, 42)
        XCTAssertEqual(loaded.unlockedAchievements, ["first_task", "streak_7"])
    }

    func testCompletionsRoundTrip() async throws {
        let store = try makeStore()
        let completions = [
            TaskCompletion(
                id: UUID(), taskId: UUID(), taskName: "Test",
                completedAt: Date(), xpEarned: 20, streakBonus: 4, notes: "Done!"
            )
        ]

        await store.saveCompletions(completions)
        let loaded = await store.loadCompletions()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.taskName, "Test")
        XCTAssertEqual(loaded.first?.xpEarned, 20)
        XCTAssertEqual(loaded.first?.streakBonus, 4)
    }

    func testBackupRoundTrip() async throws {
        let store = try makeStore()
        let householdId = UUID()
        var customTask = HouseholdTask(
            id: UUID(), name: "Sort the costume closet", description: "",
            category: .general, frequency: .unscheduled, estimatedMinutes: 15,
            difficulty: .medium, supplies: [], isActive: true
        )
        customTask.room = "Costume Closet"
        let tasks = taskCatalog.prefix(5).map { $0.toHouseholdTask() } + [customTask]
        var profile = UserProfile()
        profile.totalXP = 250
        profile.totalTasksCompleted = 10

        await store.saveTasks(tasks, for: householdId)
        await store.saveProfile(profile)

        guard let backupData = await store.exportBackup(householdId: householdId) else {
            XCTFail("Export returned nil")
            return
        }

        // Reset and reimport
        await store.resetAllData()
        let success = await store.importBackup(from: backupData, householdId: householdId)

        XCTAssertTrue(success)
        let loadedTasks = await store.loadTasks(for: householdId)
        let loadedProfile = await store.loadProfile()
        XCTAssertEqual(loadedTasks.count, tasks.count)
        XCTAssertEqual(loadedTasks.last?.room, "Costume Closet")
        XCTAssertEqual(loadedTasks.last?.frequency, .unscheduled)
        XCTAssertEqual(loadedProfile.totalXP, 250)
    }

    func testImportRejectsDuplicateTaskIDs() async throws {
        let store = try makeStore()
        let householdId = UUID()
        let task = HouseholdTask(
            id: UUID(), name: "Duplicate", description: "",
            category: .general, frequency: .unscheduled, estimatedMinutes: 15,
            difficulty: .medium, supplies: [], isActive: true
        )
        let backup = TaskStore.AppBackup(
            version: 1,
            exported: ISO8601DateFormatter().string(from: Date()),
            tasks: [task, task],
            profile: UserProfile(),
            completions: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let imported = await store.importBackup(
            from: try encoder.encode(backup),
            householdId: householdId
        )

        XCTAssertFalse(imported)

        let completion = TaskCompletion(
            id: UUID(), taskId: task.id, taskName: task.name,
            completedAt: Date(), xpEarned: 10, streakBonus: 0,
            notes: nil, profileId: nil
        )
        let duplicateCompletionBackup = TaskStore.AppBackup(
            version: 1,
            exported: ISO8601DateFormatter().string(from: Date()),
            tasks: [task],
            profile: UserProfile(),
            completions: [completion, completion]
        )

        let importedDuplicateCompletions = await store.importBackup(
            from: try encoder.encode(duplicateCompletionBackup),
            householdId: householdId
        )

        XCTAssertFalse(importedDuplicateCompletions)
    }
}

/// DataStore uses a few shared preferences in addition to its injected file
/// store. Restore only keys touched by these tests; never replace a whole domain.
enum StorageTestPreferences {
    static func preserve(in test: XCTestCase) throws {
        try preserve([
            PrefKey.householdSharingEnabled,
            PrefKey.householdsLayoutMigratedV2,
            PrefKey.defaultHouseholdId
        ], suiteName: nil, in: test)
        try preserve([
            "widget_dueTasks", "widget_streak", "widget_level", "widget_levelTitle",
            "widget_xpProgress", "widget_totalXP", "widget_todayCompleted", "widget_nextTask"
        ], suiteName: SharedDefaults.suiteName, in: test)
    }

    private static func preserve(_ keys: [String], suiteName: String?, in test: XCTestCase) throws {
        let defaults: UserDefaults?
        if let suiteName { defaults = UserDefaults(suiteName: suiteName) }
        else { defaults = .standard }
        guard let defaults else { return }
        let values = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            defaults.object(forKey: key).map { (key, $0) }
        })
        // Capture Sendable bytes in XCTest's teardown closure, not a mutable
        // dictionary of Any or a shared UserDefaults instance.
        let snapshot = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        test.addTeardownBlock {
            let defaults: UserDefaults?
            if let suiteName { defaults = UserDefaults(suiteName: suiteName) }
            else { defaults = .standard }
            guard let defaults else { return }
            let saved = try PropertyListSerialization.propertyList(from: snapshot, format: nil) as? [String: Any] ?? [:]
            for key in keys { defaults.set(saved[key], forKey: key) }
        }
    }
}
