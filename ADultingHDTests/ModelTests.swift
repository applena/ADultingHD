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

    func testScheduledFrequenciesHaveConcreteDefaults() {
        XCTAssertEqual(TaskFrequency.weekly.defaultWeekdays, [2])
        XCTAssertEqual(TaskFrequency.biweekly.defaultWeekdays, [2])
        XCTAssertEqual(TaskFrequency.twiceWeekly.defaultWeekdays, [2, 5])
        XCTAssertTrue(TaskFrequency.daily.defaultWeekdays.isEmpty)
    }

    func testCatalogWeeklyTaskIsAnchoredToItsDefaultDay() {
        let catalogTask = CatalogTask(
            name: "Clean the oven", description: "", category: .kitchen,
            suggestedFrequency: .weekly, estimatedMinutes: 20,
            difficulty: .medium, supplies: []
        )

        XCTAssertEqual(catalogTask.toHouseholdTask().scheduledWeekdays, [2])
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

    func testPersonalTaskIsMineAndNeverUnassigned() {
        let me = UUID()
        var task = HouseholdTask(
            id: UUID(), name: "Take a shower", description: "", category: .bathroom,
            frequency: .daily, estimatedMinutes: 10, difficulty: .easy, supplies: [], isActive: true
        )
        task.isPersonal = true
        task.defaultAssigneeId = UUID()

        XCTAssertTrue(task.matches(.mine, currentProfileId: me))
        XCTAssertFalse(task.matches(.unassigned, currentProfileId: me))
    }

    func testLegacyTaskJSONDefaultsNewFields() throws {
        let data = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Clip fingernails",
          "description": "",
          "category": "General",
          "frequency": "Weekly",
          "estimatedMinutes": 10,
          "difficulty": 1,
          "supplies": [],
          "isActive": true
        }
        """.utf8)

        let task = try JSONDecoder().decode(HouseholdTask.self, from: data)

        XCTAssertNil(task.room)
        XCTAssertEqual(task.frequency, .weekly)
        XCTAssertFalse(task.isPersonal)
        XCTAssertTrue(task.scheduledWeekdays.isEmpty)
        XCTAssertTrue(task.checklist.isEmpty)
    }

    func testUnknownLegacyCategoryMigratesToCustomRoom() throws {
        let data = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "name": "Clear the mudroom",
          "description": "",
          "category": "Mudroom",
          "frequency": "Monthly",
          "estimatedMinutes": 10,
          "difficulty": 1,
          "supplies": [],
          "isActive": true
        }
        """.utf8)

        let task = try JSONDecoder().decode(HouseholdTask.self, from: data)

        XCTAssertEqual(task.room, "Mudroom")
        XCTAssertEqual(task.category, .general, "custom rooms use the legacy General fallback")
    }

    func testFreeformRoomAndUnscheduledStateRoundTripWithLegacyFallbacks() throws {
        var task = HouseholdTask(
            id: UUID(), name: "Sort the costume closet", description: "",
            category: .general, frequency: .unscheduled, estimatedMinutes: 15,
            difficulty: .medium, supplies: [], isActive: true
        )
        task.room = "Costume Closet"

        let data = try JSONEncoder().encode(task)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(HouseholdTask.self, from: data)

        XCTAssertEqual(json["room"] as? String, "Costume Closet")
        XCTAssertEqual(json["category"] as? String, "General")
        XCTAssertEqual(json["scheduleFrequency"] as? String, "No Schedule")
        XCTAssertEqual(json["frequency"] as? String, "Weekly")
        XCTAssertEqual(decoded.room, "Costume Closet")
        XCTAssertEqual(decoded.frequency, .unscheduled)
    }

    func testLegacyRoomStylingUsesTheSameNormalizedIdentityAsGrouping() {
        XCTAssertEqual(TaskCategory.legacyFallback(for: "kitchen"), .kitchen)
        XCTAssertEqual(TaskCategory.legacyFallback(for: "LIVING ROOM"), .livingRoom)
        XCTAssertEqual(HouseholdTask.roomIdentity("Café"), HouseholdTask.roomIdentity("cafe"))
    }

    func testExplicitGeneralRoomIsDistinctFromLegacyGeneralCategory() throws {
        var task = try JSONDecoder().decode(HouseholdTask.self, from: Data("""
        {
          "id": "00000000-0000-0000-0000-000000000003",
          "name": "Legacy task",
          "description": "",
          "category": "General",
          "frequency": "Weekly",
          "estimatedMinutes": 10,
          "difficulty": 1,
          "supplies": [],
          "isActive": true
        }
        """.utf8))
        XCTAssertNil(task.room)

        task.room = "General"
        let roundTripped = try JSONDecoder().decode(
            HouseholdTask.self,
            from: JSONEncoder().encode(task)
        )
        XCTAssertEqual(roundTripped.room, "General")
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

    func testStreakBonusXPScalesWithStreakAndCaps() {
        XCTAssertEqual(UserProfile.streakBonusXP(for: 0), 0)
        XCTAssertEqual(UserProfile.streakBonusXP(for: 1), 2)
        XCTAssertEqual(UserProfile.streakBonusXP(for: 7), 14)
        XCTAssertEqual(UserProfile.streakBonusXP(for: 25), 50)
        XCTAssertEqual(UserProfile.streakBonusXP(for: 100), 50)
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
        XCTAssertEqual(TaskFrequency.unscheduled.days, 0)
        XCTAssertEqual(TaskFrequency.daily.days, 1)
        XCTAssertEqual(TaskFrequency.weekly.days, 7)
        XCTAssertEqual(TaskFrequency.biweekly.days, 14)
        XCTAssertEqual(TaskFrequency.monthly.days, 30)
        XCTAssertEqual(TaskFrequency.quarterly.days, 90)
        XCTAssertEqual(TaskFrequency.yearly.days, 365)
    }

    // MARK: - Task Catalog

    func testCatalogTasksHaveUniqueNames() {
        let names = taskCatalog.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "Catalog tasks should have unique names")
    }

    func testCatalogTasksHaveValidXPRewards() {
        for task in taskCatalog {
            XCTAssertGreaterThan(task.toHouseholdTask().xpReward, 0, "\(task.name) should have positive XP")
        }
    }

    /// Onboarding is the only path that seeds a new household, so an offered
    /// room with no recommendations would strand a user on an empty list.
    func testEveryOnboardingRoomHasRecommendations() {
        XCTAssertFalse(onboardingRooms.isEmpty)
        for room in onboardingRooms {
            XCTAssertFalse(
                onboardingRecommendedCatalogTasks(for: [room]).isEmpty,
                "\(room.rawValue) is offered during onboarding but recommends nothing"
            )
        }
    }

    func testEveryHomeLocationHasScopedCatalogSuggestions() {
        XCTAssertEqual(
            Set(HomeLocation.allCases.map(\.id)).count,
            HomeLocation.allCases.count,
            "Home locations should have stable unique identifiers"
        )

        for location in HomeLocation.allCases {
            let recommendations = onboardingRecommendedCatalogTasks(for: [location])
            XCTAssertFalse(
                recommendations.isEmpty,
                "\(location.rawValue) should offer at least one catalog suggestion"
            )
            XCTAssertTrue(
                recommendations.contains { task in
                    task.suggestedRoom != nil && location.matches(taskRoom: task.suggestedRoom)
                }
            )
        }
    }

    func testOnboardingRecommendationsAreFocusedAndScopedToSelectedRooms() {
        let requestedRooms: Set<TaskCategory> = [.kitchen, .bathroom, .general]
        let recommendations = onboardingRecommendedCatalogTasks(for: requestedRooms)

        XCTAssertFalse(recommendations.isEmpty)
        XCTAssertTrue(recommendations.allSatisfy { requestedRooms.contains($0.category) })
        XCTAssertEqual(recommendations.count, Set(recommendations.map(\.name)).count)

        for category in requestedRooms {
            XCTAssertLessThanOrEqual(recommendations.filter { $0.category == category }.count, 3)
        }

        XCTAssertEqual(recommendations.first?.name, "Wash dishes")
        XCTAssertTrue(recommendations.contains { $0.name == "Take out trash and recycling" })
    }

    func testOnboardingCatalogSearchRanksNameMatchesAndLimitsResults() {
        let matches = onboardingCatalogMatches(for: "  DISH  ", limit: 2)

        XCTAssertLessThanOrEqual(matches.count, 2)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.first?.name, "Wash dishes")
        XCTAssertTrue(matches.allSatisfy {
            $0.name.localizedCaseInsensitiveContains("dish")
                || $0.description.localizedCaseInsensitiveContains("dish")
        })
    }

    func testOnboardingCatalogSearchFindsExactRecord() {
        XCTAssertEqual(onboardingCatalogTask(named: "  wash dishes ")?.name, "Wash dishes")
        XCTAssertNil(onboardingCatalogTask(named: "polish the moon"))
    }

    func testOnboardingLocationFilterKeepsWholeHomeTasksAvailable() {
        let selectedLocations: Set<HomeLocation> = [.garage]

        XCTAssertEqual(
            onboardingCatalogTask(named: "sweep garage floor", in: selectedLocations)?.name,
            "Sweep garage floor"
        )
        XCTAssertNil(onboardingCatalogTask(named: "wash dishes", in: selectedLocations))
        XCTAssertEqual(
            onboardingCatalogTask(named: "take out trash and recycling", in: selectedLocations)?.name,
            "Take out trash and recycling"
        )
    }

    func testOnboardingCustomTaskRequiresOnlyAName() throws {
        let task = try XCTUnwrap(makeOnboardingCustomTask(named: "  Polish the moon  "))

        XCTAssertEqual(task.name, "Polish the moon")
        XCTAssertNil(task.room)
        XCTAssertEqual(task.frequency, .unscheduled)
        XCTAssertNil(task.nextOccurrence())
        XCTAssertNil(makeOnboardingCustomTask(named: "   "))
    }

    func testCatalogTemplateCopiesEditableDefaults() {
        let template = taskCatalog[0]
        var task = template.toHouseholdTask()

        XCTAssertEqual(task.room, template.suggestedRoom)
        XCTAssertEqual(task.frequency, template.suggestedFrequency)

        task.room = nil
        task.frequency = .unscheduled
        task.supplies = []
        task.difficulty = .epic

        XCTAssertNil(task.room)
        XCTAssertEqual(task.frequency, .unscheduled)
        XCTAssertFalse(template.supplies.isEmpty)
        XCTAssertNotEqual(template.difficulty, task.difficulty)
    }

    func testStarterAvatarsAreFreeAndHaveImages() {
        let starterIDs = ["raccoon", "turtle", "otter", "capybara"]
        let starters = starterIDs.compactMap(avatarItem(byId:))

        XCTAssertEqual(starters.count, starterIDs.count)
        XCTAssertTrue(starters.allSatisfy { $0.cost == 0 && $0.imageName != nil })
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
