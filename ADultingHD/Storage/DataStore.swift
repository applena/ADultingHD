import Foundation
import SwiftUI
import WidgetKit
import CloudKit
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

    /// Multi-household index. After `load()` always contains at least one
    /// household with a valid `activeHouseholdId`. Mutated only via household
    /// management methods — kept `private(set)` so views can't bypass save/sync.
    private(set) var householdIndex: HouseholdIndex = HouseholdIndex(
        households: [],
        activeHouseholdId: UUID(),
        schemaVersion: HouseholdIndex.currentSchemaVersion
    )

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
    /// Reentrancy guard. `load()` and `pullFromCloudKit()` both overwrite all
    /// `@Observable` state wholesale; allowing them to interleave causes view
    /// bodies to observe torn state mid-update, which SwiftUI has historically
    /// crashed on. Both paths early-return when set, but coalesce the dropped
    /// request through `pendingReload` so a CloudKit push that arrives during
    /// an in-progress iCloud reload isn't lost.
    @ObservationIgnored
    private var isReloading = false
    @ObservationIgnored
    private var pendingReload: PendingReload?

    private enum PendingReload { case local, cloudKit }

    /// True only when the compile-time `Features.cloudKitSharing` is on AND the
    /// user has explicitly opted into sharing. The compile-time gate matters
    /// because `CKContainer(identifier:)` traps at launch if the container
    /// isn't deployed to Production on CloudKit Console — which is the case
    /// until the prerequisites listed in `Features.cloudKitSharing` are met.
    /// Persisted flags from older builds (where the UI was reachable without
    /// the compile gate) would otherwise still trigger that trap here.
    private var isHouseholdSharingEnabled: Bool {
        Features.cloudKitSharing && UserDefaults.standard.bool(forKey: PrefKey.householdSharingEnabled)
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

    // MARK: - Household Index Convenience

    /// The UUID of the currently active household. Always valid after `load()`.
    var activeHouseholdId: UUID { householdIndex.activeHouseholdId }

    /// The currently active household, or a synthesized fallback if the index
    /// is empty (only possible during migration or after reset).
    var activeHousehold: Household {
        householdIndex.activeHousehold
            ?? Household.newLocal(id: householdIndex.activeHouseholdId, name: "My Household", members: [])
    }

    var householdProfiles: [UserProfile] {
        activeHousehold.members
    }

    var leaderboard: [UserProfile] {
        householdProfiles.sorted { $0.totalXP > $1.totalXP }
    }

    // MARK: - Load

    func load() async {
        if isReloading {
            // Upgrade a queued cloudKit reload over a local one; a cloudKit
            // pull also refreshes the local state after merge.
            if pendingReload != .cloudKit { pendingReload = .local }
            return
        }
        isReloading = true
        defer {
            isReloading = false
            drainPendingReload()
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            let demo = DemoData.generate()
            let demoHousehold = Household.newLocal(name: "Demo House", members: demo.householdProfiles)
            householdIndex = HouseholdIndex(
                households: [demoHousehold],
                activeHouseholdId: demoHousehold.id,
                schemaVersion: HouseholdIndex.currentSchemaVersion
            )
            tasks = demo.tasks
            profile = demo.profile
            completions = demo.completions
            supplyStock = demo.supplyStock
            isLoaded = true
            logger.info("🎬 Demo data loaded")
            return
        }
        #endif

        // Run the one-time layout migration before any reads so subsequent
        // scoped loads see the new directory structure.
        await migrateToHouseholdsLayoutIfNeeded()

        // Snapshot household state before reload for change detection on subsequent loads
        let wasLoaded = isLoaded
        let preProfiles = wasLoaded ? householdProfiles : []
        let preCompletionIDs = wasLoaded ? Set(completions.map(\.id)) : []
        let preRank = wasLoaded ? leaderboard.firstIndex(where: { $0.id == profile.id }).map { $0 + 1 } : nil

        // Load the household index. If it's missing (e.g. very first install
        // with no legacy data), synthesize a fresh default household.
        if let loadedIndex = await store.loadHouseholdIndex() {
            householdIndex = loadedIndex
        } else if householdIndex.households.isEmpty {
            householdIndex = makeFreshDefaultIndex()
            await store.saveHouseholdIndex(householdIndex)
        }

        let activeId = householdIndex.activeHouseholdId
        async let loadedTasks = store.loadTasks(for: activeId)
        async let loadedProfile = store.loadProfile()
        async let loadedCompletions = store.loadCompletions()
        async let loadedStock = store.loadSupplyStock(for: activeId)

        tasks = await loadedTasks
        profile = await loadedProfile
        completions = await loadedCompletions
        supplyStock = await loadedStock
        isLoaded = true

        // Make sure the device user is in the active household's member list,
        // and persist if we had to add them.
        let memberWasMissing = !activeHousehold.members.contains(where: { $0.id == profile.id })
        syncDeviceUserIntoActiveHousehold()
        if memberWasMissing {
            await store.saveHouseholdIndex(householdIndex)
        }

        updateStreak()
        logger.info("DataStore loaded: \(self.tasks.count) tasks, level \(self.profile.level), household '\(self.activeHousehold.name, privacy: .public)'")

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

    private func drainPendingReload() {
        guard let pending = pendingReload else { return }
        pendingReload = nil
        Task { @MainActor [weak self] in
            switch pending {
            case .local: await self?.load()
            case .cloudKit: await self?.pullFromCloudKit()
            }
        }
    }

    private func makeFreshDefaultIndex() -> HouseholdIndex {
        let name = UserDefaults.standard.string(forKey: PrefKey.onboardingHouseholdName) ?? "My Household"
        let household = Household.newLocal(name: name, members: [profile])
        return HouseholdIndex(
            households: [household],
            activeHouseholdId: household.id,
            schemaVersion: HouseholdIndex.currentSchemaVersion
        )
    }

    // MARK: - Multi-household migration

    /// One-time migration from the legacy flat file layout (tasks.json +
    /// supply_stock.json + household.json at the Documents root) into the new
    /// per-household directory tree. Idempotent; gated on a UserDefaults flag
    /// so it runs at most once per device. Legacy files are left in place so
    /// a crash mid-migration cleanly retries on the next launch.
    private func migrateToHouseholdsLayoutIfNeeded() async {
        let flagKey = PrefKey.householdsLayoutMigratedV2
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: flagKey) { return }

        // If another device already migrated and iCloud synced households.json
        // to us, just adopt it without touching local legacy files.
        if let existing = await store.loadHouseholdIndex() {
            householdIndex = existing
            defaults.set(true, forKey: flagKey)
            logger.info("🏠 Adopted migrated HouseholdIndex from iCloud")
            return
        }

        let legacyTasks = await store.loadTasksLegacy()
        let legacyStock = await store.loadSupplyStockLegacy()
        let legacyMembers = await store.loadLegacyHouseholdProfiles() ?? []

        // Determine a stable default household id. Reuse one we persisted
        // earlier if present, otherwise mint a new one and store it so any
        // retry on the next launch picks the same id.
        let defaultIdString = defaults.string(forKey: PrefKey.defaultHouseholdId) ?? UUID().uuidString
        defaults.set(defaultIdString, forKey: PrefKey.defaultHouseholdId)
        let defaultId = UUID(uuidString: defaultIdString) ?? UUID()

        let householdName = defaults.string(forKey: PrefKey.onboardingHouseholdName) ?? "My Household"

        // Load current profile so the device user is always in the household's
        // member list even if legacy household.json didn't include them.
        let currentProfile = await store.loadProfile()
        var members = legacyMembers
        if !members.contains(where: { $0.id == currentProfile.id }) {
            members.append(currentProfile)
        }

        // Reuse the legacy CloudKit zone name (default for newLocal) so
        // existing TestFlight users don't lose their records — CloudKit
        // doesn't support zone rename.
        let defaultHousehold = Household.newLocal(id: defaultId, name: householdName, members: members)

        // Copy (not move) legacy files into the per-household directory. Copy
        // rather than move so a crash mid-migration leaves legacy files intact
        // and next launch retries cleanly.
        if let legacyTasks {
            await store.saveTasks(legacyTasks, for: defaultId)
        }
        if let legacyStock {
            await store.saveSupplyStock(legacyStock, for: defaultId)
        }

        let index = HouseholdIndex(
            households: [defaultHousehold],
            activeHouseholdId: defaultId,
            schemaVersion: HouseholdIndex.currentSchemaVersion
        )
        await store.saveHouseholdIndex(index)
        householdIndex = index

        // Single commit point — only flip the flag once the new layout is
        // fully written.
        defaults.set(true, forKey: flagKey)
        logger.info("🏠 Migrated legacy layout into household \(defaultId.uuidString, privacy: .public) '\(householdName, privacy: .public)'")
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
            await store.saveTasks(tasks, for: activeHouseholdId)
        }
    }

    func addCustomTask(_ task: HouseholdTask) async {
        tasks.append(task)
        await store.saveTasks(tasks, for: activeHouseholdId)
    }

    func deleteTask(_ task: HouseholdTask) async {
        tasks.removeAll { $0.id == task.id }
        await store.saveTasks(tasks, for: activeHouseholdId)
    }

    func updateTask(_ task: HouseholdTask) async {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
            await store.saveTasks(tasks, for: activeHouseholdId)
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
        await store.saveSupplyStock(supplyStock, for: activeHouseholdId)
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
        await store.saveTasks(tasks, for: activeHouseholdId)
        await store.saveProfile(profile)
        await store.saveCompletions(completions)
        // Mirror the device user's latest progression into the active
        // household's member list so the leaderboard reflects current XP.
        syncDeviceUserIntoActiveHousehold()
        await store.saveHouseholdIndex(householdIndex)
        updateWidgetData()
        if isHouseholdSharingEnabled && ckSync.isAvailable {
            await ckSync.pushTasks(tasks)
            await ckSync.pushProfile(profile)
        }
    }

    private func syncDeviceUserIntoActiveHousehold() {
        guard let hIdx = householdIndex.households.firstIndex(where: { $0.id == activeHouseholdId }) else { return }
        if let mIdx = householdIndex.households[hIdx].members.firstIndex(where: { $0.id == profile.id }) {
            householdIndex.households[hIdx].members[mIdx] = profile
        } else {
            householdIndex.households[hIdx].members.append(profile)
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

    // MARK: - Household Members

    func addHouseholdMember(name: String, avatar: String) async {
        var newProfile = UserProfile()
        newProfile.name = name
        newProfile.avatar = avatar
        if let idx = householdIndex.households.firstIndex(where: { $0.id == activeHouseholdId }) {
            householdIndex.households[idx].members.append(newProfile)
            await store.saveHouseholdIndex(householdIndex)
        }
    }

    func switchProfile(to profileId: UUID) async {
        // Save current profile's latest state back into the active household
        syncDeviceUserIntoActiveHousehold()
        // Switch to new profile
        if let newProfile = householdProfiles.first(where: { $0.id == profileId }) {
            profile = newProfile
            await store.saveProfile(profile)
            await store.saveHouseholdIndex(householdIndex)
        }
    }

    func removeHouseholdMember(_ profileId: UUID) async {
        guard profileId != profile.id else { return } // Can't remove active profile
        if let idx = householdIndex.households.firstIndex(where: { $0.id == activeHouseholdId }) {
            householdIndex.households[idx].members.removeAll { $0.id == profileId }
            await store.saveHouseholdIndex(householdIndex)
        }
    }

    // MARK: - Multi-household management

    /// Creates a new household with default tasks and makes it active. UI gates
    /// this on Pro for the 2nd+ household.
    func createHousehold(name: String) async {
        let id = UUID()
        let household = Household.newLocal(
            id: id,
            name: name.isEmpty ? "New Household" : name,
            members: [profile],
            zoneName: "Household-\(id.uuidString)"
        )
        householdIndex.households.append(household)
        householdIndex.activeHouseholdId = id
        // Seed scoped state directly instead of loading from disk (which would
        // fall through to defaults + write anyway, costing a wasted read).
        tasks = defaultHouseholdTasks
        supplyStock = [:]
        await store.saveTasks(tasks, for: id)
        await store.saveHouseholdIndex(householdIndex)
        logger.info("🏠 Created household '\(name, privacy: .public)' \(id.uuidString, privacy: .public)")
    }

    func switchHousehold(to id: UUID) async {
        guard householdIndex.households.contains(where: { $0.id == id }) else { return }
        guard id != activeHouseholdId else { return }
        // Persist current household's state before swapping so nothing is lost
        await save()
        householdIndex.activeHouseholdId = id
        await store.saveHouseholdIndex(householdIndex)
        async let loadedTasks = store.loadTasks(for: id)
        async let loadedStock = store.loadSupplyStock(for: id)
        tasks = await loadedTasks
        supplyStock = await loadedStock
        logger.info("🏠 Switched to household \(id.uuidString, privacy: .public)")
    }

    func renameHousehold(_ id: UUID, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = householdIndex.households.firstIndex(where: { $0.id == id }) {
            householdIndex.households[idx].name = trimmed
            await store.saveHouseholdIndex(householdIndex)
        }
    }

    /// Delete a household. Refuses to delete the last remaining household. If
    /// the active household is deleted, falls back to the first remaining one.
    func deleteHousehold(_ id: UUID) async {
        guard householdIndex.households.count > 1 else {
            logger.info("🏠 Refusing to delete last household")
            return
        }
        householdIndex.households.removeAll { $0.id == id }
        if activeHouseholdId == id, let firstRemaining = householdIndex.households.first {
            householdIndex.activeHouseholdId = firstRemaining.id
            tasks = await store.loadTasks(for: firstRemaining.id)
            supplyStock = await store.loadSupplyStock(for: firstRemaining.id)
        }
        await store.saveHouseholdIndex(householdIndex)
        await store.deleteHouseholdDirectory(id)
        logger.info("🏠 Deleted household \(id.uuidString, privacy: .public)")
    }

    func listHouseholds() -> [Household] {
        householdIndex.households
    }

    // MARK: - CloudKit Migration & Sync

    /// One-time migration: push existing JSON data to CloudKit on first launch.
    private func migrateToCloudKitIfNeeded() async {
        let key = PrefKey.ckMigrationDone
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
        if isReloading {
            pendingReload = .cloudKit
            return
        }
        isReloading = true
        defer {
            isReloading = false
            drainPendingReload()
        }

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

        // Merge profiles into the active household's members list, preferring
        // the higher-XP version for conflicts on the same profile id.
        if let hIdx = householdIndex.households.firstIndex(where: { $0.id == activeHouseholdId }) {
            for cloudProfile in payload.profiles {
                if cloudProfile.id == profile.id {
                    if cloudProfile.totalXP > profile.totalXP { profile = cloudProfile }
                } else if let mIdx = householdIndex.households[hIdx].members.firstIndex(where: { $0.id == cloudProfile.id }) {
                    if cloudProfile.totalXP > householdIndex.households[hIdx].members[mIdx].totalXP {
                        householdIndex.households[hIdx].members[mIdx] = cloudProfile
                    }
                } else {
                    householdIndex.households[hIdx].members.append(cloudProfile)
                }
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
        // Defensive: CloudKit paths trap if the container isn't deployed.
        // Callers should already be gated on Features.cloudKitSharing through
        // the UI; this guard stops a stale UserDefaults flag or a direct
        // invocation from crashing the app.
        guard Features.cloudKitSharing else { throw CloudKitSyncError.shareCreationFailed }
        UserDefaults.standard.set(true, forKey: PrefKey.householdSharingEnabled)
        AppDelegate.registerForRemoteNotifications()
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

        syncObserverTokens.append(
            NotificationCenter.default.addObserver(forName: .cloudKitShareAccepted, object: nil, queue: .main) { [weak self] notification in
                guard let metadata = notification.object as? CKShare.Metadata else { return }
                Task { @MainActor in
                    await self?.registerJoinedHousehold(from: metadata)
                }
            }
        )
    }

    /// Handle acceptance of a CKShare invite. Joins the shared zone and
    /// pulls its data into the active household.
    func registerJoinedHousehold(from metadata: CKShare.Metadata) async {
        guard Features.cloudKitSharing else {
            logger.error("🏠 Ignoring CKShare acceptance: cloudKitSharing feature is off")
            return
        }
        do {
            try await ckSync.acceptShare(from: metadata)
            UserDefaults.standard.set(true, forKey: PrefKey.householdSharingEnabled)
            AppDelegate.registerForRemoteNotifications()
            await ckSync.setup()
            await pullFromCloudKit()
            logger.info("🏠 Joined shared household via CKShare")
        } catch {
            logger.error("🏠 Failed to accept share: \(error.localizedDescription)")
        }
    }

    // MARK: - Export/Import

    func exportData() async -> Data? {
        await store.exportBackup(householdId: activeHouseholdId)
    }

    func importData(_ data: Data) async -> Bool {
        let success = await store.importBackup(from: data, householdId: activeHouseholdId)
        if success { await load() }
        return success
    }

    func resetAll() async {
        await store.resetAllData()
        // Clear one-shot migration flags so a fresh load seeds a new default
        // household; clear onboarding flags so ContentView falls back to the
        // welcome screen the same way a fresh install would.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PrefKey.householdsLayoutMigratedV2)
        defaults.removeObject(forKey: PrefKey.defaultHouseholdId)
        defaults.removeObject(forKey: PrefKey.ckMigrationDone)
        defaults.removeObject(forKey: PrefKey.hasCompletedOnboarding)
        defaults.removeObject(forKey: PrefKey.onboardingHouseholdName)
        defaults.removeObject(forKey: PrefKey.householdSharingEnabled)
        tasks = defaultHouseholdTasks
        profile = UserProfile()
        completions = []
        supplyStock = [:]
        householdIndex = makeFreshDefaultIndex()
        await save()
    }
}

private extension Array where Element == String {
    mutating func appendIfNew(_ element: String) {
        if !contains(element) { append(element) }
    }
}
