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
        let baseXP = difficulty.rawValue * 10
        let frequencyMultiplier = max(1, frequency.days / 7)
        let timeBonus = estimatedMinutes / 10
        return baseXP + (frequencyMultiplier * 5) + (timeBonus * 2)
    }

    var isDue: Bool {
        guard isActive else { return false }
        guard let last = lastCompleted else { return true }
        let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
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

struct TaskCompletion: Codable, Identifiable {
    let id: UUID
    let taskId: UUID
    let taskName: String
    let completedAt: Date
    let xpEarned: Int
    let streakBonus: Int
    let notes: String?
}

// MARK: - User Profile

struct UserProfile: Codable {
    var totalXP: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastActiveDate: Date?
    var unlockedAchievements: [String] = []
    var totalTasksCompleted: Int = 0
    var joinDate: Date = Date()

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

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Achievement, rhs: Achievement) -> Bool {
        lhs.id == rhs.id
    }
}

let allAchievements: [Achievement] = [
    Achievement(id: "first_task", name: "First Steps", description: "Complete your first task", icon: "star", requirement: "Complete 1 task"),
    Achievement(id: "ten_tasks", name: "Getting Started", description: "Complete 10 tasks", icon: "star.fill", requirement: "Complete 10 tasks"),
    Achievement(id: "fifty_tasks", name: "Half Century", description: "Complete 50 tasks", icon: "trophy", requirement: "Complete 50 tasks"),
    Achievement(id: "hundred_tasks", name: "Centurion", description: "Complete 100 tasks", icon: "trophy.fill", requirement: "Complete 100 tasks"),
    Achievement(id: "streak_3", name: "Three-peat", description: "Maintain a 3-day streak", icon: "flame", requirement: "3-day streak"),
    Achievement(id: "streak_7", name: "Week Warrior", description: "Maintain a 7-day streak", icon: "flame.fill", requirement: "7-day streak"),
    Achievement(id: "streak_14", name: "Fortnight Force", description: "Maintain a 14-day streak", icon: "bolt", requirement: "14-day streak"),
    Achievement(id: "streak_30", name: "Monthly Master", description: "Maintain a 30-day streak", icon: "bolt.fill", requirement: "30-day streak"),
    Achievement(id: "streak_100", name: "Unstoppable", description: "Maintain a 100-day streak", icon: "bolt.circle.fill", requirement: "100-day streak"),
    Achievement(id: "level_5", name: "Leveling Up", description: "Reach level 5", icon: "arrow.up.circle", requirement: "Reach level 5"),
    Achievement(id: "level_10", name: "Double Digits", description: "Reach level 10", icon: "arrow.up.circle.fill", requirement: "Reach level 10"),
    Achievement(id: "level_25", name: "Quarter Century", description: "Reach level 25", icon: "crown", requirement: "Reach level 25"),
    Achievement(id: "all_kitchen", name: "Kitchen King", description: "Complete all kitchen tasks in one day", icon: "fork.knife", requirement: "All kitchen tasks in a day"),
    Achievement(id: "all_bathroom", name: "Bathroom Boss", description: "Complete all bathroom tasks in one day", icon: "shower", requirement: "All bathroom tasks in a day"),
    Achievement(id: "early_bird", name: "Early Bird", description: "Complete a task before it's due", icon: "sunrise", requirement: "Complete a task early"),
    Achievement(id: "five_in_day", name: "Productive Day", description: "Complete 5 tasks in one day", icon: "sparkles", requirement: "5 tasks in one day"),
    Achievement(id: "xp_1000", name: "XP Collector", description: "Earn 1,000 total XP", icon: "bitcoinsign.circle", requirement: "1,000 total XP"),
    Achievement(id: "xp_10000", name: "XP Hoarder", description: "Earn 10,000 total XP", icon: "bitcoinsign.circle.fill", requirement: "10,000 total XP"),
]
