import Foundation
import UserNotifications
import os

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "Notifications")

@MainActor
@Observable
final class NotificationManager {
    /// Re-plans the streak warning whenever authorization actually flips —
    /// covers both cold launch (`checkAuthorizationStatus()` resolves after
    /// `DataStore.load()` already synced while this was stale-false) and
    /// the user granting permission from Settings mid-session.
    var isAuthorized = false {
        didSet {
            guard isAuthorized != oldValue else { return }
            rescheduleStreakReminderFromSnapshot()
        }
    }
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
    /// Streak protection defaults ON (unlike the opt-in daily reminder):
    /// anyone who authorized notifications for a streak game expects to be
    /// warned before losing the streak. It only ever fires while a live
    /// streak is one missed day from dying — see
    /// `Recurrence.streakReminderFireDate`.
    var streakReminderEnabled: Bool = UserDefaults.standard.object(forKey: PrefKey.streakReminderEnabled) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(streakReminderEnabled, forKey: PrefKey.streakReminderEnabled)
            rescheduleStreakReminderFromSnapshot()
        }
    }
    var streakReminderHour: Int = UserDefaults.standard.object(forKey: PrefKey.streakReminderHour) as? Int ?? 18 {
        didSet {
            guard streakReminderHour != oldValue else { return }
            UserDefaults.standard.set(streakReminderHour, forKey: PrefKey.streakReminderHour)
            rescheduleStreakReminderFromSnapshot()
        }
    }
    var streakReminderMinute: Int = UserDefaults.standard.object(forKey: PrefKey.streakReminderMinute) as? Int ?? 0 {
        didSet {
            guard streakReminderMinute != oldValue else { return }
            UserDefaults.standard.set(streakReminderMinute, forKey: PrefKey.streakReminderMinute)
            rescheduleStreakReminderFromSnapshot()
        }
    }

    /// Last streak state handed to `syncStreakReminder` — kept so the
    /// Settings toggles/time picker and the `isAuthorized` flip can re-plan
    /// the pending warning without a back-reference to `DataStore`.
    private var streakSnapshot: (streak: Int, lastActiveDate: Date?) = (0, nil)

    /// The (streak, fireDate) pair last applied to the notification center
    /// (`fireDate == nil` means "nothing pending"). Re-syncs that compute
    /// an identical plan — the dominant case: every iCloud-triggered
    /// reload, every completion's pre-insert streak refresh — early-return
    /// on this compare instead of paying notification-center round-trips.
    private var appliedStreakPlan: (streak: Int, fireDate: Date?)?

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
        var components = DateComponents()
        components.hour = reminderHour
        components.minute = reminderMinute
        schedule(
            identifier: "daily_reminder",
            title: "Time to adult!",
            body: "Check your tasks for today and keep your streak alive.",
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        logger.info("Daily reminder scheduled for \(self.reminderHour):\(String(format: "%02d", self.reminderMinute))")
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
    }

    /// Replaces the pending streak-at-risk warning to match the given streak
    /// state. Call whenever the streak may have changed — completion, undo,
    /// (re)load, day rollover. Completing a task moves `lastActiveDate`
    /// forward, which re-plans the warning for the following evening; a dead
    /// or absent streak cancels it (`streakReminderFireDate` returns nil).
    func syncStreakReminder(streak: Int, lastActiveDate: Date?) {
        streakSnapshot = (streak, lastActiveDate)
        rescheduleStreakReminderFromSnapshot()
    }

    private func rescheduleStreakReminderFromSnapshot() {
        let fireDate: Date? = (isAuthorized && streakReminderEnabled)
            ? Recurrence.streakReminderFireDate(
                lastActiveDate: streakSnapshot.lastActiveDate,
                currentStreak: streakSnapshot.streak,
                asOf: Date(),
                hour: streakReminderHour,
                minute: streakReminderMinute
            )
            : nil
        let plan = (streak: streakSnapshot.streak, fireDate: fireDate)
        if let applied = appliedStreakPlan, applied == plan { return }
        appliedStreakPlan = plan

        guard let fireDate else {
            center.removePendingNotificationRequests(withIdentifiers: ["streak_reminder"])
            return
        }

        let streak = streakSnapshot.streak
        schedule(
            identifier: "streak_reminder",
            title: "🔥 Your \(streak)-day streak is on the line!",
            body: "One task before midnight keeps it going — and earns +\(UserProfile.streakBonusXP(for: streak)) bonus XP.",
            trigger: UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false
            )
        )
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
        var components = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        components.hour = reminderHour
        components.minute = reminderMinute
        schedule(
            identifier: "task_\(task.id.uuidString)",
            title: "\(task.name) is due!",
            body: task.room.map { "\($0) task — \(task.estimatedMinutes) min, +\(task.xpReward) XP" }
                ?? "\(task.estimatedMinutes) min, +\(task.xpReward) XP",
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    func cancelTaskReminder(for task: HouseholdTask) {
        center.removePendingNotificationRequests(withIdentifiers: ["task_\(task.id.uuidString)"])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    func notifyHouseholdActivity(_ activity: HouseholdActivity) {
        guard isAuthorized, householdActivityEnabled else { return }
        schedule(
            identifier: "household_\(activity.id.uuidString)",
            title: activity.notificationTitle,
            body: activity.notificationBody,
            trigger: nil
        )
    }

    /// Shared content→request→add path for every notification this manager
    /// schedules. Adding with an identifier that's already pending replaces
    /// it, so callers never need a paired cancel first.
    private func schedule(identifier: String, title: String, body: String, trigger: UNNotificationTrigger?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                logger.error("Failed to schedule \(identifier): \(error.localizedDescription)")
            }
        }
    }
}
