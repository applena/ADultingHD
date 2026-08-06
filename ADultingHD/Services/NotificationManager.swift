import Foundation
import UserNotifications
import os

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "Notifications")

@MainActor
@Observable
final class NotificationManager {
    var isAuthorized = false
    var householdActivityEnabled: Bool = UserDefaults.standard.bool(forKey: "householdActivityEnabled") {
        didSet { UserDefaults.standard.set(householdActivityEnabled, forKey: "householdActivityEnabled") }
    }
    var dailyReminderEnabled: Bool = UserDefaults.standard.bool(forKey: "dailyReminderEnabled") {
        didSet {
            UserDefaults.standard.set(dailyReminderEnabled, forKey: "dailyReminderEnabled")
            if dailyReminderEnabled {
                scheduleDailyReminder()
            } else {
                cancelDailyReminder()
            }
        }
    }
    var reminderHour: Int = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 9 {
        didSet {
            UserDefaults.standard.set(reminderHour, forKey: "reminderHour")
            if dailyReminderEnabled { scheduleDailyReminder() }
        }
    }
    var reminderMinute: Int = UserDefaults.standard.object(forKey: "reminderMinute") as? Int ?? 0 {
        didSet {
            UserDefaults.standard.set(reminderMinute, forKey: "reminderMinute")
            if dailyReminderEnabled { scheduleDailyReminder() }
        }
    }

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            logger.info("Notification authorization: \(self.isAuthorized)")
        } catch {
            logger.error("Notification auth error: \(error.localizedDescription)")
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    func scheduleDailyReminder() {
        cancelDailyReminder()

        let content = UNMutableNotificationContent()
        content.title = "Time to adult!"
        content.body = "Check your tasks for today and keep your streak alive."
        content.sound = .default

        var components = DateComponents()
        components.hour = reminderHour
        components.minute = reminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)

        let hour = reminderHour
        let minute = reminderMinute
        center.add(request) { error in
            if let error {
                logger.error("Failed to schedule daily reminder: \(error.localizedDescription)")
            } else {
                logger.info("Daily reminder scheduled for \(hour):\(String(format: "%02d", minute))")
            }
        }
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
    }

    /// Schedules a one-shot reminder for `task`'s current occurrence
    /// (`task.dueDate`, from the same recurrence engine that drives due-task
    /// sorting and Schedule bucketing). Re-adding with the same identifier
    /// replaces any existing pending request for this task, so callers can
    /// call this again whenever the occurrence might have changed —
    /// on completion, on edit, and on day rollover — without needing to
    /// cancel first.
    func scheduleTaskReminder(for task: HouseholdTask) {
        guard isAuthorized, let dueDate = task.dueDate else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(task.name) is due!"
        content.body = "\(task.category.rawValue) task — \(task.estimatedMinutes) min, +\(task.xpReward) XP"
        content.sound = .default

        var components = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        components.hour = reminderHour
        components.minute = reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "task_\(task.id.uuidString)", content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                logger.error("Failed to schedule task reminder: \(error.localizedDescription)")
            }
        }
    }

    func cancelTaskReminder(for task: HouseholdTask) {
        center.removePendingNotificationRequests(withIdentifiers: ["task_\(task.id.uuidString)"])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    func notifyHouseholdActivity(_ activity: HouseholdActivity) {
        guard isAuthorized, householdActivityEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = activity.notificationTitle
        content.body = activity.notificationBody
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "household_\(activity.id.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error { logger.error("Household notification failed: \(error.localizedDescription)") }
        }
    }
}
