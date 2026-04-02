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
    var householdActivityFeed: [HouseholdActivity] = []

    private let dailyClearBonusXP = 25
    private let weeklyConsistencyBonusXP = 75
    private let monthlyConsistencyBonusXP = 150

    private let store = TaskStore()
    private let ckSync = CloudKitSync.shared

    @ObservationIgnored
    private var notificationManager: NotificationManager?
    @ObservationIgnored
    private var syncObserverTokens: [NSObjectProtocol] = []

    private var isHouseholdSharingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "householdSharingEnabled")
    }

    func configure(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            let demo = DemoData.generate()
            tasks = demo.tasks
            profile = demo.profile
            completions = demo.completions
            supplyStock = demo.supplyStock
            householdProfiles = demo.householdProfiles
            isLoaded = true
            logger.info("🎬 Demo data loaded")
            return
        }
        #endif

        // Snapshot household state before reload for change detection on subsequent loads
        let wasLoaded = isLoaded
        let preProfiles = wasLoaded ? householdProfiles : []
        let preCompletionIDs = wasLoaded ? Set(completions.map(\.id)) : []
        let preRank = wasLoaded ? leaderboard.firstIndex(where: { $0.id == profile.id }).map { $0 + 1 } : nil

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

        if wasLoaded {
            detectHouseholdChanges(preProfiles: preProfiles, preCompletionIDs: preCompletionIDs, preRank: preRank)
        }

        // CloudKit: only engage if household sharing has been explicitly enabled
        if isHouseholdSharingEnabled {
            await ckSync.setup()
            if ckSync.isAvailable {
                await migrateToCloudKitIfNeeded()
                await ckSync.setupSubscriptions()
            }
        }
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
            quality: quality,
            profileId: profile.id
        )

        completions.insert(completion, at: 0)
        profile.totalXP += xpEarned + streakBonus
        profile.coins += xpEarned + streakBonus
        profile.totalTasksCompleted += 1

        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].lastCompleted = Date()
        }

        let periodBonus = applyPeriodBonusesIfEarned(at: completion.completedAt)
        if periodBonus > 0 {
            profile.totalXP += periodBonus
            logger.info("Applied consistency bonus: +\(periodBonus)XP")
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

    // MARK: - Avatar

    func purchaseAvatarItem(_ item: AvatarItem) async {
        guard profile.coins >= item.cost else { return }
        profile.coins -= item.cost
        profile.avatarState.purchase(item)
        profile.avatarState.equip(item)
        await store.saveProfile(profile)
    }

    func equipAvatarItem(_ item: AvatarItem) async {
        profile.avatarState.equip(item)
        await store.saveProfile(profile)
    }

    func unequipAvatarItem(slot: AvatarSlot) async {
        profile.avatarState.unequip(slot: slot)
        await store.saveProfile(profile)
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
        if isHouseholdSharingEnabled && ckSync.isAvailable {
            await ckSync.pushTasks(tasks)
            await ckSync.pushProfile(profile)
        }
    }

    private func updateWidgetData() {
        SharedDefaults.updateWidgetData(
            dueTasks: dueTasks.count,
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

    // MARK: - Consistency Bonuses

    private func applyPeriodBonusesIfEarned(at date: Date) -> Int {
        var totalBonus = 0

        if dueTasks.isEmpty {
            totalBonus += awardIfFirst(for: "daily", at: date, xp: dailyClearBonusXP)
        }

        if earnedWeeklyConsistencyBonus(at: date) {
            totalBonus += awardIfFirst(for: "weekly", at: date, xp: weeklyConsistencyBonusXP)
        }

        if earnedMonthlyConsistencyBonus(at: date) {
            totalBonus += awardIfFirst(for: "monthly", at: date, xp: monthlyConsistencyBonusXP)
        }

        return totalBonus
    }

    private func earnedWeeklyConsistencyBonus(at date: Date) -> Bool {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return false }
        let completedTaskIDs = Set(
            completions
                .filter { interval.contains($0.completedAt) }
                .map(\.taskId)
        )
        let requiredTaskIDs = Set(activeTasks.map(\.id))
        return !requiredTaskIDs.isEmpty && requiredTaskIDs.isSubset(of: completedTaskIDs)
    }

    private func earnedMonthlyConsistencyBonus(at date: Date) -> Bool {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return false }
        let completedTaskIDs = Set(
            completions
                .filter { interval.contains($0.completedAt) }
                .map(\.taskId)
        )
        let requiredTaskIDs = Set(activeTasks.map(\.id))
        return !requiredTaskIDs.isEmpty && requiredTaskIDs.isSubset(of: completedTaskIDs)
    }

    private func awardIfFirst(for period: String, at date: Date, xp: Int) -> Int {
        let key = bonusPeriodKey(period: period, date: date)
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return 0 }
        defaults.set(true, forKey: key)
        return xp
    }

    private func bonusPeriodKey(period: String, date: Date) -> String {
        let calendar = Calendar.current
        let anchorDate: Date
        switch period {
        case "weekly":
            anchorDate = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case "monthly":
            anchorDate = calendar.dateInterval(of: .month, for: date)?.start ?? date
        default:
            anchorDate = calendar.startOfDay(for: date)
        }
        let formatter = DateFormatter()
        formatter.locale = .init(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: anchorDate)
        return "bonus_awarded_\(period)_\(stamp)"
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

    // MARK: - CloudKit Migration & Sync

    /// One-time migration: push existing JSON data to CloudKit on first launch.
    private func migrateToCloudKitIfNeeded() async {
        let key = "ckMigrationDone_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        logger.info("☁️ Migrating local data to CloudKit...")
        await ckSync.pushTasks(tasks)
        await ckSync.pushProfile(profile)
        for completion in completions { await ckSync.pushCompletion(completion) }
        for p in householdProfiles where p.id != profile.id { await ckSync.pushProfile(p) }
        UserDefaults.standard.set(true, forKey: key)
        logger.info("☁️ Migration complete")
    }

    /// Pull latest from CloudKit and merge, preferring higher XP / more recent completions.
    func pullFromCloudKit() async {
        guard ckSync.isAvailable, let payload = await ckSync.pullAll() else { return }

        // Snapshot before merge for change detection
        let preProfiles = householdProfiles
        let preCompletionIDs = Set(completions.map(\.id))
        let preRank = leaderboard.firstIndex(where: { $0.id == profile.id }).map { $0 + 1 }

        // Merge tasks: union by ID, keeping local custom tasks not in cloud
        let cloudTaskIds = Set(payload.tasks.map(\.id))
        let localOnly = tasks.filter { !cloudTaskIds.contains($0.id) }
        tasks = payload.tasks + localOnly

        // Merge completions: union by ID
        let newCompletions = payload.completions.filter { !preCompletionIDs.contains($0.id) }
        completions = (completions + newCompletions).sorted { $0.completedAt > $1.completedAt }

        // Merge profiles: prefer higher XP version
        for cloudProfile in payload.profiles {
            if cloudProfile.id == profile.id {
                if cloudProfile.totalXP > profile.totalXP { profile = cloudProfile }
            } else if let idx = householdProfiles.firstIndex(where: { $0.id == cloudProfile.id }) {
                if cloudProfile.totalXP > householdProfiles[idx].totalXP {
                    householdProfiles[idx] = cloudProfile
                }
            } else {
                householdProfiles.append(cloudProfile)
            }
        }

        await save()
        logger.info("☁️ CloudKit pull merged: \(self.tasks.count) tasks, \(self.completions.count) completions")

        detectHouseholdChanges(preProfiles: preProfiles, preCompletionIDs: preCompletionIDs, preRank: preRank)
    }

    private func detectHouseholdChanges(preProfiles: [UserProfile], preCompletionIDs: Set<UUID>, preRank: Int?) {
        guard householdProfiles.count > 1 else { return }

        let preXP = Dictionary(uniqueKeysWithValues: preProfiles.map { ($0.id, $0.totalXP) })
        let preLevels = Dictionary(uniqueKeysWithValues: preProfiles.map { ($0.id, $0.level) })
        let preAchievs = Dictionary(uniqueKeysWithValues: preProfiles.map { ($0.id, Set($0.unlockedAchievements)) })

        var newActivities: [HouseholdActivity] = []

        for member in householdProfiles where member.id != profile.id {
            let prevXP = preXP[member.id] ?? 0
            guard prevXP > 0 else { continue }  // skip members not seen before (avoid false level-up on add)

            // Level up
            let prevLevel = preLevels[member.id] ?? 0
            if member.level > prevLevel {
                newActivities.append(HouseholdActivity(
                    profileId: member.id, profileName: member.name, avatar: member.avatar,
                    event: .leveledUp(level: member.level), timestamp: Date()
                ))
            }

            // New achievements
            let prevAch = preAchievs[member.id] ?? []
            for achievId in Set(member.unlockedAchievements).subtracting(prevAch) {
                let name = allAchievements.first { $0.id == achievId }?.name ?? achievId
                newActivities.append(HouseholdActivity(
                    profileId: member.id, profileName: member.name, avatar: member.avatar,
                    event: .achievementUnlocked(name: name), timestamp: Date()
                ))
            }

            // New completions attributed to this member
            let memberCompletions = completions.filter {
                $0.profileId == member.id && !preCompletionIDs.contains($0.id)
            }
            for c in memberCompletions.prefix(5) {
                newActivities.append(HouseholdActivity(
                    profileId: member.id, profileName: member.name, avatar: member.avatar,
                    event: .completedTask(name: c.taskName, xp: c.xpEarned), timestamp: c.completedAt
                ))
            }
        }

        // Rank drop: did someone pass the current user?
        let postRank = leaderboard.firstIndex(where: { $0.id == profile.id }).map { $0 + 1 }
        if let pre = preRank, let post = postRank, post > pre {
            // Find members who were at or below our XP before but are now ahead
            let passers = leaderboard.prefix(post - 1).filter { member in
                (preXP[member.id] ?? member.totalXP) <= profile.totalXP
            }
            for passer in passers.prefix(1) {
                newActivities.append(HouseholdActivity(
                    profileId: passer.id, profileName: passer.name, avatar: passer.avatar,
                    event: .passedYou(newRank: post), timestamp: Date()
                ))
            }
        }

        guard !newActivities.isEmpty else { return }

        householdActivityFeed = Array((newActivities + householdActivityFeed).prefix(50))
        newActivities.forEach { notificationManager?.notifyHouseholdActivity($0) }
        logger.info("🏠 \(newActivities.count) new household activities detected")
    }

    var cloudKitShareURL: URL? { ckSync.shareURL }
    var cloudKitError: String? { ckSync.syncError }

    func createHouseholdShare() async throws -> URL? {
        UserDefaults.standard.set(true, forKey: "householdSharingEnabled")
        await ckSync.setup()
        await migrateToCloudKitIfNeeded()
        let share = try await ckSync.createOrFetchShare()
        return share.url
    }

    // MARK: - iCloud Documents Sync

    /// Start listening for remote iCloud and CloudKit changes. Safe to call once.
    func startSyncObserver() {
        guard syncObserverTokens.isEmpty else { return }

        syncObserverTokens.append(
            NotificationCenter.default.addObserver(forName: .dataDidSync, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.load()
                    logger.info("☁️ reloaded from iCloud sync")
                }
            }
        )

        syncObserverTokens.append(
            NotificationCenter.default.addObserver(forName: .cloudKitRemoteChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.pullFromCloudKit()
                    logger.info("☁️ pulled from CloudKit remote change")
                }
            }
        )
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
