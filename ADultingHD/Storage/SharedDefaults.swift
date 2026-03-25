import Foundation

enum SharedDefaults {
    static let suiteName = "group.net.shadowpuppet.ADultingHD"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func updateWidgetData(dueTasks: Int, overdueTasks: Int, streak: Int, level: Int, levelTitle: String, xpProgress: Double, totalXP: Int, todayCompleted: Int, nextTaskName: String?) {
        guard let defaults else { return }
        defaults.set(dueTasks, forKey: "widget_dueTasks")
        defaults.set(overdueTasks, forKey: "widget_overdueTasks")
        defaults.set(streak, forKey: "widget_streak")
        defaults.set(level, forKey: "widget_level")
        defaults.set(levelTitle, forKey: "widget_levelTitle")
        defaults.set(xpProgress, forKey: "widget_xpProgress")
        defaults.set(totalXP, forKey: "widget_totalXP")
        defaults.set(todayCompleted, forKey: "widget_todayCompleted")
        defaults.set(nextTaskName, forKey: "widget_nextTask")
    }

    static var dueTasks: Int { defaults?.integer(forKey: "widget_dueTasks") ?? 0 }
    static var overdueTasks: Int { defaults?.integer(forKey: "widget_overdueTasks") ?? 0 }
    static var streak: Int { defaults?.integer(forKey: "widget_streak") ?? 0 }
    static var level: Int { defaults?.integer(forKey: "widget_level") ?? 0 }
    static var levelTitle: String { defaults?.string(forKey: "widget_levelTitle") ?? "Rookie Roommate" }
    static var xpProgress: Double { defaults?.double(forKey: "widget_xpProgress") ?? 0 }
    static var totalXP: Int { defaults?.integer(forKey: "widget_totalXP") ?? 0 }
    static var todayCompleted: Int { defaults?.integer(forKey: "widget_todayCompleted") ?? 0 }
    static var nextTask: String? { defaults?.string(forKey: "widget_nextTask") }
}
