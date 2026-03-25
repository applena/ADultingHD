import Foundation
import SwiftUI
import WidgetKit
import os

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "DataStore")

@Observable
@MainActor
final class DataStore {
    var tasks: [HouseholdTask] = []
    var profile: UserProfile = UserProfile()
    var completions: [TaskCompletion] = []
    var supplyStock: [String: SupplyStock] = [:]
    var isLoaded = false

    var celebrationType: CelebrationOverlay.CelebrationType?

    private let store = TaskStore()

    // MARK: - Derived State

    var activeTasks: [HouseholdTask] { tasks.filter(\.isActive) }
    var dueTasks: [HouseholdTask] { activeTasks.filter(\.isDue).sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) } }
    var overdueTasks: [HouseholdTask] { activeTasks.filter(\.isOverdue) }

    var todayCompletions: [TaskCompletion] {
        completions.filter { Calendar.current.isDateInToday($0.completedAt) }
    }

    var todayXP: Int { todayCompletions.reduce(0) { $0 + $1.xpEarned + $1.streakBonus } }

    var tasksByCategory: [TaskCategory: [HouseholdTask]] {
        Dictionary(grouping: tasks, by: \.category)
    }

    var allSupplies: [String: [HouseholdTask]] {
        var result: [String: [HouseholdTask]] = [:]
        for task in activeTasks {
            for supply in task.supplies {
                result[supply, default: []].append(task)
            }
        }
        return result
    }

    // MARK: - Load

    func load() async {
        let loadedTasks = await store.loadTasks()
        let loadedProfile = await store.loadProfile()
        let loadedCompletions = await store.loadCompletions()
        let loadedStock = await store.loadSupplyStock()

        tasks = loadedTasks
        profile = loadedProfile
        completions = loadedCompletions
        supplyStock = loadedStock
        isLoaded = true

        updateStreak()
        await loadHouseholdProfiles()
        logger.info("DataStore loaded: \(self.tasks.count) tasks, level \(self.profile.level)")
    }

    // MARK: - Complete Task

    func completeTask(_ task: HouseholdTask, notes: String? = nil, quality: CompletionQuality = .normal) async {
        let streakBonus = profile.currentStreak > 0 ? min(profile.currentStreak * 2, 50) : 0
        let baseXP = task.xpReward
        let xpEarned = Int(Double(baseXP) * quality.xpMultiplier)

        let completion = TaskCompletion(
            id: UUID(),
            taskId: task.id,
            taskName: task.name,
            completedAt: Date(),
            xpEarned: xpEarned,
            streakBonus: streakBonus,
            notes: notes,
            quality: quality
        )

        completions.insert(completion, at: 0)
        profile.totalXP += xpEarned + streakBonus
        profile.totalTasksCompleted += 1

        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].lastCompleted = Date()
        }

        let previousLevel = profile.level
        let previousAchievements = profile.unlockedAchievements

        updateStreak()
        checkAchievements()

        // Trigger celebrations
        let newLevel = profile.level
        if newLevel > previousLevel {
            celebrationType = .levelUp(newLevel)

            FeedbackManager.levelUp()
        } else if profile.unlockedAchievements.count > previousAchievements.count {
            let newId = profile.unlockedAchievements.first { !previousAchievements.contains($0) }
            let name = allAchievements.first { $0.id == newId }?.name ?? "Achievement"
            celebrationType = .achievement(name)

            FeedbackManager.achievementUnlocked()
        } else if [3, 7, 14, 30, 100].contains(profile.currentStreak) {
            celebrationType = .streakMilestone(profile.currentStreak)

            FeedbackManager.streakMilestone()
        } else {
            celebrationType = .taskComplete

            FeedbackManager.taskCompleted()
        }

        await save()
        logger.info("Completed '\(task.name)' +\(xpEarned)XP +\(streakBonus) streak bonus")
    }

    // MARK: - Task Management

    func toggleTask(_ task: HouseholdTask) async {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].isActive.toggle()
            await store.saveTasks(tasks)
        }
    }

    func addCustomTask(_ task: HouseholdTask) async {
        tasks.append(task)
        await store.saveTasks(tasks)
    }

    func deleteTask(_ task: HouseholdTask) async {
        tasks.removeAll { $0.id == task.id }
        await store.saveTasks(tasks)
    }

    func updateTask(_ task: HouseholdTask) async {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
            await store.saveTasks(tasks)
        }
    }

    // MARK: - Supply Stock

    var shoppingList: [String] {
        supplyStock.filter { $0.value == .low || $0.value == .out }
            .keys.sorted()
    }

    func setSupplyStock(_ supply: String, stock: SupplyStock) async {
        supplyStock[supply] = stock
        await store.saveSupplyStock(supplyStock)
    }

    // MARK: - Streak

    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let lastActive = profile.lastActiveDate else {
            if !todayCompletions.isEmpty {
                profile.currentStreak = 1
                profile.lastActiveDate = today
            }
            return
        }

        let lastActiveDay = calendar.startOfDay(for: lastActive)
        let daysDiff = calendar.dateComponents([.day], from: lastActiveDay, to: today).day ?? 0

        if daysDiff == 0 {
            // Same day — streak unchanged
        } else if daysDiff == 1 {
            // Consecutive day
            if !todayCompletions.isEmpty {
                profile.currentStreak += 1
                profile.lastActiveDate = today
            }
        } else {
            // Streak broken
            profile.currentStreak = todayCompletions.isEmpty ? 0 : 1
            profile.lastActiveDate = todayCompletions.isEmpty ? nil : today
        }

        profile.longestStreak = max(profile.longestStreak, profile.currentStreak)
    }

    // MARK: - Achievements

    private func checkAchievements() {
        var newAchievements = profile.unlockedAchievements

        // Task count achievements
        if profile.totalTasksCompleted >= 1 { newAchievements.appendIfNew("first_task") }
        if profile.totalTasksCompleted >= 10 { newAchievements.appendIfNew("ten_tasks") }
        if profile.totalTasksCompleted >= 50 { newAchievements.appendIfNew("fifty_tasks") }
        if profile.totalTasksCompleted >= 100 { newAchievements.appendIfNew("hundred_tasks") }

        // Streak achievements
        if profile.currentStreak >= 3 { newAchievements.appendIfNew("streak_3") }
        if profile.currentStreak >= 7 { newAchievements.appendIfNew("streak_7") }
        if profile.currentStreak >= 14 { newAchievements.appendIfNew("streak_14") }
        if profile.currentStreak >= 30 { newAchievements.appendIfNew("streak_30") }
        if profile.currentStreak >= 100 { newAchievements.appendIfNew("streak_100") }

        // Level achievements
        if profile.level >= 5 { newAchievements.appendIfNew("level_5") }
        if profile.level >= 10 { newAchievements.appendIfNew("level_10") }
        if profile.level >= 25 { newAchievements.appendIfNew("level_25") }

        // XP achievements
        if profile.totalXP >= 1000 { newAchievements.appendIfNew("xp_1000") }
        if profile.totalXP >= 10000 { newAchievements.appendIfNew("xp_10000") }

        // Daily productivity
        if todayCompletions.count >= 5 { newAchievements.appendIfNew("five_in_day") }

        // Early bird - completed before due
        if let lastCompletion = completions.first,
           let task = tasks.first(where: { $0.id == lastCompletion.taskId }),
           !task.isDue {
            newAchievements.appendIfNew("early_bird")
        }

        profile.unlockedAchievements = newAchievements
    }

    // MARK: - Persistence

    private func save() async {
        await store.saveTasks(tasks)
        await store.saveProfile(profile)
        await store.saveCompletions(completions)
        updateWidgetData()
    }

    private func updateWidgetData() {
        SharedDefaults.updateWidgetData(
            dueTasks: dueTasks.count,
            overdueTasks: overdueTasks.count,
            streak: profile.currentStreak,
            level: profile.level,
            levelTitle: profile.levelTitle,
            xpProgress: profile.xpProgress,
            totalXP: profile.totalXP,
            todayCompleted: todayCompletions.count,
            nextTaskName: dueTasks.first?.name
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Household Profiles

    var householdProfiles: [UserProfile] = []

    func loadHouseholdProfiles() async {
        householdProfiles = await store.loadHouseholdProfiles()
        // Ensure current profile is in the list
        if !householdProfiles.contains(where: { $0.id == profile.id }) {
            householdProfiles.append(profile)
            await store.saveHouseholdProfiles(householdProfiles)
        }
    }

    func addHouseholdMember(name: String, avatar: String) async {
        var newProfile = UserProfile()
        newProfile.name = name
        newProfile.avatar = avatar
        householdProfiles.append(newProfile)
        await store.saveHouseholdProfiles(householdProfiles)
    }

    func switchProfile(to profileId: UUID) async {
        // Save current profile back to household list
        if let idx = householdProfiles.firstIndex(where: { $0.id == profile.id }) {
            householdProfiles[idx] = profile
        }
        // Switch to new profile
        if let newProfile = householdProfiles.first(where: { $0.id == profileId }) {
            profile = newProfile
            await store.saveProfile(profile)
            await store.saveHouseholdProfiles(householdProfiles)
        }
    }

    func removeHouseholdMember(_ profileId: UUID) async {
        guard profileId != profile.id else { return } // Can't remove active profile
        householdProfiles.removeAll { $0.id == profileId }
        await store.saveHouseholdProfiles(householdProfiles)
    }

    var leaderboard: [UserProfile] {
        householdProfiles.sorted { $0.totalXP > $1.totalXP }
    }

    // MARK: - Export/Import

    func exportData() async -> Data? {
        await store.exportBackup()
    }

    func importData(_ data: Data) async -> Bool {
        let success = await store.importBackup(from: data)
        if success { await load() }
        return success
    }

    func resetAll() async {
        await store.resetAllData()
        tasks = defaultHouseholdTasks
        profile = UserProfile()
        completions = []
        await save()
    }
}

private extension Array where Element == String {
    mutating func appendIfNew(_ element: String) {
        if !contains(element) { append(element) }
    }
}
