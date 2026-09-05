import XCTest
@testable import ADultingHD

final class StorageRecoveryTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_700_000_000)
    private let newer = Date(timeIntervalSince1970: 1_700_001_000)

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func write(_ data: Data, at url: URL, modified: Date) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private func makeTask(name: String = "Sort costumes") -> HouseholdTask {
        HouseholdTask(id: UUID(), name: name, description: "Keep every costume",
                      category: .general, frequency: .unscheduled, estimatedMinutes: 15,
                      difficulty: .medium, supplies: ["Storage boxes"], isActive: true)
    }

    func testDefaultStoresAreIsolatedAndResetDoesNotAffectAnotherInstance() async {
        let first = TaskStore()
        let second = TaskStore()
        var firstProfile = UserProfile()
        firstProfile.name = "First test"
        var secondProfile = UserProfile()
        secondProfile.name = "Second test"
        await first.saveProfile(firstProfile)
        await second.saveProfile(secondProfile)

        let firstLoaded = await first.loadProfile()
        let secondLoaded = await second.loadProfile()
        XCTAssertEqual(firstLoaded.id, firstProfile.id)
        XCTAssertEqual(secondLoaded.id, secondProfile.id)

        await first.resetAllData()
        let secondAfterReset = await second.loadProfile()
        XCTAssertEqual(secondAfterReset.id, secondProfile.id)
        XCTAssertEqual(secondAfterReset.name, "Second test")
    }

    @MainActor
    func testDataStoreInternalStorageIsAlsoIsolatedUnderXCTest() async throws {
        try StorageTestPreferences.preserve(in: self)
        let first = DataStore()
        let second = DataStore()
        await first.load()
        await first.addCustomTask(makeTask())
        await second.load()

        XCTAssertEqual(first.tasks.map(\.name), ["Sort costumes"])
        XCTAssertTrue(second.tasks.isEmpty)
        XCTAssertNotEqual(first.profile.id, second.profile.id)
    }

    func testEveryWorkspaceFileFallsBackToOlderValidLocalCopyWithoutRewritingIt() async throws {
        let root = try temporaryDirectory()
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        let store = TaskStore(directory: local, cloudDirectory: cloud)
        let task = makeTask()
        var profile = UserProfile()
        profile.name = "Alex"
        let household = Household.newLocal(name: "Maple House", members: [profile])
        let index = HouseholdIndex(households: [household], activeHouseholdId: household.id,
                                   schemaVersion: HouseholdIndex.currentSchemaVersion)
        let completion = TaskCompletion(id: UUID(), taskId: task.id, taskName: task.name,
                                        completedAt: older, xpEarned: 20, streakBonus: 0, notes: nil,
                                        profileId: profile.id)
        let workspace = "households/\(household.id.uuidString)/"
        let files = [
            ("profile.json", try encode(profile)),
            ("completions.json", try encode([completion])),
            ("households.json", try encode(index)),
            (workspace + "tasks.json", try encode([task])),
            (workspace + "supply_stock.json", try encode(["Storage boxes": SupplyStock.low]))
        ]
        let corrupt = Data("{unfinished".utf8)
        for (name, data) in files {
            try write(data, at: local.appendingPathComponent(name), modified: older)
            try write(corrupt, at: cloud.appendingPathComponent(name), modified: newer)
        }

        let loadedTasks = await store.loadTasks(for: household.id)
        let loadedProfile = await store.loadProfile()
        let loadedCompletions = await store.loadCompletions()
        let loadedIndex = await store.loadHouseholdIndex()
        let loadedStock = await store.loadSupplyStock(for: household.id)
        XCTAssertEqual(loadedTasks.map(\.id), [task.id])
        XCTAssertEqual(loadedProfile.id, profile.id)
        XCTAssertEqual(loadedCompletions.map(\.id), [completion.id])
        XCTAssertEqual(loadedIndex?.activeHouseholdId, household.id)
        XCTAssertEqual(loadedStock, ["Storage boxes": .low])
        for (name, data) in files {
            XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent(name)), data)
            XCTAssertEqual(try Data(contentsOf: cloud.appendingPathComponent(name)), corrupt)
        }
    }

    func testProfileChoosesNewestValidCopyAndFallsBackFromCorruptLocalCopy() async throws {
        let root = try temporaryDirectory()
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        let store = TaskStore(directory: local, cloudDirectory: cloud)
        var localProfile = UserProfile()
        localProfile.name = "Old name"
        var cloudProfile = localProfile
        cloudProfile.name = "New name"
        let localURL = local.appendingPathComponent("profile.json")
        let cloudURL = cloud.appendingPathComponent("profile.json")
        let cloudData = try encode(cloudProfile)
        try write(encode(localProfile), at: localURL, modified: older)
        try write(cloudData, at: cloudURL, modified: newer)
        let newest = await store.loadProfile()
        XCTAssertEqual(newest.name, "New name")

        try write(Data("broken".utf8), at: localURL, modified: newer.addingTimeInterval(100))
        let recovered = await store.loadProfile()
        XCTAssertEqual(recovered.id, cloudProfile.id)
        XCTAssertEqual(recovered.name, "New name")
        XCTAssertEqual(try Data(contentsOf: cloudURL), cloudData)
    }

    func testPlanningSidecarFallsBackToValidCopyForLegacyTasks() async throws {
        let root = try temporaryDirectory()
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        let store = TaskStore(directory: local, cloudDirectory: cloud)
        let id = UUID()
        var task = makeTask()
        task.room = "Costume Closet"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(task)) as? [String: Any])
        object.removeValue(forKey: "room")
        object.removeValue(forKey: "scheduleFrequency")
        object["category"] = "General"
        object["frequency"] = "Weekly"
        let taskData = try JSONSerialization.data(withJSONObject: [object])
        let prefix = "households/\(id.uuidString)/"
        let metadata = [TaskStore.TaskPlanningMetadata(id: task.id, room: "Costume Closet",
                                                       scheduleFrequency: .unscheduled,
                                                       legacyCategorySnapshot: "General",
                                                       legacyFrequencySnapshot: "Weekly")]
        try write(taskData, at: local.appendingPathComponent(prefix + "tasks.json"), modified: older)
        try write(encode(metadata), at: local.appendingPathComponent(prefix + "task_planning.json"), modified: older)
        try write(Data("broken".utf8), at: cloud.appendingPathComponent(prefix + "task_planning.json"), modified: newer)

        let recovered = await store.loadTasks(for: id)
        XCTAssertEqual(recovered.first?.room, "Costume Closet")
        XCTAssertEqual(recovered.first?.frequency, .unscheduled)
    }

    func testUnreadableProfileCopiesArePreservedDuringLoadAndBeforeExplicitReplacement() async throws {
        let root = try temporaryDirectory()
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        let store = TaskStore(directory: local, cloudDirectory: cloud)
        let localCorrupt = Data("local recovery bytes".utf8)
        let cloudCorrupt = Data("cloud recovery bytes".utf8)
        try write(localCorrupt, at: local.appendingPathComponent("profile.json"), modified: older)
        try write(cloudCorrupt, at: cloud.appendingPathComponent("profile.json"), modified: newer)

        _ = await store.loadProfile()
        XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent("profile.json")), localCorrupt)
        XCTAssertEqual(try Data(contentsOf: cloud.appendingPathComponent("profile.json")), cloudCorrupt)

        var replacement = UserProfile()
        replacement.name = "Recovered player"
        await store.saveProfile(replacement)
        for (directory, expected) in [(local, localCorrupt), (cloud, cloudCorrupt)] {
            let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("profile.json.recovery-") }
            XCTAssertEqual(copies.count, 1)
            let copy = try XCTUnwrap(copies.first)
            XCTAssertEqual(try Data(contentsOf: copy), expected)
        }
        let loaded = await store.loadProfile()
        XCTAssertEqual(loaded.id, replacement.id)
    }

    func testReliableWorkspaceSavePersistsTasksPlanningAndStockWhenCloudWriteFails() async throws {
        let root = try temporaryDirectory()
        let local = root.appendingPathComponent("local")
        let blockedCloud = root.appendingPathComponent("cloud-is-a-file")
        try Data("not a directory".utf8).write(to: blockedCloud)
        let store = TaskStore(directory: local, cloudDirectory: blockedCloud)
        let id = UUID()
        var task = makeTask()
        task.room = "Costume Closet"
        try await store.saveWorkspaceReliably(tasks: [task], supplyStock: ["Storage boxes": .out], for: id)

        let reopened = TaskStore(directory: local)
        let loaded = await reopened.loadTasks(for: id)
        let stock = await reopened.loadSupplyStock(for: id)
        XCTAssertEqual(loaded.map(\.id), [task.id])
        XCTAssertEqual(loaded.first?.room, "Costume Closet")
        XCTAssertEqual(stock, ["Storage boxes": .out])
        let metadataURL = local.appendingPathComponent("households/\(id.uuidString)/task_planning.json")
        let metadata = try JSONDecoder().decode([TaskStore.TaskPlanningMetadata].self, from: Data(contentsOf: metadataURL))
        XCTAssertEqual(metadata.first?.scheduleFrequency, .unscheduled)
        XCTAssertEqual(try Data(contentsOf: blockedCloud), Data("not a directory".utf8))
    }

    func testReliableWorkspaceSaveThrowsBeforeCloudWriteWhenLocalDirectoryIsBlocked() async throws {
        let root = try temporaryDirectory()
        let blockedLocal = root.appendingPathComponent("local-is-a-file")
        let cloud = root.appendingPathComponent("cloud")
        let sentinel = Data("preserve me".utf8)
        try sentinel.write(to: blockedLocal)
        let store = TaskStore(directory: blockedLocal, cloudDirectory: cloud)
        do {
            try await store.saveWorkspaceReliably(tasks: [makeTask()], supplyStock: [:], for: UUID())
            XCTFail("A failed local write must not report a saved household")
        } catch {
            XCTAssertTrue(error is CocoaError)
        }
        XCTAssertEqual(try Data(contentsOf: blockedLocal), sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.path))
    }

    func testDuplicateTaskIDsInNewestCopyFallBackToValidCopy() async throws {
        let root = try temporaryDirectory()
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        let store = TaskStore(directory: local, cloudDirectory: cloud)
        let id = UUID()
        let task = makeTask()
        let path = "households/\(id.uuidString)/tasks.json"
        try write(encode([task]), at: local.appendingPathComponent(path), modified: older)
        try write(encode([task, task]), at: cloud.appendingPathComponent(path), modified: newer)

        let loaded = await store.loadTasks(for: id)
        XCTAssertEqual(loaded.map(\.id), [task.id])
    }
}
