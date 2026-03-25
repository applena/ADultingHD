import XCTest
@testable import ADultingHD

final class StorageTests: XCTestCase {

    func testTaskRoundTrip() async {
        let store = TaskStore()
        let tasks = [
            HouseholdTask(
                id: UUID(), name: "Test Task", description: "A test",
                category: .kitchen, frequency: .weekly, estimatedMinutes: 10,
                difficulty: .easy, supplies: ["Sponge", "Soap"], isActive: true,
                lastCompleted: Date()
            )
        ]

        await store.saveTasks(tasks)
        let loaded = await store.loadTasks()

        XCTAssertEqual(loaded.count, tasks.count)
        XCTAssertEqual(loaded.first?.name, "Test Task")
        XCTAssertEqual(loaded.first?.supplies, ["Sponge", "Soap"])
    }

    func testProfileRoundTrip() async {
        let store = TaskStore()
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

    func testCompletionsRoundTrip() async {
        let store = TaskStore()
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

    func testBackupRoundTrip() async {
        let store = TaskStore()
        let tasks = Array(defaultHouseholdTasks.prefix(5))
        var profile = UserProfile()
        profile.totalXP = 250
        profile.totalTasksCompleted = 10

        await store.saveTasks(tasks)
        await store.saveProfile(profile)

        guard let backupData = await store.exportBackup() else {
            XCTFail("Export returned nil")
            return
        }

        // Reset and reimport
        await store.resetAllData()
        let success = await store.importBackup(from: backupData)

        XCTAssertTrue(success)
        let loadedTasks = await store.loadTasks()
        let loadedProfile = await store.loadProfile()
        XCTAssertEqual(loadedTasks.count, tasks.count)
        XCTAssertEqual(loadedProfile.totalXP, 250)
    }
}
