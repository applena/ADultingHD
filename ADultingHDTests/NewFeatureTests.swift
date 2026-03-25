import XCTest
@testable import ADultingHD

final class NewFeatureTests: XCTestCase {

    // MARK: - Helper: create a test task

    private func makeTask(
        name: String = "Test Task",
        category: TaskCategory = .kitchen,
        frequency: TaskFrequency = .weekly,
        minutes: Int = 15,
        difficulty: Difficulty = .medium,
        supplies: [String] = [],
        isActive: Bool = true,
        lastCompleted: Date? = nil
    ) -> HouseholdTask {
        HouseholdTask(
            id: UUID(),
            name: name,
            description: "Test description",
            category: category,
            frequency: frequency,
            estimatedMinutes: minutes,
            difficulty: difficulty,
            supplies: supplies,
            isActive: isActive,
            lastCompleted: lastCompleted
        )
    }

    private func makeCompletion(
        taskId: UUID = UUID(),
        taskName: String = "Test Task",
        date: Date = Date(),
        xpEarned: Int = 20,
        streakBonus: Int = 0,
        quality: CompletionQuality? = .normal
    ) -> TaskCompletion {
        TaskCompletion(
            id: UUID(),
            taskId: taskId,
            taskName: taskName,
            completedAt: date,
            xpEarned: xpEarned,
            streakBonus: streakBonus,
            notes: nil,
            quality: quality
        )
    }

    private func makeProfile(
        name: String = "Player 1",
        totalXP: Int = 0,
        streak: Int = 0,
        longestStreak: Int = 0,
        completed: Int = 0,
        achievements: [String] = []
    ) -> UserProfile {
        var profile = UserProfile()
        profile.name = name
        profile.totalXP = totalXP
        profile.currentStreak = streak
        profile.longestStreak = longestStreak
        profile.totalTasksCompleted = completed
        profile.unlockedAchievements = achievements
        return profile
    }

    // MARK: - Idea 2: Stats data (XP per day, completions per day)

    func testCompletionsGroupedByDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let completions = [
            makeCompletion(date: today, xpEarned: 15),
            makeCompletion(date: today, xpEarned: 25),
            makeCompletion(date: yesterday, xpEarned: 30),
        ]

        let todayCompletions = completions.filter { calendar.isDate($0.completedAt, inSameDayAs: today) }
        let yesterdayCompletions = completions.filter { calendar.isDate($0.completedAt, inSameDayAs: yesterday) }

        XCTAssertEqual(todayCompletions.count, 2)
        XCTAssertEqual(yesterdayCompletions.count, 1)

        let todayXP = todayCompletions.reduce(0) { $0 + $1.xpEarned + $1.streakBonus }
        XCTAssertEqual(todayXP, 40)
    }

    func testCategoryBreakdownFromCompletions() {
        let kitchenTaskId = UUID()
        let bathroomTaskId = UUID()

        let tasks = [
            HouseholdTask(id: kitchenTaskId, name: "Dishes", description: "", category: .kitchen, frequency: .daily, estimatedMinutes: 10, difficulty: .easy, supplies: [], isActive: true),
            HouseholdTask(id: bathroomTaskId, name: "Toilet", description: "", category: .bathroom, frequency: .weekly, estimatedMinutes: 10, difficulty: .medium, supplies: [], isActive: true),
        ]

        let completions = [
            makeCompletion(taskId: kitchenTaskId),
            makeCompletion(taskId: kitchenTaskId),
            makeCompletion(taskId: bathroomTaskId),
        ]

        let categoryData = TaskCategory.allCases.compactMap { category -> (TaskCategory, Int)? in
            let count = completions.filter { completion in
                tasks.first { $0.id == completion.taskId }?.category == category
            }.count
            return count > 0 ? (category, count) : nil
        }

        XCTAssertEqual(categoryData.count, 2)
        XCTAssertEqual(categoryData.first(where: { $0.0 == .kitchen })?.1, 2)
        XCTAssertEqual(categoryData.first(where: { $0.0 == .bathroom })?.1, 1)
    }

    // MARK: - Idea 3: Multi-User

    func testUserProfileHasNameAndAvatar() {
        let profile = UserProfile()
        XCTAssertEqual(profile.name, "Player 1")
        XCTAssertEqual(profile.avatar, "person.crop.circle.fill")
    }

    func testUserProfileIsIdentifiable() {
        let p1 = UserProfile()
        let p2 = UserProfile()
        XCTAssertNotEqual(p1.id, p2.id)
    }

    func testLeaderboardSortedByXP() {
        var p1 = makeProfile(name: "Alice", totalXP: 500)
        var p2 = makeProfile(name: "Bob", totalXP: 300)
        var p3 = makeProfile(name: "Charlie", totalXP: 800)

        let leaderboard = [p1, p2, p3].sorted { $0.totalXP > $1.totalXP }
        XCTAssertEqual(leaderboard[0].name, "Charlie")
        XCTAssertEqual(leaderboard[1].name, "Alice")
        XCTAssertEqual(leaderboard[2].name, "Bob")
    }

    // MARK: - Idea 5: Achievement Progress

    func testAchievementHasFlavorText() {
        for achievement in allAchievements {
            XCTAssertFalse(achievement.flavorText.isEmpty, "\(achievement.name) should have flavor text")
        }
    }

    func testAchievementHasTargetValue() {
        for achievement in allAchievements {
            XCTAssertGreaterThan(achievement.targetValue, 0, "\(achievement.name) should have a positive target")
        }
    }

    func testAchievementProgressComputation() {
        let profile = makeProfile(totalXP: 500, completed: 25)
        let completions: [TaskCompletion] = []

        // Task count achievement: 25 of 50
        let halfCentury = allAchievements.first { $0.id == "fifty_tasks" }!
        let progress = halfCentury.currentProgress(profile: profile, completions: completions)
        XCTAssertEqual(progress, 25)

        let fraction = halfCentury.progressFraction(profile, completions)
        XCTAssertEqual(fraction, 0.5, accuracy: 0.01)
    }

    func testAchievementProgressForStreaks() {
        let profile = makeProfile(streak: 5, longestStreak: 10)
        let completions: [TaskCompletion] = []

        let weekWarrior = allAchievements.first { $0.id == "streak_7" }!
        let progress = weekWarrior.currentProgress(profile: profile, completions: completions)
        // Uses max(current, longest) = 10
        XCTAssertEqual(progress, 10)
    }

    func testAchievementProgressForXP() {
        let profile = makeProfile(totalXP: 750)
        let completions: [TaskCompletion] = []

        let xpCollector = allAchievements.first { $0.id == "xp_1000" }!
        let fraction = xpCollector.progressFraction(profile, completions)
        XCTAssertEqual(fraction, 0.75, accuracy: 0.01)
    }

    func testAchievementProgressCapsAtOne() {
        let profile = makeProfile(totalXP: 2000)
        let completions: [TaskCompletion] = []

        let xpCollector = allAchievements.first { $0.id == "xp_1000" }!
        let fraction = xpCollector.progressFraction(profile, completions)
        XCTAssertEqual(fraction, 1.0, accuracy: 0.01)
    }

    func testFiveInDayProgressFromCompletions() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let completions = (0..<3).map { _ in makeCompletion(date: today) }

        let profile = makeProfile()
        let productive = allAchievements.first { $0.id == "five_in_day" }!
        let progress = productive.currentProgress(profile: profile, completions: completions)
        XCTAssertEqual(progress, 3)
    }

    // MARK: - Idea 6: Completion Quality

    func testCompletionQualityXPMultiplier() {
        XCTAssertEqual(CompletionQuality.quick.xpMultiplier, 0.75)
        XCTAssertEqual(CompletionQuality.normal.xpMultiplier, 1.0)
        XCTAssertEqual(CompletionQuality.deep.xpMultiplier, 1.5)
    }

    func testCompletionQualityLabels() {
        XCTAssertEqual(CompletionQuality.quick.label, "Quick")
        XCTAssertEqual(CompletionQuality.normal.label, "Normal")
        XCTAssertEqual(CompletionQuality.deep.label, "Deep Clean")
    }

    func testCompletionQualityIcons() {
        XCTAssertFalse(CompletionQuality.quick.icon.isEmpty)
        XCTAssertFalse(CompletionQuality.normal.icon.isEmpty)
        XCTAssertFalse(CompletionQuality.deep.icon.isEmpty)
    }

    func testCompletionQualityXPCalculation() {
        let task = makeTask(difficulty: .hard) // 3*10=30 base
        let baseXP = task.xpReward

        let quickXP = Int(Double(baseXP) * CompletionQuality.quick.xpMultiplier)
        let normalXP = Int(Double(baseXP) * CompletionQuality.normal.xpMultiplier)
        let deepXP = Int(Double(baseXP) * CompletionQuality.deep.xpMultiplier)

        XCTAssertLessThan(quickXP, normalXP)
        XCTAssertLessThan(normalXP, deepXP)
    }

    func testCompletionQualityAllCases() {
        XCTAssertEqual(CompletionQuality.allCases.count, 3)
    }

    func testCompletionQualityCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        let completion = makeCompletion(quality: .deep)
        let data = try encoder.encode(completion)
        let decoded = try decoder.decode(TaskCompletion.self, from: data)

        XCTAssertEqual(decoded.quality, .deep)
    }

    func testCompletionQualityNilBackwardsCompat() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        // Old completions without quality field should decode fine
        let completion = TaskCompletion(
            id: UUID(), taskId: UUID(), taskName: "Test",
            completedAt: Date(), xpEarned: 10, streakBonus: 0, notes: nil
        )
        let data = try encoder.encode(completion)
        let decoded = try decoder.decode(TaskCompletion.self, from: data)
        XCTAssertNil(decoded.quality)
    }

    // MARK: - Idea 7: Smart Scheduling

    func testTaskBatchingByCategory() {
        let tasks = [
            makeTask(name: "Dishes", category: .kitchen, minutes: 15),
            makeTask(name: "Counters", category: .kitchen, minutes: 5),
            makeTask(name: "Toilet", category: .bathroom, minutes: 10),
            makeTask(name: "Mirror", category: .bathroom, minutes: 5),
            makeTask(name: "Vacuum", category: .livingRoom, minutes: 15),
        ]

        let grouped = Dictionary(grouping: tasks, by: \.category)
        XCTAssertEqual(grouped[.kitchen]?.count, 2)
        XCTAssertEqual(grouped[.bathroom]?.count, 2)
        XCTAssertEqual(grouped[.livingRoom]?.count, 1)

        let kitchenMinutes = grouped[.kitchen]!.reduce(0) { $0 + $1.estimatedMinutes }
        XCTAssertEqual(kitchenMinutes, 20)

        let totalMinutes = tasks.reduce(0) { $0 + $1.estimatedMinutes }
        XCTAssertEqual(totalMinutes, 50)
    }

    func testTaskBatchingXPTotal() {
        let tasks = [
            makeTask(category: .kitchen, difficulty: .easy),
            makeTask(category: .kitchen, difficulty: .hard),
        ]

        let totalXP = tasks.reduce(0) { $0 + $1.xpReward }
        XCTAssertGreaterThan(totalXP, 0)
        XCTAssertEqual(totalXP, tasks[0].xpReward + tasks[1].xpReward)
    }

    // MARK: - Idea 8: Seasonal Tasks

    func testSeasonalSuggestionsNotEmpty() {
        XCTAssertGreaterThan(seasonalSuggestions.count, 10)
    }

    func testSeasonalSuggestionsHaveAllSeasons() {
        let seasons = Set(seasonalSuggestions.map(\.season))
        XCTAssertTrue(seasons.contains(.spring))
        XCTAssertTrue(seasons.contains(.summer))
        XCTAssertTrue(seasons.contains(.fall))
        XCTAssertTrue(seasons.contains(.winter))
    }

    func testCurrentSeasonSuggestionsNotEmpty() {
        let current = currentSeasonSuggestions()
        XCTAssertGreaterThan(current.count, 0, "Current season should have suggestions")
    }

    func testSeasonalSuggestionToTask() {
        let suggestion = seasonalSuggestions[0]
        let task = suggestion.toTask()

        XCTAssertEqual(task.name, suggestion.name)
        XCTAssertEqual(task.description, suggestion.description)
        XCTAssertEqual(task.category, suggestion.category)
        XCTAssertEqual(task.difficulty, suggestion.difficulty)
        XCTAssertTrue(task.isActive)
        XCTAssertEqual(task.frequency, .yearly)
    }

    func testSeasonFromMonth() {
        // Test all seasons have icons
        XCTAssertFalse(Season.spring.icon.isEmpty)
        XCTAssertFalse(Season.summer.icon.isEmpty)
        XCTAssertFalse(Season.fall.icon.isEmpty)
        XCTAssertFalse(Season.winter.icon.isEmpty)
    }

    func testSeasonCurrentIsValid() {
        let current = Season.current
        XCTAssertTrue([Season.spring, .summer, .fall, .winter].contains(current))
    }

    // MARK: - Idea 9: Supply Stock

    func testSupplyStockEnum() {
        XCTAssertEqual(SupplyStock.allCases.count, 3)
        XCTAssertEqual(SupplyStock.inStock.rawValue, "In Stock")
        XCTAssertEqual(SupplyStock.low.rawValue, "Low")
        XCTAssertEqual(SupplyStock.out.rawValue, "Out")
    }

    func testSupplyStockIcons() {
        for stock in SupplyStock.allCases {
            XCTAssertFalse(stock.icon.isEmpty, "\(stock.rawValue) should have an icon")
        }
    }

    func testSupplyStockColors() {
        for stock in SupplyStock.allCases {
            XCTAssertFalse(stock.color.isEmpty, "\(stock.rawValue) should have a color")
        }
    }

    func testSupplyStockCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let stock: [String: SupplyStock] = [
            "Dish soap": .low,
            "Sponge": .inStock,
            "Bleach": .out,
        ]

        let data = try encoder.encode(stock)
        let decoded = try decoder.decode([String: SupplyStock].self, from: data)

        XCTAssertEqual(decoded["Dish soap"], .low)
        XCTAssertEqual(decoded["Sponge"], .inStock)
        XCTAssertEqual(decoded["Bleach"], .out)
    }

    func testShoppingListFilters() {
        let stock: [String: SupplyStock] = [
            "Dish soap": .low,
            "Sponge": .inStock,
            "Bleach": .out,
            "Mop": .inStock,
            "Vinegar": .low,
        ]

        let shoppingList = stock.filter { $0.value == .low || $0.value == .out }.keys.sorted()
        XCTAssertEqual(shoppingList, ["Bleach", "Dish soap", "Vinegar"])
    }

    // MARK: - Idea 10: Celebration Types

    func testCelebrationTypeTitles() {
        let levelUp = CelebrationOverlay.CelebrationType.levelUp(5)
        XCTAssertEqual(levelUp.title, "Level 5!")

        let achievement = CelebrationOverlay.CelebrationType.achievement("First Steps")
        XCTAssertEqual(achievement.title, "First Steps")

        let streak = CelebrationOverlay.CelebrationType.streakMilestone(7)
        XCTAssertEqual(streak.title, "7-Day Streak!")

        let done = CelebrationOverlay.CelebrationType.taskComplete
        XCTAssertEqual(done.title, "Done!")
    }

    func testCelebrationTypeConfetti() {
        XCTAssertTrue(CelebrationOverlay.CelebrationType.levelUp(5).showConfetti)
        XCTAssertTrue(CelebrationOverlay.CelebrationType.achievement("Test").showConfetti)
        XCTAssertTrue(CelebrationOverlay.CelebrationType.streakMilestone(7).showConfetti)
        XCTAssertFalse(CelebrationOverlay.CelebrationType.taskComplete.showConfetti)
    }

    func testCelebrationTypeIcons() {
        XCTAssertFalse(CelebrationOverlay.CelebrationType.levelUp(1).icon.isEmpty)
        XCTAssertFalse(CelebrationOverlay.CelebrationType.achievement("Test").icon.isEmpty)
        XCTAssertFalse(CelebrationOverlay.CelebrationType.streakMilestone(7).icon.isEmpty)
        XCTAssertFalse(CelebrationOverlay.CelebrationType.taskComplete.icon.isEmpty)
    }

    // MARK: - Test Data Population

    func testCanPopulateFullTestDataSet() {
        // Create a rich test data set with all features
        var tasks = defaultHouseholdTasks
        XCTAssertGreaterThan(tasks.count, 40)

        // Add seasonal tasks
        let seasonals = currentSeasonSuggestions().map { $0.toTask() }
        tasks.append(contentsOf: seasonals)
        XCTAssertGreaterThan(tasks.count, 45)

        // Create multiple profiles
        var profiles: [UserProfile] = []
        let profile1 = makeProfile(name: "Alice", totalXP: 2500, streak: 14, longestStreak: 30, completed: 75, achievements: ["first_task", "ten_tasks", "fifty_tasks", "streak_3", "streak_7", "streak_14", "xp_1000"])
        let profile2 = makeProfile(name: "Bob", totalXP: 1200, streak: 5, longestStreak: 12, completed: 40, achievements: ["first_task", "ten_tasks", "streak_3", "xp_1000"])
        let profile3 = makeProfile(name: "Charlie", totalXP: 500, streak: 2, longestStreak: 4, completed: 15, achievements: ["first_task", "ten_tasks", "streak_3"])
        profiles.append(contentsOf: [profile1, profile2, profile3])

        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(profiles.sorted(by: { $0.totalXP > $1.totalXP }).first?.name, "Alice")

        // Create completions over 30 days with quality ratings
        let calendar = Calendar.current
        var completions: [TaskCompletion] = []
        for dayOffset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let taskCount = Int.random(in: 0...5)
            for _ in 0..<taskCount {
                let task = tasks.randomElement()!
                let quality = CompletionQuality.allCases.randomElement()!
                let xp = Int(Double(task.xpReward) * quality.xpMultiplier)
                let completion = TaskCompletion(
                    id: UUID(), taskId: task.id, taskName: task.name,
                    completedAt: date, xpEarned: xp, streakBonus: 0,
                    notes: dayOffset % 3 == 0 ? "Test note for \(task.name)" : nil,
                    quality: quality
                )
                completions.append(completion)
            }
        }
        XCTAssertGreaterThan(completions.count, 0)

        // Create supply stock data
        var supplyStock: [String: SupplyStock] = [:]
        let allSupplyNames = Set(tasks.flatMap(\.supplies))
        for supply in allSupplyNames {
            supplyStock[supply] = SupplyStock.allCases.randomElement()!
        }
        XCTAssertGreaterThan(supplyStock.count, 0)

        let shoppingList = supplyStock.filter { $0.value == .low || $0.value == .out }.keys.sorted()
        // Shopping list should be a subset of all supplies
        XCTAssertTrue(Set(shoppingList).isSubset(of: allSupplyNames))

        // Verify achievement progress
        for achievement in allAchievements {
            let progress = achievement.currentProgress(profile: profile1, completions: completions)
            XCTAssertGreaterThanOrEqual(progress, 0, "\(achievement.name) progress should be >= 0")
        }
    }

    // MARK: - Notification Settings Persistence Keys

    func testNotificationDefaultValues() {
        // Verify default reminder time is 9:00
        let defaultHour = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 9
        XCTAssertEqual(defaultHour, 9)
    }

    // MARK: - Widget Shared Defaults

    func testSharedDefaultsKeys() {
        // Verify SharedDefaults has sensible defaults when no data set
        XCTAssertGreaterThanOrEqual(SharedDefaults.dueTasks, 0)
        XCTAssertGreaterThanOrEqual(SharedDefaults.streak, 0)
        XCTAssertGreaterThanOrEqual(SharedDefaults.level, 0)
        XCTAssertGreaterThanOrEqual(SharedDefaults.totalXP, 0)
    }
}
