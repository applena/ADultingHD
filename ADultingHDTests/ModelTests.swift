import XCTest
@testable import ADultingHD

final class ModelTests: XCTestCase {

    // MARK: - HouseholdTask

    func testXPRewardCalculation() {
        let easyDaily = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: .daily, estimatedMinutes: 5, difficulty: .easy, supplies: [], isActive: true
        )
        // easy=1*10=10, daily=max(1,1/7)=1*5=5, time=5/10=0*2=0 → 15
        XCTAssertEqual(easyDaily.xpReward, 15)

        let hardWeekly = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .bathroom,
            frequency: .weekly, estimatedMinutes: 30, difficulty: .hard, supplies: [], isActive: true
        )
        // hard=3*10=30, weekly=max(1,7/7)=1*5=5, time=30/10=3*2=6 → 41
        XCTAssertEqual(hardWeekly.xpReward, 41)

        let epicMonthly = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .general,
            frequency: .monthly, estimatedMinutes: 60, difficulty: .epic, supplies: [], isActive: true
        )
        // epic=4*10=40, monthly=max(1,30/7)=4*5=20, time=60/10=6*2=12 → 72
        XCTAssertEqual(epicMonthly.xpReward, 72)
    }

    func testIsDueWhenNeverCompleted() {
        let task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: .weekly, estimatedMinutes: 10, difficulty: .easy, supplies: [], isActive: true
        )
        XCTAssertTrue(task.isDue)
    }

    func testIsDueWhenRecentlyCompleted() {
        var task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: .weekly, estimatedMinutes: 10, difficulty: .easy, supplies: [], isActive: true
        )
        task.lastCompleted = Date()
        XCTAssertFalse(task.isDue)
    }

    func testIsDueWhenOverdue() {
        var task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: .weekly, estimatedMinutes: 10, difficulty: .easy, supplies: [], isActive: true
        )
        task.lastCompleted = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        XCTAssertTrue(task.isDue)
        XCTAssertTrue(task.isOverdue)
    }

    func testInactiveTaskIsNeverDue() {
        let task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: .daily, estimatedMinutes: 5, difficulty: .easy, supplies: [], isActive: false
        )
        XCTAssertFalse(task.isDue)
        XCTAssertFalse(task.isOverdue)
    }

    // MARK: - UserProfile

    func testLevelCalculation() {
        var profile = UserProfile()
        XCTAssertEqual(profile.level, 0)

        profile.totalXP = 100
        XCTAssertEqual(profile.level, 1)

        profile.totalXP = 300  // 100 + 200 = 300 needed for level 2
        XCTAssertEqual(profile.level, 2)

        profile.totalXP = 600  // 100 + 200 + 300 = 600 for level 3
        XCTAssertEqual(profile.level, 3)
    }

    func testXPProgress() {
        var profile = UserProfile()
        profile.totalXP = 50
        // Level 0, need 100 for level 1
        XCTAssertEqual(profile.level, 0)
        XCTAssertEqual(profile.xpProgress, 0.5, accuracy: 0.01)
    }

    func testLevelTitles() {
        var profile = UserProfile()
        XCTAssertEqual(profile.levelTitle, "Rookie Roommate")

        profile.totalXP = 100
        XCTAssertEqual(profile.levelTitle, "Tidy Trainee")

        profile.totalXP = 2100 // level 5+
        XCTAssert(profile.level >= 5)
    }

    // MARK: - TaskFrequency

    func testFrequencyDays() {
        XCTAssertEqual(TaskFrequency.daily.days, 1)
        XCTAssertEqual(TaskFrequency.weekly.days, 7)
        XCTAssertEqual(TaskFrequency.biweekly.days, 14)
        XCTAssertEqual(TaskFrequency.monthly.days, 30)
        XCTAssertEqual(TaskFrequency.quarterly.days, 90)
        XCTAssertEqual(TaskFrequency.yearly.days, 365)
    }

    // MARK: - Default Tasks

    func testDefaultTasksNotEmpty() {
        XCTAssertGreaterThan(defaultHouseholdTasks.count, 40)
    }

    func testDefaultTasksHaveUniqueIDs() {
        let ids = defaultHouseholdTasks.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Default tasks should have unique IDs")
    }

    func testDefaultTasksCoverAllCategories() {
        let categories = Set(defaultHouseholdTasks.map(\.category))
        for cat in TaskCategory.allCases {
            XCTAssertTrue(categories.contains(cat), "Missing category: \(cat.rawValue)")
        }
    }

    func testDefaultTasksHaveValidXPRewards() {
        for task in defaultHouseholdTasks {
            XCTAssertGreaterThan(task.xpReward, 0, "\(task.name) should have positive XP")
        }
    }

    // MARK: - Difficulty

    func testDifficultyComparable() {
        XCTAssertTrue(Difficulty.easy < Difficulty.medium)
        XCTAssertTrue(Difficulty.medium < Difficulty.hard)
        XCTAssertTrue(Difficulty.hard < Difficulty.epic)
    }

    // MARK: - Achievements

    func testAllAchievementsHaveUniqueIDs() {
        let ids = allAchievements.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Achievements should have unique IDs")
    }
}
