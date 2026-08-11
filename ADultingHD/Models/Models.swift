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

    /// How many specific weekdays this frequency expects (0 for frequencies
    /// that schedule by day-of-month instead).
    var weekdayCount: Int {
        switch self {
        case .weekly, .biweekly: return 1
        case .twiceWeekly: return 2
        default: return 0
        }
    }

    var usesDayOfMonth: Bool {
        switch self {
        case .monthly, .quarterly, .semiannually, .yearly: return true
        default: return false
        }
    }

    /// Safe first-run choices for schedules that need a concrete weekday.
    /// A weekly task without a weekday falls back to interval semantics and
    /// appears immediately, which makes the Home screen look as if it ignores
    /// the user's schedule. The task form uses these defaults until the user
    /// picks a different day.
    var defaultWeekdays: [Int] {
        switch self {
        case .twiceWeekly: [2, 5] // Monday and Thursday
        case .weekly, .biweekly: [2] // Monday
        default: []
        }
    }

    /// Days after a completion before `Recurrence` starts searching for the
    /// next weekday/day-of-month match. Slightly shorter than `days` so it
    /// lands on this cycle's occurrence whether the completion happened
    /// early, late, or exactly on schedule, without ever finding the same
    /// day that was just completed.
    var minGap: Int {
        switch self {
        case .daily: return 1
        case .twiceWeekly: return 2
        case .weekly: return 6
        case .biweekly: return 13
        case .monthly: return 23
        case .quarterly: return 83
        case .semiannually: return 175
        case .yearly: return 300
        }
    }
}

// MARK: - Weekday helpers

/// Apple `Calendar.component(.weekday:)` convention: 1 = Sunday … 7 = Saturday.
enum Weekday: Int, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortLabel: String { Calendar.current.shortWeekdaySymbols[rawValue - 1] }
    var fullLabel: String { Calendar.current.weekdaySymbols[rawValue - 1] }

    static func label(for weekdays: [Int]) -> String {
        weekdays.compactMap(Weekday.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.shortLabel)
            .joined(separator: ", ")
    }
}

extension Calendar {
    /// The calendar week (per this calendar's `.weekOfYear` boundary)
    /// containing `date`. The single source of truth for "this week" —
    /// shared by `DataStore`'s weekly consistency bonus
    /// (`earnedWeeklyConsistencyBonus`/`bonusPeriodKey`) and
    /// `WeeklyLeaderboard`'s XP aggregation — so both agree on where a week
    /// starts and ends.
    func weekInterval(containing date: Date) -> DateInterval? {
        dateInterval(of: .weekOfYear, for: date)
    }
}

func shortMonthName(_ month: Int) -> String {
    let symbols = Calendar.current.shortMonthSymbols
    guard (1...symbols.count).contains(month) else { return "" }
    return symbols[month - 1]
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

// MARK: - Checklist Item

struct ChecklistItem: Codable, Identifiable, Hashable {
    var id: UUID
    var text: String
    var instructions: String

    init(id: UUID = UUID(), text: String, instructions: String = "") {
        self.id = id
        self.text = text
        self.instructions = instructions
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
    /// When this task was added. Defaults to "now" for newly created tasks
    /// (including legacy JSON/CloudKit records that predate this field, via
    /// Codable's default-value fallback for a missing key). Used only as
    /// the recurrence anchor for a task that has never been completed — see
    /// `Recurrence.nextOccurrence`. `DataStore.updateTask` resets it to
    /// "now" whenever a never-completed task's recurrence rule changes, so
    /// editing a schedule always gives it a fresh start rather than
    /// re-anchoring to a stale creation date.
    var createdAt: Date = Date()
    /// Profile id of the member who should complete this task by default.
    /// Optional: `nil` means "anyone in the household." Populated via the
    /// assignee picker once the household has more than one member (members
    /// only arrive via CloudKit share acceptance).
    var defaultAssigneeId: UUID? = nil
    /// Apple weekday ints (1 = Sunday … 7 = Saturday) the task is scheduled on.
    /// Empty for daily/monthly-family frequencies. Count matches
    /// `frequency.weekdayCount` when set.
    var scheduledWeekdays: [Int] = []
    /// Day of month (1…28) for monthly/quarterly/semi-annual/yearly tasks.
    var scheduledDayOfMonth: Int? = nil
    /// Month (1…12) for yearly tasks.
    var scheduledMonth: Int? = nil
    /// Ordered steps the user ticks off while completing the task. Empty
    /// for simple single-action tasks.
    var checklist: [ChecklistItem] = []
    /// One-off manual reschedule set by dragging a task to a different day
    /// in `ScheduleView`'s week view (see issue #25). When set,
    /// `nextOccurrence` returns this date directly instead of deriving one
    /// from `frequency`/`scheduledWeekdays`/`scheduledDayOfMonth` — the
    /// override moves a single occurrence, never the recurring schedule
    /// itself. `DataStore.completeTask` clears it on completion so the next
    /// occurrence resumes the normal cadence computed from that completion.
    /// If left uncompleted, the moved occurrence is just as fixed as any
    /// normal occurrence: it becomes overdue via carry-forward once the
    /// moved-to day passes, same as `Recurrence`'s existing semantics.
    var scheduledOverrideDate: Date? = nil

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

    /// The fixed day this task's occurrence falls on — see
    /// `Recurrence.nextOccurrence` for the full model, including how
    /// `scheduledOverrideDate` takes precedence over the computed schedule.
    /// `nil` for inactive tasks, which are never due.
    func nextOccurrence(calendar: Calendar = .current) -> Date? {
        guard isActive else { return nil }
        return Recurrence.nextOccurrence(
            frequency: frequency,
            scheduledWeekdays: scheduledWeekdays,
            scheduledDayOfMonth: scheduledDayOfMonth,
            scheduledMonth: scheduledMonth,
            lastCompleted: lastCompleted,
            createdAt: createdAt,
            scheduledOverrideDate: scheduledOverrideDate,
            calendar: calendar
        )
    }

    /// Is this task due on or before the given reference date? Inactive
    /// tasks are never due. A missed occurrence stays due on every
    /// subsequent day (carry-forward) until it's completed — the occurrence
    /// date doesn't move just because time passes.
    func isDue(on referenceDate: Date, calendar: Calendar = .current) -> Bool {
        guard let occurrence = nextOccurrence(calendar: calendar) else { return false }
        return Recurrence.isDue(occurrence: occurrence, on: referenceDate, calendar: calendar)
    }

    var isOverdue: Bool { isOverdue(on: Date()) }

    /// Has this task's occurrence already passed as of the given reference
    /// date? A never-completed task is not overdue until its first
    /// occurrence has passed (see `Recurrence.nextOccurrence`).
    func isOverdue(on referenceDate: Date, calendar: Calendar = .current) -> Bool {
        guard let occurrence = nextOccurrence(calendar: calendar) else { return false }
        return Recurrence.isOverdue(occurrence: occurrence, on: referenceDate, calendar: calendar)
    }

    /// Whole calendar days this task has been overdue as of the given
    /// reference date. Zero when not overdue. Used for "longest-missed
    /// first" sort order and the overdue-age badge in the UI.
    func daysOverdue(on referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let occurrence = nextOccurrence(calendar: calendar) else { return 0 }
        return Recurrence.daysOverdue(occurrence: occurrence, on: referenceDate, calendar: calendar)
    }

    /// `isDue`, `isOverdue`, and `daysOverdue` as of a single reference
    /// date, computed from one `nextOccurrence()` lookup. Prefer this over
    /// calling the three separately when a view needs more than one of
    /// them — e.g. a row that shows both an overdue badge and a day count.
    func dueStatus(on referenceDate: Date = Date(), calendar: Calendar = .current) -> (isDue: Bool, isOverdue: Bool, daysOverdue: Int) {
        guard let occurrence = nextOccurrence(calendar: calendar) else { return (false, false, 0) }
        return (
            Recurrence.isDue(occurrence: occurrence, on: referenceDate, calendar: calendar),
            Recurrence.isOverdue(occurrence: occurrence, on: referenceDate, calendar: calendar),
            Recurrence.daysOverdue(occurrence: occurrence, on: referenceDate, calendar: calendar)
        )
    }

    /// The stored fields that fully determine `Recurrence.nextOccurrence`'s
    /// schedule — everything except `lastCompleted`/`createdAt`. Equal
    /// values mean two tasks (or a task before/after an edit) compute the
    /// same occurrence given the same completion history. Used by
    /// `DataStore.updateTask` to detect a recurrence-rule change without
    /// re-deriving which fields matter.
    struct RecurrenceRule: Equatable {
        let frequency: TaskFrequency
        let scheduledWeekdays: [Int]
        let scheduledDayOfMonth: Int?
        let scheduledMonth: Int?
    }

    var recurrenceRule: RecurrenceRule {
        RecurrenceRule(frequency: frequency, scheduledWeekdays: scheduledWeekdays, scheduledDayOfMonth: scheduledDayOfMonth, scheduledMonth: scheduledMonth)
    }

    /// Applies the concrete defaults used when a catalog or starter task is
    /// added without an explicit schedule. This keeps weekly tasks anchored to
    /// a real day instead of silently falling back to "due immediately, then
    /// every seven days."
    func withDefaultSchedule() -> HouseholdTask {
        var copy = self
        if copy.frequency.weekdayCount > 0 && copy.scheduledWeekdays.isEmpty {
            copy.scheduledWeekdays = copy.frequency.defaultWeekdays
        }
        return copy
    }

    var dueDate: Date? { nextOccurrence() }

    /// Human-readable description of when this task recurs — used in lists
    /// and detail views. Returns `nil` when no specific day is set.
    var scheduleSummary: String? {
        switch frequency {
        case .daily:
            return nil
        case .weekly, .biweekly, .twiceWeekly:
            guard !scheduledWeekdays.isEmpty else { return nil }
            let days = Weekday.label(for: scheduledWeekdays)
            switch frequency {
            case .twiceWeekly: return days
            case .biweekly: return "every other \(days)"
            default: return days
            }
        case .monthly, .quarterly, .semiannually:
            guard let dom = scheduledDayOfMonth else { return nil }
            return "day \(dom)"
        case .yearly:
            guard let dom = scheduledDayOfMonth, let month = scheduledMonth else { return nil }
            return "\(shortMonthName(month)) \(dom)"
        }
    }

    var daysSinceLastCompleted: Int? {
        guard let last = lastCompleted else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: Date())).day
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HouseholdTask, rhs: HouseholdTask) -> Bool {
        lhs.id == rhs.id
    }

    /// Whether this task matches an `AssigneeFilter` chip selection, given the
    /// current device user's profile id. `.all` always matches; `.mine`
    /// matches only tasks explicitly assigned to `currentProfileId`;
    /// `.unassigned` matches only tasks with no default assignee.
    func matches(_ filter: AssigneeFilter, currentProfileId: UUID) -> Bool {
        switch filter {
        case .all: return true
        case .mine: return defaultAssigneeId == currentProfileId
        case .unassigned: return defaultAssigneeId == nil
        }
    }
}

/// "Mine" / "Unassigned" / "All" filter chip options for `TaskListView`,
/// shown only in households with more than one member (see
/// `DataStore.householdProfiles`).
enum AssigneeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case mine = "Mine"
    case unassigned = "Unassigned"

    var id: String { rawValue }
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
    var profileId: UUID?  // nil = legacy data; set to completing member's profile id

    /// Daily/weekly/monthly consistency bonus XP this completion happened to
    /// trigger, keyed by period name ("daily"/"weekly"/"monthly") — see
    /// `DataStore.applyPeriodBonusesIfEarned`. nil for legacy data or a
    /// completion that triggered no period bonus. Recorded so
    /// `DataStore.uncompleteTask` can reverse exactly the bonus this specific
    /// completion earned (and only this one — the award is a first-completion-
    /// in-the-period gate, so no other completion in the same period carries it).
    var periodBonuses: [String: Int]?

    /// XP this completion contributed, including any streak bonus. Excludes
    /// `periodBonuses` (those are added straight to `profile.totalXP`, not
    /// attributed to a single task) — the canonical sum wherever a single
    /// completion's XP is displayed or totaled.
    var totalXP: Int { xpEarned + streakBonus }
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
    let avatarState: AvatarState
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
    var name: String = ""
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

    /// Streak bonus XP awarded on top of a task's base XP when completing
    /// with `streak` consecutive active days — +2 XP per day, capped at 50.
    /// Shared by `DataStore.completeTask` (the award) and the streak-at-risk
    /// notification copy (the incentive), so they can't drift apart.
    static func streakBonusXP(for streak: Int) -> Int {
        streak > 0 ? min(streak * 2, 50) : 0
    }

    /// Best-effort name for a fresh profile. macOS exposes the logged-in
    /// user's full name; iOS does not surface the iCloud name to third-party
    /// apps, so we return an empty string and rely on the onboarding prompt
    /// or Settings field to fill it in.
    static func defaultPlayerName() -> String {
        #if os(macOS)
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "" : full
        #else
        return ""
        #endif
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
