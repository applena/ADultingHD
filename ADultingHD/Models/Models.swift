import Foundation

// MARK: - Task Category

enum TaskCategory: String, Codable, CaseIterable, Identifiable {
    case kitchen = "Kitchen"
    case bathroom = "Bathroom"
    case bedroom = "Bedroom"
    case livingRoom = "Living Room"
    case laundry = "Laundry"
    case outdoor = "Outdoor"
    case garage = "Garage"
    case office = "Office"
    case general = "General"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .kitchen: "fork.knife"
        case .bathroom: "shower"
        case .bedroom: "bed.double"
        case .livingRoom: "sofa"
        case .laundry: "washer"
        case .outdoor: "leaf"
        case .garage: "car"
        case .office: "desktopcomputer"
        case .general: "house"
        }
    }

    var color: String {
        switch self {
        case .kitchen: "orange"
        case .bathroom: "blue"
        case .bedroom: "purple"
        case .livingRoom: "green"
        case .laundry: "cyan"
        case .outdoor: "mint"
        case .garage: "gray"
        case .office: "indigo"
        case .general: "brown"
        }
    }
}

// MARK: - Task Frequency

enum TaskFrequency: String, Codable, CaseIterable, Identifiable {
    case daily = "Daily"
    case twiceWeekly = "Twice Weekly"
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case semiannually = "Semi-Annually"
    case yearly = "Yearly"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .daily: 1
        case .twiceWeekly: 3
        case .weekly: 7
        case .biweekly: 14
        case .monthly: 30
        case .quarterly: 90
        case .semiannually: 182
        case .yearly: 365
        }
    }

    var icon: String {
        switch self {
        case .daily: "clock"
        case .twiceWeekly: "clock.badge.checkmark"
        case .weekly: "calendar.badge.clock"
        case .biweekly: "calendar"
        case .monthly: "calendar.circle"
        case .quarterly: "calendar.badge.plus"
        case .semiannually: "calendar.badge.exclamationmark"
        case .yearly: "star.circle"
        }
    }
}

// MARK: - Difficulty

enum Difficulty: Int, Codable, CaseIterable, Identifiable, Comparable {
    case easy = 1
    case medium = 2
    case hard = 3
    case epic = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .epic: "Epic"
        }
    }

    var icon: String {
        switch self {
        case .easy: "tortoise"
        case .medium: "hare"
        case .hard: "flame"
        case .epic: "bolt.fill"
        }
    }

    var color: String {
        switch self {
        case .easy: "green"
        case .medium: "yellow"
        case .hard: "orange"
        case .epic: "red"
        }
    }

    static func < (lhs: Difficulty, rhs: Difficulty) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Household Task

struct HouseholdTask: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var category: TaskCategory
    var frequency: TaskFrequency
    var estimatedMinutes: Int
    var difficulty: Difficulty
    var supplies: [String]
    var isActive: Bool
    var lastCompleted: Date?

    var xpReward: Int {
        Self.computeXP(difficulty: difficulty, frequency: frequency, estimatedMinutes: estimatedMinutes)
    }

    static func computeXP(difficulty: Difficulty, frequency: TaskFrequency, estimatedMinutes: Int) -> Int {
        let baseXP = difficulty.rawValue * 10
        let frequencyMultiplier = max(1, frequency.days / 7)
        let timeBonus = estimatedMinutes / 10
        return baseXP + (frequencyMultiplier * 5) + (timeBonus * 2)
    }

    static func parseSupplies(from text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var isDue: Bool { isDue(on: Date()) }

    /// Is this task due on or before the given reference date? Inactive tasks
    /// are never due; tasks that have never been completed are always due.
    func isDue(on referenceDate: Date) -> Bool {
        guard isActive else { return false }
        guard let last = lastCompleted else { return true }
        let daysSince = Calendar.current.dateComponents([.day], from: last, to: referenceDate).day ?? 0
        return daysSince >= frequency.days
    }

    var isOverdue: Bool {
        guard isActive else { return false }
        guard let last = lastCompleted else { return true }
        let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return daysSince > frequency.days + 1
    }

    var dueDate: Date? {
        guard isActive, let last = lastCompleted else { return nil }
        return Calendar.current.date(byAdding: .day, value: frequency.days, to: last)
    }

    var daysSinceLastCompleted: Int? {
        guard let last = lastCompleted else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HouseholdTask, rhs: HouseholdTask) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Task Completion

enum CompletionQuality: Int, Codable, CaseIterable, Identifiable {
    case quick = 1
    case normal = 2
    case deep = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .quick: "Quick"
        case .normal: "Normal"
        case .deep: "Deep Clean"
        }
    }

    var icon: String {
        switch self {
        case .quick: "hare"
        case .normal: "checkmark"
        case .deep: "sparkles"
        }
    }

    var xpMultiplier: Double {
        switch self {
        case .quick: 0.75
        case .normal: 1.0
        case .deep: 1.5
        }
    }
}

struct TaskCompletion: Codable, Identifiable {
    let id: UUID
    let taskId: UUID
    let taskName: String
    let completedAt: Date
    let xpEarned: Int
    let streakBonus: Int
    let notes: String?
    var quality: CompletionQuality?
    var profileId: UUID?  // nil = legacy data; set to completing member's profile id
}

// MARK: - Household Activity Feed

enum HouseholdActivityEvent {
    case completedTask(name: String, xp: Int)
    case leveledUp(level: Int)
    case achievementUnlocked(name: String)
    case passedYou(newRank: Int)
}

struct HouseholdActivity: Identifiable {
    let id = UUID()
    let profileId: UUID
    let profileName: String
    let avatar: String
    let event: HouseholdActivityEvent
    let timestamp: Date

    var displayTitle: String {
        switch event {
        case .completedTask(let name, let xp):
            return "\(profileName) completed '\(name)' +\(xp) XP"
        case .leveledUp(let level):
            return "\(profileName) reached Level \(level)!"
        case .achievementUnlocked(let name):
            return "\(profileName) unlocked \(name)"
        case .passedYou(let rank):
            return "\(profileName) passed you (you're now #\(rank))"
        }
    }

    var systemImage: String {
        switch event {
        case .completedTask: "checkmark.circle.fill"
        case .leveledUp: "arrow.up.circle.fill"
        case .achievementUnlocked: "star.fill"
        case .passedYou: "arrow.up.right.circle.fill"
        }
    }

    var notificationTitle: String {
        switch event {
        case .completedTask: return "\(profileName) is adulting!"
        case .leveledUp: return "\(profileName) leveled up!"
        case .achievementUnlocked: return "\(profileName) unlocked an achievement!"
        case .passedYou: return "\(profileName) passed you!"
        }
    }

    var notificationBody: String {
        switch event {
        case .completedTask(let name, let xp): return "Completed '\(name)' for +\(xp) XP"
        case .leveledUp(let level): return "Now Level \(level) on the household leaderboard"
        case .achievementUnlocked(let name): return name
        case .passedYou(let newRank): return "You dropped to #\(newRank) on the leaderboard. Time to catch up!"
        }
    }
}

// MARK: - Supply Stock

// MARK: - Array Extensions

extension Array where Element == HouseholdTask {
    var totalMinutes: Int { reduce(0) { $0 + $1.estimatedMinutes } }
    var totalXP: Int { reduce(0) { $0 + $1.xpReward } }
}

enum SupplyStock: String, Codable, CaseIterable {
    case inStock = "In Stock"
    case low = "Low"
    case out = "Out"

    var icon: String {
        switch self {
        case .inStock: "checkmark.circle.fill"
        case .low: "exclamationmark.triangle.fill"
        case .out: "xmark.circle.fill"
        }
    }

}

// MARK: - User Profile

struct UserProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String = "Player 1"
    var avatar: String = "person.crop.circle.fill"
    var totalXP: Int = 0
    var coins: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastActiveDate: Date?
    var unlockedAchievements: [String] = []
    var totalTasksCompleted: Int = 0
    var joinDate: Date = Date()
    var avatarState: AvatarState = AvatarState()

    var level: Int {
        // Each level requires progressively more XP: level N needs N*100 XP
        // Total XP for level L = sum(1..L) * 100 = L*(L+1)/2 * 100
        var lvl = 0
        var xpNeeded = 0
        while xpNeeded + (lvl + 1) * 100 <= totalXP {
            lvl += 1
            xpNeeded += lvl * 100
        }
        return lvl
    }

    var xpForCurrentLevel: Int {
        let lvl = level
        return lvl * (lvl + 1) / 2 * 100
    }

    var xpForNextLevel: Int {
        let lvl = level
        return (lvl + 1) * (lvl + 2) / 2 * 100
    }

    var xpProgress: Double {
        let current = totalXP - xpForCurrentLevel
        let needed = xpForNextLevel - xpForCurrentLevel
        guard needed > 0 else { return 0 }
        return Double(current) / Double(needed)
    }

    var levelTitle: String {
        switch level {
        case 0: "Rookie Roommate"
        case 1...3: "Tidy Trainee"
        case 4...7: "Chore Champion"
        case 8...12: "Domestic Dynamo"
        case 13...19: "Household Hero"
        case 20...29: "Adulting Apprentice"
        case 30...44: "Adulting Adept"
        case 45...64: "Adulting Expert"
        case 65...99: "Adulting Master"
        default: "Adulting Legend"
        }
    }
}

// MARK: - Achievement

struct Achievement: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let requirement: String
    let flavorText: String
    let targetValue: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Achievement, rhs: Achievement) -> Bool {
        lhs.id == rhs.id
    }

    func currentProgress(profile: UserProfile, completions: [TaskCompletion]) -> Int {
        switch id {
        case "first_task", "ten_tasks", "fifty_tasks", "hundred_tasks":
            return profile.totalTasksCompleted
        case "streak_3", "streak_7", "streak_14", "streak_30", "streak_100":
            return max(profile.currentStreak, profile.longestStreak)
        case "level_5", "level_10", "level_25":
            return profile.level
        case "xp_1000", "xp_10000":
            return profile.totalXP
        case "five_in_day":
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: completions) { calendar.startOfDay(for: $0.completedAt) }
            return grouped.values.map(\.count).max() ?? 0
        case "early_bird":
            return profile.unlockedAchievements.contains("early_bird") ? 1 : 0
        case "all_kitchen", "all_bathroom":
            return profile.unlockedAchievements.contains(id) ? 1 : 0
        default:
            return 0
        }
    }

    var progressFraction: (UserProfile, [TaskCompletion]) -> Double {
        { profile, completions in
            let current = self.currentProgress(profile: profile, completions: completions)
            guard targetValue > 0 else { return 0 }
            return min(1.0, Double(current) / Double(targetValue))
        }
    }
}

let allAchievements: [Achievement] = [
    Achievement(id: "first_task", name: "First Steps", description: "Complete your first task", icon: "star", requirement: "Complete 1 task", flavorText: "Every journey begins with a single sweep.", targetValue: 1),
    Achievement(id: "ten_tasks", name: "Getting Started", description: "Complete 10 tasks", icon: "star.fill", requirement: "Complete 10 tasks", flavorText: "You're building momentum. The house can feel it.", targetValue: 10),
    Achievement(id: "fifty_tasks", name: "Half Century", description: "Complete 50 tasks", icon: "trophy", requirement: "Complete 50 tasks", flavorText: "Fifty down. Your home thanks you.", targetValue: 50),
    Achievement(id: "hundred_tasks", name: "Centurion", description: "Complete 100 tasks", icon: "trophy.fill", requirement: "Complete 100 tasks", flavorText: "A hundred acts of adulting. Legendary.", targetValue: 100),
    Achievement(id: "streak_3", name: "Three-peat", description: "Maintain a 3-day streak", icon: "flame", requirement: "3-day streak", flavorText: "Three days in a row — you're on fire!", targetValue: 3),
    Achievement(id: "streak_7", name: "Week Warrior", description: "Maintain a 7-day streak", icon: "flame.fill", requirement: "7-day streak", flavorText: "A full week of consistency. That's real discipline.", targetValue: 7),
    Achievement(id: "streak_14", name: "Fortnight Force", description: "Maintain a 14-day streak", icon: "bolt", requirement: "14-day streak", flavorText: "Two weeks strong. You're unstoppable.", targetValue: 14),
    Achievement(id: "streak_30", name: "Monthly Master", description: "Maintain a 30-day streak", icon: "bolt.fill", requirement: "30-day streak", flavorText: "A whole month! Adulting is now a habit.", targetValue: 30),
    Achievement(id: "streak_100", name: "Unstoppable", description: "Maintain a 100-day streak", icon: "bolt.circle.fill", requirement: "100-day streak", flavorText: "100 days. You've transcended mere adulting.", targetValue: 100),
    Achievement(id: "level_5", name: "Leveling Up", description: "Reach level 5", icon: "arrow.up.circle", requirement: "Reach level 5", flavorText: "Level 5! You've graduated from 'figuring it out.'", targetValue: 5),
    Achievement(id: "level_10", name: "Double Digits", description: "Reach level 10", icon: "arrow.up.circle.fill", requirement: "Reach level 10", flavorText: "Double digits. The neighbors are impressed.", targetValue: 10),
    Achievement(id: "level_25", name: "Quarter Century", description: "Reach level 25", icon: "crown", requirement: "Reach level 25", flavorText: "Level 25. You practically run this house.", targetValue: 25),
    Achievement(id: "all_kitchen", name: "Kitchen King", description: "Complete all kitchen tasks in one day", icon: "fork.knife", requirement: "All kitchen tasks in a day", flavorText: "The kitchen has never been this clean. Ever.", targetValue: 1),
    Achievement(id: "all_bathroom", name: "Bathroom Boss", description: "Complete all bathroom tasks in one day", icon: "shower", requirement: "All bathroom tasks in a day", flavorText: "Sparkling from tile to toilet. Respect.", targetValue: 1),
    Achievement(id: "early_bird", name: "Early Bird", description: "Complete a task before it's due", icon: "sunrise", requirement: "Complete a task early", flavorText: "Ahead of schedule? Who even are you?", targetValue: 1),
    Achievement(id: "five_in_day", name: "Productive Day", description: "Complete 5 tasks in one day", icon: "sparkles", requirement: "5 tasks in one day", flavorText: "Five in a day! That's a power session.", targetValue: 5),
    Achievement(id: "xp_1000", name: "XP Collector", description: "Earn 1,000 total XP", icon: "bitcoinsign.circle", requirement: "1,000 total XP", flavorText: "A thousand points of clean.", targetValue: 1000),
    Achievement(id: "xp_10000", name: "XP Hoarder", description: "Earn 10,000 total XP", icon: "bitcoinsign.circle.fill", requirement: "10,000 total XP", flavorText: "Ten thousand XP. You're basically a chore wizard.", targetValue: 10000),
]
