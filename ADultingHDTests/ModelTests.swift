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

    // MARK: - Assignee Filter

    func testAssigneeFilterAllAlwaysMatches() {
        let me = UUID()
        var task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: .weekly, estimatedMinutes: 10, difficulty: .easy, supplies: [], isActive: true
        )
        XCTAssertTrue(task.matches(.all, currentProfileId: me))
        task.defaultAssigneeId = UUID()
        XCTAssertTrue(task.matches(.all, currentProfileId: me))
    }

    func testAssigneeFilterMineMatchesOnlyOwnAssignment() {
        let me = UUID()
        var task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: .weekly, estimatedMinutes: 10, difficulty: .easy, supplies: [], isActive: true
        )
        XCTAssertFalse(task.matches(.mine, currentProfileId: me), "unassigned task should not match Mine")

        task.defaultAssigneeId = UUID()
        XCTAssertFalse(task.matches(.mine, currentProfileId: me), "task assigned to someone else should not match Mine")

        task.defaultAssigneeId = me
        XCTAssertTrue(task.matches(.mine, currentProfileId: me))
    }

    func testAssigneeFilterUnassignedMatchesOnlyNilAssignment() {
        let me = UUID()
        var task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: .weekly, estimatedMinutes: 10, difficulty: .easy, supplies: [], isActive: true
        )
        XCTAssertTrue(task.matches(.unassigned, currentProfileId: me))

        task.defaultAssigneeId = me
        XCTAssertFalse(task.matches(.unassigned, currentProfileId: me))

        task.defaultAssigneeId = UUID()
        XCTAssertFalse(task.matches(.unassigned, currentProfileId: me))
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
        XCTAssertGreaterThanOrEqual(defaultHouseholdTasks.count, 3)
    }

    func testDefaultTasksHaveUniqueIDs() {
        let ids = defaultHouseholdTasks.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Default tasks should have unique IDs")
    }

    func testDefaultTasksHaveFocusedStarterSet() {
        let dailyTasks = defaultHouseholdTasks.filter { $0.frequency == .daily && $0.isActive }
        XCTAssertLessThanOrEqual(dailyTasks.count, 2)
        XCTAssertTrue(defaultHouseholdTasks.contains { $0.name == "Do dishes" })
        XCTAssertTrue(defaultHouseholdTasks.contains { $0.name == "Wipe the counters" })
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

    // MARK: - WeeklyLeaderboard

    private func makeCompletion(profileId: UUID?, xp: Int, streakBonus: Int = 0, daysAgo: Int = 0) -> TaskCompletion {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return TaskCompletion(
            id: UUID(), taskId: UUID(), taskName: "Test", completedAt: date,
            xpEarned: xp, streakBonus: streakBonus, notes: nil, profileId: profileId
        )
    }

    func testWeeklyLeaderboardSumsXPAndStreakBonusPerMember() {
        var alice = UserProfile(); alice.name = "Alice"
        var bob = UserProfile(); bob.name = "Bob"
        let completions = [
            makeCompletion(profileId: alice.id, xp: 10, streakBonus: 5),
            makeCompletion(profileId: alice.id, xp: 20),
            makeCompletion(profileId: bob.id, xp: 15),
        ]
        let entries = WeeklyLeaderboard.entries(members: [alice, bob], completions: completions)
        XCTAssertEqual(entries.first?.profile.name, "Alice")
        XCTAssertEqual(entries.first?.weeklyXP, 35)
        XCTAssertEqual(entries.last?.profile.name, "Bob")
        XCTAssertEqual(entries.last?.weeklyXP, 15)
    }

    func testWeeklyLeaderboardExcludesCompletionsOutsideCurrentWeek() {
        let alice = UserProfile()
        let completions = [
            makeCompletion(profileId: alice.id, xp: 10, daysAgo: 0),
            makeCompletion(profileId: alice.id, xp: 999, daysAgo: 30),
        ]
        let entries = WeeklyLeaderboard.entries(members: [alice], completions: completions)
        XCTAssertEqual(entries.first?.weeklyXP, 10)
    }

    func testWeeklyLeaderboardIgnoresLegacyCompletionsWithNoProfileId() {
        let alice = UserProfile()
        let completions = [makeCompletion(profileId: nil, xp: 50)]
        let entries = WeeklyLeaderboard.entries(members: [alice], completions: completions)
        XCTAssertEqual(entries.first?.weeklyXP, 0)
    }

    func testWeeklyLeaderboardMembersWithNoCompletionsScoreZero() {
        let alice = UserProfile()
        let bob = UserProfile()
        let entries = WeeklyLeaderboard.entries(members: [alice, bob], completions: [])
        XCTAssertEqual(entries.map(\.weeklyXP), [0, 0])
    }

    func testSuperstarIsNilForSoloHousehold() {
        let alice = UserProfile()
        let entries = WeeklyLeaderboard.entries(members: [alice], completions: [makeCompletion(profileId: alice.id, xp: 100)])
        XCTAssertNil(WeeklyLeaderboard.superstar(among: entries))
    }

    func testSuperstarIsNilWhenNoOneHasEarnedXP() {
        let entries = WeeklyLeaderboard.entries(members: [UserProfile(), UserProfile()], completions: [])
        XCTAssertNil(WeeklyLeaderboard.superstar(among: entries))
    }

    func testSuperstarIsNilOnATie() {
        let alice = UserProfile()
        let bob = UserProfile()
        let completions = [
            makeCompletion(profileId: alice.id, xp: 20),
            makeCompletion(profileId: bob.id, xp: 20),
        ]
        let entries = WeeklyLeaderboard.entries(members: [alice, bob], completions: completions)
        XCTAssertNil(WeeklyLeaderboard.superstar(among: entries))
    }

    func testSuperstarIsTheTopScorer() {
        var alice = UserProfile(); alice.name = "Alice"
        let bob = UserProfile()
        let completions = [
            makeCompletion(profileId: alice.id, xp: 50),
            makeCompletion(profileId: bob.id, xp: 20),
        ]
        let entries = WeeklyLeaderboard.entries(members: [alice, bob], completions: completions)
        XCTAssertEqual(WeeklyLeaderboard.superstar(among: entries)?.profile.name, "Alice")
    }
}
