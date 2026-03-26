import Foundation

enum SharedDefaults {
    static let suiteName = "group.net.shadowpuppet.ADultingHD"
    private nonisolated(unsafe) static let defaults = UserDefaults(suiteName: suiteName)

    private enum Key {
        static let dueTasks = "widget_dueTasks"
        static let streak = "widget_streak"
        static let level = "widget_level"
        static let levelTitle = "widget_levelTitle"
        static let xpProgress = "widget_xpProgress"
        static let totalXP = "widget_totalXP"
        static let todayCompleted = "widget_todayCompleted"
        static let nextTask = "widget_nextTask"
    }

    static func updateWidgetData(dueTasks: Int, streak: Int, level: Int, levelTitle: String, xpProgress: Double, totalXP: Int, todayCompleted: Int, nextTaskName: String?) {
        guard let defaults else { return }
        defaults.set(dueTasks, forKey: Key.dueTasks)
        defaults.set(streak, forKey: Key.streak)
        defaults.set(level, forKey: Key.level)
        defaults.set(levelTitle, forKey: Key.levelTitle)
        defaults.set(xpProgress, forKey: Key.xpProgress)
        defaults.set(totalXP, forKey: Key.totalXP)
        defaults.set(todayCompleted, forKey: Key.todayCompleted)
        defaults.set(nextTaskName, forKey: Key.nextTask)
    }

    static var dueTasks: Int { defaults?.integer(forKey: Key.dueTasks) ?? 0 }
    static var streak: Int { defaults?.integer(forKey: Key.streak) ?? 0 }
    static var level: Int { defaults?.integer(forKey: Key.level) ?? 0 }
    static var levelTitle: String { defaults?.string(forKey: Key.levelTitle) ?? "Rookie Roommate" }
    static var xpProgress: Double { defaults?.double(forKey: Key.xpProgress) ?? 0 }
    static var totalXP: Int { defaults?.integer(forKey: Key.totalXP) ?? 0 }
    static var todayCompleted: Int { defaults?.integer(forKey: Key.todayCompleted) ?? 0 }
    static var nextTask: String? { defaults?.string(forKey: Key.nextTask) }
}
