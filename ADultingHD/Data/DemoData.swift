import Foundation

enum DemoData {
    struct Bundle {
        let tasks: [HouseholdTask]
        let profile: UserProfile
        let completions: [TaskCompletion]
        let supplyStock: [String: SupplyStock]
        let householdProfiles: [UserProfile]
    }

    static func generate() -> Bundle {
        let tasks = makeTasks()
        let completions = makeCompletions(for: tasks)
        let profile = makeProfile()
        let stock = makeSupplyStock()
        let household = makeHousehold(main: profile)
        return Bundle(tasks: tasks, profile: profile, completions: completions,
                      supplyStock: stock, householdProfiles: household)
    }

    // MARK: - Tasks

    private static func makeTasks() -> [HouseholdTask] {
        let calendar = Calendar.current
        let now = Date()

        func daysAgo(_ d: Int) -> Date { calendar.date(byAdding: .day, value: -d, to: now)! }

        return [
            // Kitchen
            task("Do dishes", desc: "Wash, dry, and put away all dishes", cat: .kitchen, freq: .daily, min: 15, diff: .easy,
                 supplies: ["Dish soap", "Sponge"], lastCompleted: daysAgo(0)),
            task("Wipe counters", desc: "Wipe down all kitchen counters and surfaces", cat: .kitchen, freq: .daily, min: 5, diff: .easy,
                 supplies: ["All-purpose cleaner", "Paper towels"], lastCompleted: daysAgo(1)),
            task("Clean stovetop", desc: "Scrub burners and wipe stovetop surface", cat: .kitchen, freq: .weekly, min: 15, diff: .medium,
                 supplies: ["Degreaser", "Sponge"], lastCompleted: daysAgo(8)),
            task("Clean microwave", desc: "Steam clean and wipe interior", cat: .kitchen, freq: .biweekly, min: 10, diff: .easy,
                 supplies: ["All-purpose cleaner"], lastCompleted: daysAgo(12)),
            task("Scrub sink", desc: "Deep clean kitchen sink and faucet", cat: .kitchen, freq: .weekly, min: 10, diff: .medium,
                 supplies: ["Baking soda", "Sponge"], lastCompleted: daysAgo(5)),
            // Bathroom
            task("Wipe sink & mirror", desc: "Clean bathroom sink, counter, and mirror", cat: .bathroom, freq: .weekly, min: 10, diff: .easy,
                 supplies: ["Glass cleaner", "Paper towels"], lastCompleted: daysAgo(6)),
            task("Scrub toilet", desc: "Clean inside bowl, seat, and base", cat: .bathroom, freq: .weekly, min: 10, diff: .medium,
                 supplies: ["Toilet cleaner", "Toilet brush"], lastCompleted: daysAgo(3)),
            task("Clean shower/tub", desc: "Scrub walls, floor, and fixtures", cat: .bathroom, freq: .biweekly, min: 25, diff: .hard,
                 supplies: ["Bathroom cleaner", "Scrub brush"], lastCompleted: daysAgo(10)),
            // Bedroom
            task("Make bed", desc: "Straighten sheets, fluff pillows, arrange covers", cat: .bedroom, freq: .daily, min: 3, diff: .easy,
                 supplies: [], lastCompleted: daysAgo(0)),
            task("Change sheets", desc: "Strip and replace all bedding", cat: .bedroom, freq: .biweekly, min: 15, diff: .medium,
                 supplies: ["Fresh sheets"], lastCompleted: daysAgo(13)),
            task("Dust surfaces", desc: "Dust nightstands, dresser, and shelves", cat: .bedroom, freq: .weekly, min: 10, diff: .easy,
                 supplies: ["Microfiber cloth"], lastCompleted: daysAgo(4)),
            // Living Room
            task("Tidy up", desc: "Put away items, straighten cushions, clear clutter", cat: .livingRoom, freq: .daily, min: 10, diff: .easy,
                 supplies: [], lastCompleted: daysAgo(0)),
            task("Vacuum floor", desc: "Vacuum all carpeted and hard floor areas", cat: .livingRoom, freq: .weekly, min: 20, diff: .medium,
                 supplies: [], lastCompleted: daysAgo(7)),
            // Laundry
            task("Do laundry load", desc: "Sort, wash, and transfer to dryer", cat: .laundry, freq: .weekly, min: 15, diff: .easy,
                 supplies: ["Laundry detergent", "Dryer sheets"], lastCompleted: daysAgo(2)),
            task("Fold & put away", desc: "Fold dried clothes and put in drawers/closets", cat: .laundry, freq: .weekly, min: 20, diff: .easy,
                 supplies: [], lastCompleted: daysAgo(2)),
            // General
            task("Take out trash", desc: "Empty all trash cans and replace bags", cat: .general, freq: .twiceWeekly, min: 5, diff: .easy,
                 supplies: ["Trash bags"], lastCompleted: daysAgo(1)),
            task("Vacuum apartment", desc: "Full vacuum of all rooms", cat: .general, freq: .weekly, min: 30, diff: .medium,
                 supplies: [], lastCompleted: daysAgo(6)),
        ]
    }

    private static func task(_ name: String, desc: String, cat: TaskCategory, freq: TaskFrequency,
                             min: Int, diff: Difficulty, supplies: [String], lastCompleted: Date?) -> HouseholdTask {
        HouseholdTask(id: UUID(), name: name, description: desc, category: cat, frequency: freq,
                      estimatedMinutes: min, difficulty: diff, supplies: supplies, isActive: true, lastCompleted: lastCompleted)
    }

    // MARK: - Completions

    private static func makeCompletions(for tasks: [HouseholdTask]) -> [TaskCompletion] {
        let calendar = Calendar.current
        let now = Date()
        var completions: [TaskCompletion] = []

        // Generate 30 days of completions with increasing activity
        for dayOffset in 0..<30 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: now)!
            let baseHour = 8

            // More completions for recent days (nice trend line)
            let count: Int
            switch dayOffset {
            case 0...5: count = [4, 5, 3, 5, 4, 3][dayOffset]
            case 6...13: count = [3, 2, 3, 2, 3, 2, 3, 2][dayOffset - 6]
            case 14...20: count = [2, 1, 2, 1, 2, 1, 2][dayOffset - 14]
            default: count = dayOffset % 3 == 0 ? 0 : 1
            }

            for i in 0..<count {
                let taskIndex = (dayOffset * 3 + i) % tasks.count
                let task = tasks[taskIndex]
                let hour = baseHour + i * 2 + (dayOffset % 3)
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = min(hour, 22)
                components.minute = (dayOffset * 7 + i * 13) % 60
                let completedAt = calendar.date(from: components) ?? day

                let xpEarned = task.xpReward
                let streakBonus = dayOffset < 14 ? UserProfile.streakBonusXP(for: dayOffset) : 0

                completions.append(TaskCompletion(
                    id: UUID(), taskId: task.id, taskName: task.name,
                    completedAt: completedAt, xpEarned: xpEarned, streakBonus: streakBonus,
                    notes: nil
                ))
            }
        }

        return completions.sorted { $0.completedAt > $1.completedAt }
    }

    // MARK: - Profile

    private static func makeProfile() -> UserProfile {
        var p = UserProfile()
        p.name = "Player 1"
        p.totalXP = 4200
        p.coins = 2550
        p.currentStreak = 14
        p.longestStreak = 14
        p.lastActiveDate = Date()
        p.totalTasksCompleted = 73
        p.joinDate = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        p.unlockedAchievements = [
            "first_task", "ten_tasks", "fifty_tasks",
            "streak_3", "streak_7", "streak_14",
            "level_5", "xp_1000",
            "early_bird", "five_in_day"
        ]
        p.avatarState = AvatarState()
        p.avatarState.ownedItemIds = ["cat", "bear", "fox", "bear_lumberjack", "bear_knight", "fox_detective"]
        p.avatarState.equippedItemIds = [.character: "bear_knight"]
        return p
    }

    // MARK: - Supply Stock

    private static func makeSupplyStock() -> [String: SupplyStock] {
        [
            "Dish soap": .inStock,
            "Sponge": .low,
            "All-purpose cleaner": .inStock,
            "Paper towels": .low,
            "Degreaser": .inStock,
            "Baking soda": .inStock,
            "Glass cleaner": .inStock,
            "Toilet cleaner": .out,
            "Toilet brush": .inStock,
            "Bathroom cleaner": .inStock,
            "Scrub brush": .inStock,
            "Fresh sheets": .inStock,
            "Microfiber cloth": .low,
            "Laundry detergent": .inStock,
            "Dryer sheets": .out,
            "Trash bags": .low,
        ]
    }

    // MARK: - Household

    private static func makeHousehold(main: UserProfile) -> [UserProfile] {
        var sarah = UserProfile()
        sarah.name = "Sarah"
        sarah.totalXP = 3200
        sarah.totalTasksCompleted = 58
        sarah.currentStreak = 9
        sarah.longestStreak = 21
        sarah.joinDate = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        sarah.avatarState.ownedItemIds = ["cat", "bunny", "bunny_gardener", "bunny_wizard"]
        sarah.avatarState.equippedItemIds = [.character: "bunny_gardener"]

        var mike = UserProfile()
        mike.name = "Mike"
        mike.totalXP = 1800
        mike.totalTasksCompleted = 32
        mike.currentStreak = 3
        mike.longestStreak = 11
        mike.joinDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        mike.avatarState.ownedItemIds = ["cat", "dog", "dog_firefighter"]
        mike.avatarState.equippedItemIds = [.character: "dog_firefighter"]

        return [main, sarah, mike]
    }
}
