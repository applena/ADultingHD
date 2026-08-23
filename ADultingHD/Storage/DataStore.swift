import Foundation
import SwiftUI
import WidgetKit
import CloudKit
import os
#if os(iOS)
import UIKit
#endif

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "DataStore")

enum IncomingHouseholdShareError: LocalizedError {
    case missingPendingShare
    case sharingUnavailable

    var errorDescription: String? {
        switch self {
        case .missingPendingShare:
            "That household invite is no longer available. Open the invite link again."
        case .sharingUnavailable:
            "Household sharing is not available in this build."
        }
    }
}

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

    /// Set after joining a shared household when the current profile's display
    /// name collides with an existing member's name. The UI presents a sheet
    /// to prompt for a unique name before leaderboards become ambiguous.
    var pendingNameClash: NameClash?

    /// One atomic value for the share a first-time user is considering. The
    /// metadata remains file-private so views can display context but cannot
    /// accidentally accept the share outside DataStore's lifecycle methods.
    private(set) var pendingOnboardingShare: PendingOnboardingShare?

    struct PendingOnboardingShare: Identifiable {
        let id: String
        let householdName: String
        let inviterName: String?
        fileprivate let bootstrapHouseholdID: UUID?
        fileprivate let metadata: CKShare.Metadata
    }

    struct NameClash: Identifiable, Equatable {
        let id = UUID()
        let householdName: String
        let existingNames: [String]
        let currentName: String
    }

    private let dailyClearBonusXP = 25
    private let weeklyConsistencyBonusXP = 75
    private let monthlyConsistencyBonusXP = 150

    private let store: TaskStore
    private let householdWorkspaceStore: HouseholdWorkspaceStore
    private let ckSync = CloudKitSync.shared

    init() {
        let store = TaskStore()
        self.store = store
        householdWorkspaceStore = HouseholdWorkspaceStore(store: store)
    }

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

    /// Today's start-of-day, tracked as `@Observable` state so `dueTasks`/
    /// `overdueTasks` re-evaluate when the calendar day rolls over while the
    /// app is foregrounded — SwiftUI has no other reason to re-render those
    /// views, since nothing about `tasks` itself changed. Advanced only by
    /// `refreshForCurrentDay()`.
    private(set) var currentDay: Date = Calendar.current.startOfDay(for: Date())

    @ObservationIgnored
    private var dayRolloverObserverTokens: [NSObjectProtocol] = []

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

    /// Tasks that participate in weekly/monthly consistency goals. One-time
    /// and unscheduled work still grants completion progress, but does not
    /// become a recurring obligation in every future period.
    private var recurringActiveTasks: [HouseholdTask] {
        activeTasks.filter { $0.frequency != .unscheduled }
    }

    /// (task, occurrence) for every active, currently-due task, sorted by
    /// occurrence ascending (longest-missed first). Computed once per
    /// task — rather than inside `dueTasks`/`overdueTasks`' own sort
    /// comparators — so `nextOccurrence()`'s calendar search doesn't rerun
    /// on every comparison, and `overdueTasks` can reuse the same sorted,
    /// already-filtered list instead of re-deriving it.
    private var sortedDueTasksWithOccurrence: [(task: HouseholdTask, occurrence: Date)] {
        activeTasks
            .compactMap { task -> (task: HouseholdTask, occurrence: Date)? in
                guard let occurrence = task.nextOccurrence(),
                      Recurrence.isDue(occurrence: occurrence, on: currentDay, calendar: .current)
                else { return nil }
                return (task, occurrence)
            }
            .sorted { $0.occurrence < $1.occurrence }
    }

    /// Active tasks due on or before `currentDay`, longest-missed first.
    /// Overdue tasks (earlier occurrence) always sort above tasks due today,
    /// since sorting is purely by occurrence date ascending.
    var dueTasks: [HouseholdTask] { sortedDueTasksWithOccurrence.map(\.task) }

    /// The subset of `dueTasks` whose occurrence has actually passed —
    /// carried-forward misses, not merely due today. Surfaced in the task
    /// list, Schedule, and dashboard so carry-forward is visible, not just
    /// a silent sort-order nudge.
    var overdueTasks: [HouseholdTask] {
        sortedDueTasksWithOccurrence
            .filter { Recurrence.isOverdue(occurrence: $0.occurrence, on: currentDay, calendar: .current) }
            .map(\.task)
    }

    var todayCompletions: [TaskCompletion] {
        completions.filter { Calendar.current.isDateInToday($0.completedAt) }
    }

    var todayXP: Int { todayCompletions.reduce(0) { $0 + $1.xpEarned + $1.streakBonus } }

    var tasksByCategory: [TaskCategory: [HouseholdTask]] {
        Dictionary(grouping: tasks, by: \.category)
    }

    /// Optional spatial organization for screens that explicitly opt into a
    /// room view. Task-first screens should use `tasks` directly.
    var tasksByRoom: [String: [HouseholdTask]] {
        Dictionary(uniqueKeysWithValues: HouseholdTask.groupedByRoom(tasks, room: \.room))
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

    /// Whether the active household has more than one member — the single
    /// source of truth for gating assignee pickers/filters, since solo
    /// households have only one possible assignee.
    var hasMultipleAssignees: Bool { householdProfiles.count > 1 }

    var leaderboard: [UserProfile] {
        householdProfiles.sorted { $0.totalXP > $1.totalXP }
    }

    /// Each household member's XP earned so far this calendar week, highest
    /// first — see `WeeklyLeaderboard.entries`.
    var weeklyLeaderboard: [WeeklyXPEntry] {
        WeeklyLeaderboard.entries(members: householdProfiles, completions: completions)
    }

    /// This week's "superstar" (highest weekly XP), or `nil` when there's no
    /// clear leader — see `WeeklyLeaderboard.superstar`.
    var weeklySuperstar: WeeklyXPEntry? {
        WeeklyLeaderboard.superstar(among: weeklyLeaderboard)
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
        await householdWorkspaceStore.withSerializedAccess {
            await loadSerializedWorkspace()
        }
    }

    private func loadSerializedWorkspace() async {
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
            refreshStreakState()
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

        // Resolve the complete workspace into locals first. Publishing the
        // index before its scoped files finish loading would briefly pair the
        // new active household with the previous household's tasks/stock.
        var loadedIndex: HouseholdIndex
        if var savedIndex = await store.loadHouseholdIndex() {
            if savedIndex.schemaVersion != HouseholdIndex.currentSchemaVersion {
                savedIndex.schemaVersion = HouseholdIndex.currentSchemaVersion
                await store.saveHouseholdIndex(savedIndex)
            }
            loadedIndex = savedIndex
        } else if householdIndex.households.isEmpty {
            loadedIndex = makeFreshDefaultIndex()
            await store.saveHouseholdIndex(loadedIndex)
        } else {
            loadedIndex = householdIndex
        }

        let activeId = loadedIndex.activeHouseholdId
        async let loadedTasks = store.loadTasks(for: activeId)
        async let loadedProfile = store.loadProfile()
        async let loadedCompletions = store.loadCompletions()
        async let loadedStock = store.loadSupplyStock(for: activeId)

        let loadedWorkspace = await (loadedTasks, loadedProfile, loadedCompletions, loadedStock)
        var finalIndex = loadedIndex
        var indexNeedsSave = false
        if let householdPosition = finalIndex.households.firstIndex(where: { $0.id == activeId }) {
            let loadedProfile = loadedWorkspace.1
            if let memberPosition = finalIndex.households[householdPosition].members.firstIndex(where: { $0.id == loadedProfile.id }) {
                finalIndex.households[householdPosition].members[memberPosition] = loadedProfile
            } else {
                finalIndex.households[householdPosition].members.append(loadedProfile)
                indexNeedsSave = true
            }

            let localPersonalTaskIDs = Set(loadedWorkspace.0.filter(\.isPersonal).map(\.id))
            if !localPersonalTaskIDs.isSubset(of: finalIndex.households[householdPosition].personalTaskIDs) {
                finalIndex.households[householdPosition].personalTaskIDs.formUnion(localPersonalTaskIDs)
                indexNeedsSave = true
            }
        }
        if indexNeedsSave { await store.saveHouseholdIndex(finalIndex) }

        // One synchronous publication boundary: SwiftUI never observes a
        // household index paired with another household's workspace.
        householdIndex = finalIndex
        tasks = loadedWorkspace.0
        profile = loadedWorkspace.1
        completions = loadedWorkspace.2
        supplyStock = loadedWorkspace.3
        refreshStreakState()
        isLoaded = true
        logger.info("DataStore loaded: \(self.tasks.count) tasks, level \(self.profile.level), household '\(self.activeHousehold.name, privacy: .public)'")

        if wasLoaded {
            detectHouseholdChanges(preProfiles: preProfiles, preCompletionIDs: preCompletionIDs, preRank: preRank)
        }

        // CloudKit setup is deliberately NOT called here. `CKContainer(identifier:)`
        // traps at runtime if the signed provisioning profile is missing the CloudKit
        // entitlement even when the entitlements *file* requests it — and the trap
        // is uncatchable. If a user tapped Invite on a build where that mismatch
        // existed, `householdSharingEnabled` was already flipped to true, and
        // calling `ckSync.setup()` here would crash-loop them at launch forever.
        // Setup now fires only on explicit user actions (Invite tap, share accept)
        // so a broken provisioning profile fails the action, not the whole app.
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
        if var existing = await store.loadHouseholdIndex() {
            existing.schemaVersion = HouseholdIndex.currentSchemaVersion
            await store.saveHouseholdIndex(existing)
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

        // Reuse the legacy CloudKit zone name only for this migration so
        // existing TestFlight users don't lose their records. New households
        // must receive a unique zone because CloudKit cannot rename zones.
        let defaultHousehold = Household.newLocal(
            id: defaultId,
            name: householdName,
            members: members,
            zoneName: ZoneName.household
        )

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

        // Single commit point — only flip the flag once the new layout is
        // fully written.
        defaults.set(true, forKey: flagKey)
        logger.info("🏠 Migrated legacy layout into household \(defaultId.uuidString, privacy: .public) '\(householdName, privacy: .public)'")
    }

    // MARK: - Complete Task

    /// Run a user-initiated mutation only if the household that originated
    /// the action is still active when its serialized turn begins. Reloads or
    /// switches queued ahead of the action can otherwise redirect a stale
    /// task/supply value into a different household.
    private func mutateActiveWorkspace(
        expectedHouseholdID: UUID,
        _ mutation: @MainActor () async -> Void
    ) async {
        await householdWorkspaceStore.withSerializedAccess {
            guard activeHouseholdId == expectedHouseholdID else { return }
            await mutation()
        }
    }

    func completeTask(_ task: HouseholdTask, notes: String? = nil) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            guard let currentTask = tasks.first(where: { $0.id == task.id }) else { return }
            await completeTaskWhileSerialized(currentTask, notes: notes)
        }
    }

    private func completeTaskWhileSerialized(_ task: HouseholdTask, notes: String?) async {
        refreshStreakState()
        let streakBonus = UserProfile.streakBonusXP(for: profile.currentStreak)
        let xpEarned = task.xpReward

        let completion = TaskCompletion(
            id: UUID(),
            taskId: task.id,
            taskName: task.name,
            completedAt: Date(),
            xpEarned: xpEarned,
            streakBonus: streakBonus,
            notes: notes,
            // Attribution always follows whoever actually completed the task
            // on this device, not `task.defaultAssigneeId` — a housemate
            // finishing someone else's assigned chore is credited to
            // themselves. This naturally equals `defaultAssigneeId` in the
            // common case where the assignee is the one completing it.
            profileId: profile.id
        )

        completions.insert(completion, at: 0)
        profile.totalXP += xpEarned + streakBonus
        profile.coins += xpEarned + streakBonus
        profile.totalTasksCompleted += 1

        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].lastCompleted = Date()
            // A completion resolves any manual reschedule — the next
            // occurrence goes back to being computed from the recurring
            // schedule, anchored to this completion, like any other task.
            tasks[idx].scheduledOverrideDate = nil
            notificationManager?.scheduleTaskReminder(for: tasks[idx])
        }

        let periodBonuses = applyPeriodBonusesIfEarned(at: completion.completedAt)
        let periodBonusTotal = periodBonuses.values.reduce(0, +)
        if periodBonusTotal > 0 {
            profile.totalXP += periodBonusTotal
            // Recorded on the completion itself (not just applied to
            // `profile.totalXP`) so `uncompleteTask` can reverse exactly
            // this bonus later — see `TaskCompletion.periodBonuses`.
            if let completionIdx = completions.firstIndex(where: { $0.id == completion.id }) {
                completions[completionIdx].periodBonuses = periodBonuses
            }
            logger.info("Applied consistency bonus: +\(periodBonusTotal)XP")
        }

        let previousLevel = profile.level
        let previousAchievements = profile.unlockedAchievements

        refreshStreakState()
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

        await saveCurrentWorkspaceWhileSerialized()
        logger.info("Completed '\(task.name)' +\(xpEarned)XP +\(streakBonus) streak bonus")
    }

    /// Reverses a same-day task completion — the paired action to
    /// `completeTask` that lets the Dashboard's "Completed Tasks" section
    /// undo an accidental checkmark tap. XP, coins, and the completion
    /// count roll back exactly, including any daily/weekly/monthly
    /// consistency bonus this specific completion triggered (see
    /// `TaskCompletion.periodBonuses`) — the "already awarded" gate for
    /// that period is cleared too, so the bonus can genuinely be re-earned
    /// if the day/week/month is completed for real afterward. Unlocked
    /// achievements are intentionally left alone, matching how most
    /// gamified apps treat achievements as permanent once earned. Streak and
    /// best-streak values are recalculated from the remaining completion
    /// history, so undoing a restart or record-setting day is also exact.
    func uncompleteTask(_ completion: TaskCompletion) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            guard let currentCompletion = completions.first(where: { $0.id == completion.id }) else { return }
            await uncompleteTaskWhileSerialized(currentCompletion)
        }
    }

    private func uncompleteTaskWhileSerialized(_ completion: TaskCompletion) async {
        guard let idx = completions.firstIndex(where: { $0.id == completion.id }) else { return }
        completions.remove(at: idx)

        let periodBonusTotal = completion.periodBonuses?.values.reduce(0, +) ?? 0
        profile.totalXP = max(0, profile.totalXP - completion.totalXP - periodBonusTotal)
        // Period bonuses are never added to coins in `completeTask` — only
        // the completion's own XP is, so only that (not the period bonus)
        // comes back out here. The `max(0, ...)` clamp also means coins
        // already spent (e.g. in the Avatar Shop) between completing and
        // undoing are forgiven rather than tracked as a deficit — accepted
        // as the simplest safe behavior for what should be a rare window.
        profile.coins = max(0, profile.coins - completion.totalXP)
        profile.totalTasksCompleted = max(0, profile.totalTasksCompleted - 1)
        for period in completion.periodBonuses?.keys ?? [String: Int]().keys {
            revokeAward(for: period, at: completion.completedAt)
        }

        if let taskIdx = tasks.firstIndex(where: { $0.id == completion.taskId }) {
            let lastRemaining = completions.filter { $0.taskId == completion.taskId }.map(\.completedAt).max()
            tasks[taskIdx].lastCompleted = lastRemaining
            syncReminder(for: tasks[taskIdx])
        }

        refreshStreakState()

        await saveCurrentWorkspaceWhileSerialized()
        logger.info("Uncompleted '\(completion.taskName)' -\(completion.totalXP + periodBonusTotal)XP")
    }

    // MARK: - Task Management

    /// Schedules or cancels `task`'s local reminder to match its current
    /// `isActive` state. Called after any mutation that could change
    /// whether a reminder should exist or what occurrence it should fire
    /// against — completion, activation toggle, add, or edit.
    private func syncReminder(for task: HouseholdTask) {
        if task.isActive {
            notificationManager?.scheduleTaskReminder(for: task)
        } else {
            notificationManager?.cancelTaskReminder(for: task)
        }
    }

    private func persistActiveTasksWhileSerialized() async {
        let householdID = activeHouseholdId
        let snapshot = tasks
        guard householdIndex.households.contains(where: { $0.id == householdID }) else { return }
        await store.saveTasks(snapshot, for: householdID)
        await store.saveHouseholdIndex(householdIndex)
        await syncTasksWhileSerialized(householdID: householdID)
    }

    func toggleTask(_ task: HouseholdTask) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            await toggleTaskWhileSerialized(task)
        }
    }

    private func toggleTaskWhileSerialized(_ task: HouseholdTask) async {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].isActive.toggle()
            syncReminder(for: tasks[idx])
            await persistActiveTasksWhileSerialized()
        }
    }

    /// Personal tasks belong to the device user even when the active
    /// household has several members. Keep the assignee invariant here, at
    /// the storage boundary, so non-form callers cannot assign one to a
    /// housemate accidentally.
    private func normalizePersonalAssignment(_ task: HouseholdTask) -> HouseholdTask {
        var normalized = task
        if normalized.isPersonal {
            normalized.defaultAssigneeId = profile.id
        }
        return normalized
    }

    /// Keep private-task ownership durable even after the task itself leaves
    /// the local array. Completion history is global, so deriving this set
    /// from `tasks` alone would eventually re-upload a deleted personal task's
    /// history to a household.
    private func registerPersonalTaskOwnership(
        for task: HouseholdTask,
        previousIsPersonal: Bool? = nil,
        householdID: UUID
    ) {
        guard let householdIndex = householdIndex.households.firstIndex(where: { $0.id == householdID }) else { return }
        if task.isPersonal {
            self.householdIndex.households[householdIndex].personalTaskIDs.insert(task.id)
            self.householdIndex.households[householdIndex].pendingPersonalTaskReleases.remove(task.id)
        } else if previousIsPersonal == true
                    || self.householdIndex.households[householdIndex].personalTaskIDs.contains(task.id) {
            self.householdIndex.households[householdIndex].personalTaskIDs.remove(task.id)
            self.householdIndex.households[householdIndex].pendingPersonalTaskReleases.insert(task.id)
        }
    }

    private func registerPersonalTaskOwnership(for tasks: [HouseholdTask], householdID: UUID) {
        for task in tasks where task.isPersonal {
            registerPersonalTaskOwnership(for: task, householdID: householdID)
        }
    }

    /// Completion history is global rather than household-scoped. Retain the
    /// private IDs before removing a household so a later save in another
    /// household cannot upload those completions to its collaborators.
    private func retainOrphanedPersonalTaskOwnership(from household: Household) {
        householdIndex.orphanedPersonalTaskIDs.formUnion(household.personalTaskIDs)
        householdIndex.orphanedPersonalTaskIDs.formUnion(household.cloudPersonalTaskIDs)
        householdIndex.orphanedPersonalTaskIDs.formUnion(household.pendingPersonalTaskReleases)
    }

    private func personalTaskIDsForSync(householdID: UUID) -> Set<UUID> {
        guard let household = householdIndex.households.first(where: { $0.id == householdID }) else {
            return Set(tasks.filter(\.isPersonal).map(\.id))
        }
        return household.personalTaskIDs
            .union(household.cloudPersonalTaskIDs)
            .subtracting(household.pendingPersonalTaskReleases)
            .union(tasks.filter(\.isPersonal).map(\.id))
    }

    /// Completions are global across household workspaces, so every personal
    /// ownership source must be excluded before uploading to any one zone.
    private func privateTaskIDsForCompletionSync() -> Set<UUID> {
        var privateTaskIDs = Set<UUID>()
        for household in householdIndex.households {
            privateTaskIDs.formUnion(household.personalTaskIDs)
            privateTaskIDs.formUnion(household.cloudPersonalTaskIDs)
            privateTaskIDs.formUnion(household.pendingPersonalTaskReleases)
        }
        privateTaskIDs.formUnion(householdIndex.orphanedPersonalTaskIDs)
        privateTaskIDs.formUnion(tasks.filter(\.isPersonal).map(\.id))
        return privateTaskIDs
    }

    @discardableResult
    private func syncTasksWhileSerialized(householdID: UUID) async -> Bool {
        guard isHouseholdSharingEnabled,
              ckSync.isAvailable,
              let target = householdIndex.households.first(where: { $0.id == householdID }) else {
            return false
        }

        let personalIDs = personalTaskIDsForSync(householdID: householdID)
        let releasedIDs = target.pendingPersonalTaskReleases
        let synced = await ckSync.pushTasks(
            tasks,
            personalTaskIDs: personalIDs,
            deletingPersonalTaskIDs: releasedIDs,
            personalCompletionCleanupHouseholds: householdIndex.households,
            household: target
        )
        if synced, !releasedIDs.isEmpty {
            if let householdPosition = householdIndex.households.firstIndex(where: { $0.id == householdID }) {
                self.householdIndex.households[householdPosition].pendingPersonalTaskReleases.subtract(releasedIDs)
                self.householdIndex.households[householdPosition].cloudPersonalTaskIDs.subtract(releasedIDs)
                await store.saveHouseholdIndex(self.householdIndex)
            }
        }
        return synced
    }

    func addCustomTask(_ task: HouseholdTask) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            await addCustomTaskWhileSerialized(task)
        }
    }

    private func addCustomTaskWhileSerialized(_ task: HouseholdTask) async {
        let normalizedTask = normalizePersonalAssignment(task.withDefaultSchedule())
        tasks.append(normalizedTask)
        registerPersonalTaskOwnership(for: normalizedTask, householdID: activeHouseholdId)
        syncReminder(for: normalizedTask)
        await persistActiveTasksWhileSerialized()
    }

    /// Tasks that don't match a built-in catalog entry by name — counted
    /// against the free-tier custom-task limit.
    var customTaskCount: Int {
        let catalogNames = Set(taskCatalog.map { $0.name.lowercased() })
        return tasks.filter { !catalogNames.contains($0.name.lowercased()) }.count
    }

    func deleteTask(_ task: HouseholdTask) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            guard let currentTask = tasks.first(where: { $0.id == task.id }) else { return }
            await deleteTaskWhileSerialized(currentTask)
        }
    }

    private func deleteTaskWhileSerialized(_ task: HouseholdTask) async {
        tasks.removeAll { $0.id == task.id }
        notificationManager?.cancelTaskReminder(for: task)
        await persistActiveTasksWhileSerialized()
    }

    func updateTask(_ task: HouseholdTask) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            await updateTaskWhileSerialized(task)
        }
    }

    private func updateTaskWhileSerialized(_ task: HouseholdTask) async {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            let previousIsPersonal = tasks[idx].isPersonal
            var updated = normalizePersonalAssignment(task)
            if updated.isPersonal,
               !previousIsPersonal,
               !activeHousehold.ownerIsCurrentUser {
                // A participant may edit a shared task, but only the owner can
                // remove that task from the household for everyone.
                updated.isPersonal = false
            }
            if tasks[idx].recurrenceRule != updated.recurrenceRule {
                // Editing the recurrence rule of a task that's never been
                // completed gives it a fresh start instead of re-anchoring to
                // a stale creation date — see `HouseholdTask.createdAt`. A
                // completed task's occurrence depends only on
                // `lastCompleted`, so this is a no-op for it either way.
                if updated.lastCompleted == nil {
                    updated.createdAt = Date()
                }
                // A real schedule edit supersedes any pending manual
                // reschedule — otherwise a stale `scheduledOverrideDate`
                // would keep winning over the newly-edited schedule (see
                // `Recurrence.nextOccurrence`) until the task next
                // completes, making the edit silently appear to do nothing.
                updated.scheduledOverrideDate = nil
            }
            tasks[idx] = updated
            registerPersonalTaskOwnership(
                for: updated,
                previousIsPersonal: previousIsPersonal,
                householdID: activeHouseholdId
            )
            syncReminder(for: updated)
            await persistActiveTasksWhileSerialized()
        }
    }

    /// Moves `task`'s next occurrence to `date` for this cycle only — the
    /// drag-to-reschedule action in `ScheduleView`'s week view (issue #25).
    /// Scoped to a single occurrence: the task's recurring
    /// `frequency`/`scheduledWeekdays`/`scheduledDayOfMonth` are untouched,
    /// and completing the task later clears the override (see
    /// `completeTask`). Rejects a `date` before today — the week view lets
    /// you browse past weeks via the date picker, but rescheduling into the
    /// past would just make the task instantly and confusingly "N days
    /// overdue." Dropping a task back onto the day it's already shown on is
    /// a no-op, including an overdue task dropped back onto "today" — it's
    /// displayed there via carry-forward (see `Recurrence`'s doc comment),
    /// not because today is its true occurrence, so the no-op check mirrors
    /// `ScheduleView.tasksByDate`'s bucketing rule rather than comparing
    /// `date` against the raw occurrence directly. A thin wrapper around
    /// `updateTask` — it shares that method's persistence (dual-write,
    /// reminder sync) rather than a heavier one-off, and `RecurrenceRule`
    /// excludes `scheduledOverrideDate` so this can't spuriously trigger the
    /// never-completed-task `createdAt` reset meant for real schedule edits.
    func rescheduleTask(_ task: HouseholdTask, to date: Date, on referenceDate: Date = Date(), calendar: Calendar = .current) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            guard let currentTask = tasks.first(where: { $0.id == task.id }) else { return }
            await rescheduleTaskWhileSerialized(currentTask, to: date, on: referenceDate, calendar: calendar)
        }
    }

    private func rescheduleTaskWhileSerialized(
        _ task: HouseholdTask,
        to date: Date,
        on referenceDate: Date,
        calendar: Calendar
    ) async {
        let today = calendar.startOfDay(for: referenceDate)
        let targetDay = calendar.startOfDay(for: date)
        guard targetDay >= today, let currentOccurrence = task.nextOccurrence(calendar: calendar) else { return }

        let isAlreadyShownOnTargetDay = calendar.isDate(currentOccurrence, inSameDayAs: targetDay)
            || (calendar.isDate(targetDay, inSameDayAs: today) && Recurrence.isDue(occurrence: currentOccurrence, on: today, calendar: calendar))
        guard !isAlreadyShownOnTargetDay else { return }

        var updated = task
        updated.scheduledOverrideDate = targetDay
        await updateTaskWhileSerialized(updated)
    }

    /// Save exactly the catalog and custom tasks the user selected during
    /// onboarding. Fresh households start empty; nothing is assigned merely
    /// because a room was selected.
    func seedOnboardingTasks(recommendedTasks: [CatalogTask], customTasks: [HouseholdTask] = []) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            await seedOnboardingTasksWhileSerialized(
                recommendedTasks: recommendedTasks,
                customTasks: customTasks
            )
        }
    }

    private func seedOnboardingTasksWhileSerialized(
        recommendedTasks: [CatalogTask],
        customTasks: [HouseholdTask]
    ) async {
        var names = Set<String>()
        let catalogTasks = recommendedTasks.compactMap { catalogTask -> HouseholdTask? in
            let key = catalogTask.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, names.insert(key).inserted else { return nil }
            return catalogTask.toHouseholdTask()
        }
        let additionalTasks = customTasks.compactMap { customTask -> HouseholdTask? in
            let key = customTask.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, names.insert(key).inserted else { return nil }
            return normalizePersonalAssignment(customTask.withDefaultSchedule())
        }
        let selectedTasks = catalogTasks + additionalTasks
        guard !selectedTasks.isEmpty else { return }

        tasks = selectedTasks
        registerPersonalTaskOwnership(for: selectedTasks, householdID: activeHouseholdId)
        for task in tasks { syncReminder(for: task) }
        await persistActiveTasksWhileSerialized()
    }

    // MARK: - Avatar

    /// Owns and equips an item without debiting coins. The single place avatar
    /// acquisition happens, so any future side effect applies to every path.
    func grantAvatarItem(_ item: AvatarItem) async {
        await householdWorkspaceStore.withSerializedAccess {
            await grantAvatarItemWhileSerialized(item)
        }
    }

    private func grantAvatarItemWhileSerialized(_ item: AvatarItem) async {
        profile.avatarState.purchase(item)
        profile.avatarState.equip(item)
        await store.saveProfile(profile)
    }

    func purchaseAvatarItem(_ item: AvatarItem) async {
        await householdWorkspaceStore.withSerializedAccess {
            guard profile.coins >= item.cost else { return }
            profile.coins -= item.cost
            await grantAvatarItemWhileSerialized(item)
        }
    }

    /// Onboarding's companion picker only offers free items.
    func selectStarterAvatar(id: String) async {
        await householdWorkspaceStore.withSerializedAccess {
            guard let item = avatarItem(byId: id), item.cost == 0 else { return }
            await grantAvatarItemWhileSerialized(item)
        }
    }

    func equipAvatarItem(_ item: AvatarItem) async {
        await householdWorkspaceStore.withSerializedAccess {
            profile.avatarState.equip(item)
            await store.saveProfile(profile)
        }
    }

    func unequipAvatarItem(slot: AvatarSlot) async {
        await householdWorkspaceStore.withSerializedAccess {
            profile.avatarState.unequip(slot: slot)
            await store.saveProfile(profile)
        }
    }

    // MARK: - Supply Stock

    var lowSupplyCount: Int {
        supplyStock.values.filter { $0 == .low }.count
    }

    var outOfStockSupplyCount: Int {
        supplyStock.values.filter { $0 == .out }.count
    }

    var supplyAttentionCount: Int {
        lowSupplyCount + outOfStockSupplyCount
    }

    var shoppingList: [String] {
        supplyStock.filter { $0.value == .low || $0.value == .out }
            .keys.sorted()
    }

    func setSupplyStock(_ supply: String, stock: SupplyStock) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            supplyStock[supply] = stock
            await store.saveSupplyStock(supplyStock, for: activeHouseholdId)
        }
    }

    // MARK: - Streak

    /// Recomputes streak state from the completion log — and, as a side
    /// effect, re-plans the streak-at-risk notification to match (see
    /// `NotificationManager.syncStreakReminder`; a no-op when the plan is
    /// unchanged).
    private func refreshStreakState(asOf date: Date = Date()) {
        let summary = Recurrence.computeStreak(
            from: completions,
            asOf: date,
            calendar: .current
        )
        profile.currentStreak = summary.currentStreak
        profile.longestStreak = summary.longestStreak
        profile.lastActiveDate = summary.lastActiveDate
        notificationManager?.syncStreakReminder(streak: profile.currentStreak, lastActiveDate: profile.lastActiveDate)
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

    /// Persist the active workspace while `HouseholdWorkspaceStore` owns the
    /// serialized mutation transaction, so the active id and published state
    /// cannot change between mutation and disk writes.
    private func saveCurrentWorkspaceWhileSerialized() async {
        let householdID = activeHouseholdId
        await store.saveProfile(profile)
        await store.saveCompletions(completions)
        guard householdIndex.households.contains(where: { $0.id == householdID }) else { return }

        await store.saveTasks(tasks, for: householdID)
        syncDeviceUser(profile, into: householdID)
        await store.saveHouseholdIndex(householdIndex)
        updateWidgetData()
        if isHouseholdSharingEnabled && ckSync.isAvailable {
            guard let target = householdIndex.households.first(where: { $0.id == householdID }) else { return }
            _ = await syncTasksWhileSerialized(householdID: householdID)
            await ckSync.pushProfile(profile, household: target)
            let privateTaskIDs = privateTaskIDsForCompletionSync()
            for completion in completions where !privateTaskIDs.contains(completion.taskId) {
                await ckSync.pushCompletion(completion, household: target)
            }
        }
    }

    private func syncDeviceUser(_ profile: UserProfile, into householdID: UUID) {
        guard let hIdx = householdIndex.households.firstIndex(where: { $0.id == householdID }) else { return }
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

    /// Returns the period bonuses newly earned by the completion at `date`,
    /// keyed by period name — empty when none fired. Returning the breakdown
    /// (rather than just a total) lets the caller attribute it to the
    /// triggering `TaskCompletion` via `TaskCompletion.periodBonuses`, which
    /// `uncompleteTask` needs to reverse this exactly later.
    private func applyPeriodBonusesIfEarned(at date: Date) -> [String: Int] {
        var bonuses: [String: Int] = [:]

        if dueTasks.isEmpty {
            let xp = awardIfFirst(for: "daily", at: date, xp: dailyClearBonusXP)
            if xp > 0 { bonuses["daily"] = xp }
        }

        if earnedWeeklyConsistencyBonus(at: date) {
            let xp = awardIfFirst(for: "weekly", at: date, xp: weeklyConsistencyBonusXP)
            if xp > 0 { bonuses["weekly"] = xp }
        }

        if earnedMonthlyConsistencyBonus(at: date) {
            let xp = awardIfFirst(for: "monthly", at: date, xp: monthlyConsistencyBonusXP)
            if xp > 0 { bonuses["monthly"] = xp }
        }

        return bonuses
    }

    private func earnedWeeklyConsistencyBonus(at date: Date) -> Bool {
        let calendar = Calendar.current
        guard let interval = calendar.weekInterval(containing: date) else { return false }
        let completedTaskIDs = Set(
            completions
                .filter { interval.contains($0.completedAt) }
                .map(\.taskId)
        )
        let requiredTaskIDs = Set(recurringActiveTasks.map(\.id))
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
        let requiredTaskIDs = Set(recurringActiveTasks.map(\.id))
        return !requiredTaskIDs.isEmpty && requiredTaskIDs.isSubset(of: completedTaskIDs)
    }

    private func awardIfFirst(for period: String, at date: Date, xp: Int) -> Int {
        let key = bonusPeriodKey(period: period, date: date)
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return 0 }
        defaults.set(true, forKey: key)
        return xp
    }

    /// Clears the "already awarded" flag `awardIfFirst` set for `period` at
    /// `date` — the paired action `uncompleteTask` calls when undoing the
    /// specific completion that earned that period's bonus, so the bonus can
    /// genuinely be re-earned if the period is completed for real afterward.
    /// Safe to call unconditionally: only the one completion that won the
    /// award ever carries it in `periodBonuses`, so this never fires for a
    /// period this undo didn't actually earn.
    private func revokeAward(for period: String, at date: Date) {
        UserDefaults.standard.removeObject(forKey: bonusPeriodKey(period: period, date: date))
    }

    private func bonusPeriodKey(period: String, date: Date) -> String {
        let calendar = Calendar.current
        let anchorDate: Date
        switch period {
        case "weekly":
            anchorDate = calendar.weekInterval(containing: date)?.start ?? date
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

    // MARK: - Multi-household management

    /// The caller must hold serialized workspace access. Split from the public
    /// commit helper so destructive flows can revalidate under that access and
    /// then use the same snapshot-install boundary.
    private func performHouseholdTransitionWhileSerialized(
        _ transition: HouseholdWorkspaceStore.Transition
    ) async {
        let snapshot = await householdWorkspaceStore.commit(
            transition,
            to: householdIndex,
            profile: profile
        )
        householdIndex = snapshot.householdIndex
        if case .loaded(let loadedTasks, let loadedStock) = snapshot.workspaceUpdate {
            tasks = loadedTasks
            supplyStock = loadedStock
        }
    }

    /// Creates a new household and makes it active. UI gates this on Pro for
    /// the 2nd+ household. Starts with no tasks — the built-in catalog is
    /// only offered during onboarding.
    func createHousehold(name: String) async {
        await householdWorkspaceStore.withSerializedAccess {
            let id = UUID()
            let household = Household.newLocal(
                id: id,
                name: name.isEmpty ? "New Household" : name,
                members: [profile],
                zoneName: ZoneName.uniqueHousehold(for: id)
            )
            await performHouseholdTransitionWhileSerialized(.upsertAndActivate(household))
            logger.info("🏠 Created household '\(name, privacy: .public)' \(id.uuidString, privacy: .public)")
        }
    }

    /// Immediately leaves an already-accepted shared household and starts a
    /// fresh local one for onboarding. Local state changes first so choosing
    /// "create my own" never depends on network availability; CloudKit
    /// participant cleanup continues best-effort afterward.
    func leaveJoinedHouseholdForOnboarding() async {
        let joined = await householdWorkspaceStore.withSerializedAccess { () -> Household? in
            let joined = activeHousehold
            guard !joined.ownerIsCurrentUser else { return nil }
            retainOrphanedPersonalTaskOwnership(from: joined)

            let transition: HouseholdWorkspaceStore.Transition
            if let existingLocal = householdIndex.households.first(where: \.ownerIsCurrentUser) {
                transition = .removeAndActivate(removedID: joined.id, activeID: existingLocal.id)
            } else {
                let localID = UUID()
                let local = Household.newLocal(
                    id: localID,
                    name: "My Household",
                    members: [profile],
                    zoneName: ZoneName.uniqueHousehold(for: localID)
                )
                transition = .replaceAndActivate(removedID: joined.id, household: local)
            }
            await performHouseholdTransitionWhileSerialized(transition)
            pendingNameClash = nil
            return joined
        }
        guard let joined else { return }
        logger.info("🏠 Left joined household locally and switched to a local onboarding household")
        cleanCloudKitAfterLocalRemoval(of: joined)
    }

    private func cleanCloudKitAfterLocalRemoval(of household: Household) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.removeCloudKitDataBeforeLocalDeletion(from: [household])
            } catch {
                logger.warning("🏠 Deferred household cleanup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func switchHousehold(to id: UUID) async {
        await householdWorkspaceStore.withSerializedAccess {
            guard householdIndex.households.contains(where: { $0.id == id }) else { return }
            guard id != activeHouseholdId else { return }
            // Persist current household's state before swapping so nothing is lost.
            await saveCurrentWorkspaceWhileSerialized()
            await performHouseholdTransitionWhileSerialized(.activate(id))
            logger.info("🏠 Switched to household \(id.uuidString, privacy: .public)")
        }
    }

    func renameActiveProfile(to newName: String) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != profile.name else { return }
            profile.name = trimmed
            await saveCurrentWorkspaceWhileSerialized()
            detectNameClashInJoinedHouseholds()
        }
    }

    /// Whether another member of the active household already uses a display
    /// name. Onboarding and clash resolution share this policy so whitespace
    /// and case handling cannot drift between the prompt and persistence.
    func isProfileNameTakenInActiveHousehold(_ candidate: String) -> Bool {
        household(activeHousehold, hasMemberNamed: candidate, excluding: profile.id)
    }

    private func household(_ household: Household, hasMemberNamed candidate: String, excluding profileID: UUID) -> Bool {
        let normalizedCandidate = normalizedProfileName(candidate)
        guard !normalizedCandidate.isEmpty else { return false }
        return household.members.contains { member in
            member.id != profileID && normalizedProfileName(member.name) == normalizedCandidate
        }
    }

    private func normalizedProfileName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func renameHousehold(_ id: UUID, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await householdWorkspaceStore.withSerializedAccess {
            if let idx = householdIndex.households.firstIndex(where: { $0.id == id }) {
                householdIndex.households[idx].name = trimmed
                await store.saveHouseholdIndex(householdIndex)
            }
        }
    }

    /// Delete a household. Refuses to delete the last remaining household. If
    /// the active household is deleted, falls back to the first remaining one.
    func deleteHousehold(_ id: UUID) async throws {
        try await householdWorkspaceStore.withSerializedAccess {
            guard householdIndex.households.count > 1 else {
                logger.info("🏠 Refusing to delete last household")
                return
            }
            guard let target = householdIndex.households.first(where: { $0.id == id }) else { return }

            // Remove the server-side share before deleting the local row.
            // Owner deletion revokes every collaborator; joined-household
            // deletion removes only this device's participation.
            try await removeCloudKitDataBeforeLocalDeletion(from: [target])
            retainOrphanedPersonalTaskOwnership(from: target)

            if activeHouseholdId == id,
               let nextHousehold = householdIndex.households.first(where: { $0.id != id }) {
                await performHouseholdTransitionWhileSerialized(
                    .removeAndActivate(removedID: id, activeID: nextHousehold.id)
                )
            } else {
                await performHouseholdTransitionWhileSerialized(.removeInactive(id))
            }
            logger.info("🏠 Deleted household \(id.uuidString, privacy: .public)")
        }
    }

    func listHouseholds() -> [Household] {
        householdIndex.households
    }

    // MARK: - CloudKit Migration & Sync

    /// Households needing CloudKit cleanup before local deletion, split into
    /// two groups because `shareRecordName` alone isn't a reliable signal:
    /// builds before this feature never persisted it, so an owned household
    /// actually shared under an older build can still read `nil` here.
    /// - `confirmed`: known to need cleanup without a network round-trip —
    ///   `shareRecordName` is set, or the household is joined (a joined
    ///   household only exists because it was shared; the participant-leave
    ///   path re-derives the share directly from the zone, not this field).
    /// - `ambiguous`: every other owned household. Deliberately NOT narrowed
    ///   by the `isHouseholdSharingEnabled` device flag — that flag lives in
    ///   local `UserDefaults`, not the iCloud-synced `HouseholdIndex`, so a
    ///   second device on the same account (or a reinstall) starts with it
    ///   unset even for a household genuinely shared from another device,
    ///   which would silently skip the check entirely. Resolved by
    ///   `removeCloudKitDataBeforeLocalDeletion` with a best-effort,
    ///   read-only CloudKit check rather than assumed either way.
    /// Internal (not `private`) so `DataStoreTests` can pin this decision
    /// logic directly — it's already been wrong twice (over-broad on the
    /// device flag, then blind to unbackfilled legacy shares) and doesn't
    /// touch CloudKit itself, so it's worth testing without needing a live
    /// `ckSync.setup()` call, which traps on an unsigned test build.
    func householdCloudKitCleanupTargets(from households: [Household]) -> (confirmed: [Household], ambiguous: [Household]) {
        guard Features.cloudKitSharing else { return ([], []) }
        var confirmed: [Household] = []
        var ambiguous: [Household] = []
        for household in households {
            if household.shareRecordName != nil || !household.ownerIsCurrentUser {
                confirmed.append(household)
            } else {
                ambiguous.append(household)
            }
        }
        return (confirmed, ambiguous)
    }

    /// CloudKit cleanup is deliberately completed before local files are
    /// removed. `confirmed` households are known to be shared, so a failure
    /// to reach CloudKit for them blocks the deletion outright — retaining
    /// the local row is safer than stranding access on a server-side
    /// household with no local handle. `ambiguous` households are only
    /// *possibly* shared (most owned households never are), so they get a
    /// best-effort check: attempted when CloudKit is reachable, silently
    /// skipped otherwise, so an ordinary offline local-only deletion is
    /// never blocked by a household that almost certainly has nothing to
    /// clean up.
    private func removeCloudKitDataBeforeLocalDeletion(from households: [Household]) async throws {
        let (confirmed, ambiguous) = householdCloudKitCleanupTargets(from: households)
        guard !confirmed.isEmpty || !ambiguous.isEmpty else { return }

        await ckSync.setup()
        guard ckSync.isAvailable else {
            guard confirmed.isEmpty else {
                throw CloudKitSyncError.iCloudUnavailable(status: ckSync.syncError ?? "unknown")
            }
            return
        }

        for household in confirmed {
            try await ckSync.removeHouseholdCloudData(for: household)
        }
        for household in ambiguous {
            guard let hasShare = try? await ckSync.hasExistingShare(for: household), hasShare else { continue }
            try await ckSync.removeHouseholdCloudData(for: household)
        }
    }

    /// Users who already reset data on a build that reused `HouseholdZone`
    /// arrive here with a local onboarding household that still points at the
    /// old share. Delete that legacy zone before creating the replacement so
    /// existing invitees lose access and the new invite gets a new URL.
    private func isolateLegacyOnboardingHouseholdWhileSerialized() async throws -> Household {
        let target = activeHousehold
        let defaults = UserDefaults.standard
        guard target.ownerIsCurrentUser,
              target.zoneName == ZoneName.household,
              target.shareRecordName == nil,
              !defaults.bool(forKey: PrefKey.hasCompletedOnboarding),
              !defaults.bool(forKey: PrefKey.householdSharingEnabled) else {
            return target
        }

        try await ckSync.removeHouseholdCloudData(for: target)
        var isolated = target
        isolated.zoneName = ZoneName.uniqueHousehold(for: target.id)
        if let index = householdIndex.households.firstIndex(where: { $0.id == target.id }) {
            householdIndex.households[index] = isolated
            await store.saveHouseholdIndex(householdIndex)
        }
        return isolated
    }

    private func recordShareWhileSerialized(_ share: CKShare, for householdID: UUID) async {
        guard let index = householdIndex.households.firstIndex(where: { $0.id == householdID }) else { return }
        householdIndex.households[index].shareRecordName = share.recordID.recordName
        await store.saveHouseholdIndex(householdIndex)
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
        await householdWorkspaceStore.withSerializedAccess {
            await pullSerializedWorkspaceFromCloudKit(for: activeHousehold)
        }
    }

    private func pullSerializedWorkspaceFromCloudKit(for target: Household) async {
        guard activeHouseholdId == target.id,
              ckSync.isAvailable,
              let payload = await ckSync.pullAll(for: target) else { return }

        // Snapshot before merge for change detection
        let preProfiles = householdProfiles
        let preCompletionIDs = Set(completions.map(\.id))
        let preRank = leaderboard.firstIndex(where: { $0.id == profile.id }).map { $0 + 1 }

        // Personal tasks are intentionally local-only. Keep a local personal
        // copy, while a UUID-only CloudKit marker removes any stale shared
        // copy from this device without exposing the task's private details.
        let localPersonalTaskIDs = Set(tasks.filter(\.isPersonal).map(\.id))
        let cloudPersonalTaskIDs = payload.personalTaskIDs
            .union(payload.tasks.filter(\.isPersonal).map(\.id))
        let persistedPrivateTaskIDs = householdIndex.orphanedPersonalTaskIDs
            .union(target.personalTaskIDs)
            .union(target.cloudPersonalTaskIDs)
            .union(target.pendingPersonalTaskReleases)
        let releasedPersonalTaskIDs = householdIndex.households
            .first(where: { $0.id == target.id })?
            .pendingPersonalTaskReleases ?? []
        let sharedCloudTasks = payload.tasks.filter {
            !$0.isPersonal
                && !localPersonalTaskIDs.contains($0.id)
                && !cloudPersonalTaskIDs.contains($0.id)
                && !persistedPrivateTaskIDs.contains($0.id)
        }
        // Merge tasks: union by ID, keeping local custom and personal tasks
        // that are not part of the shared CloudKit snapshot.
        let cloudTaskIds = Set(sharedCloudTasks.map(\.id))
        let localOnly = tasks.filter { task in
            !cloudTaskIds.contains(task.id)
                && (!cloudPersonalTaskIDs.contains(task.id)
                    || task.isPersonal
                    || releasedPersonalTaskIDs.contains(task.id))
        }
        tasks = Self.mergeCloudTasks(sharedCloudTasks, preserving: tasks) + localOnly

        // Merge completions: union by ID
        let personalTaskIDs = localPersonalTaskIDs
            .union(cloudPersonalTaskIDs)
            .union(persistedPrivateTaskIDs)
        let newCompletions = payload.completions.filter {
            !personalTaskIDs.contains($0.taskId) && !preCompletionIDs.contains($0.id)
        }
        completions = (completions + newCompletions).sorted { $0.completedAt > $1.completedAt }

        // Merge profiles into the active household's members list, preferring
        // the higher-XP version for conflicts on the same profile id.
        if let hIdx = householdIndex.households.firstIndex(where: { $0.id == activeHouseholdId }) {
            householdIndex.households[hIdx].cloudPersonalTaskIDs = cloudPersonalTaskIDs.subtracting(releasedPersonalTaskIDs)
            householdIndex.households[hIdx].personalTaskIDs.formUnion(localPersonalTaskIDs)
            if let inviterName = payload.inviterName {
                householdIndex.households[hIdx].inviterName = inviterName
            }
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

        await saveCurrentWorkspaceWhileSerialized()
        logger.info("☁️ CloudKit pull merged: \(self.tasks.count) tasks, \(self.completions.count) completions")

        detectHouseholdChanges(preProfiles: preProfiles, preCompletionIDs: preCompletionIDs, preRank: preRank)
        detectNameClashInJoinedHouseholds()
    }

    /// CloudKit's production schema predates the local-only recurrence fields.
    /// Keep those values for tasks already known on this device while taking
    /// the cloud record as the source of truth for the shared task fields.
    /// A newly joined device has no local anchor and therefore uses the
    /// server-managed record creation date from `HouseholdTask.init(from:)`.
    static func mergeCloudTasks(
        _ cloudTasks: [HouseholdTask],
        preserving localTasks: [HouseholdTask]
    ) -> [HouseholdTask] {
        let localByID = localTasks.reduce(into: [UUID: HouseholdTask]()) { result, task in
            result[task.id] = task
        }
        return cloudTasks.map { cloudTask in
            guard let localTask = localByID[cloudTask.id] else { return cloudTask }
            var merged = cloudTask
            if cloudTask.lastCompleted == nil, localTask.lastCompleted == nil {
                merged.createdAt = localTask.createdAt
            }
            if cloudTask.scheduledOverrideDate == nil {
                merged.scheduledOverrideDate = localTask.scheduledOverrideDate
            }
            return merged
        }
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
                    profileId: member.id, profileName: member.name,
                    avatarState: member.avatarState,
                    event: .leveledUp(level: member.level), timestamp: Date()
                ))
            }

            // New achievements
            let prevAch = preAchievs[member.id] ?? []
            for achievId in Set(member.unlockedAchievements).subtracting(prevAch) {
                let name = allAchievements.first { $0.id == achievId }?.name ?? achievId
                newActivities.append(HouseholdActivity(
                    profileId: member.id, profileName: member.name,
                    avatarState: member.avatarState,
                    event: .achievementUnlocked(name: name), timestamp: Date()
                ))
            }

            // New completions attributed to this member
            let memberCompletions = completions.filter {
                $0.profileId == member.id && !preCompletionIDs.contains($0.id)
            }
            for c in memberCompletions.prefix(5) {
                newActivities.append(HouseholdActivity(
                    profileId: member.id, profileName: member.name,
                    avatarState: member.avatarState,
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
                    profileId: passer.id, profileName: passer.name,
                    avatarState: passer.avatarState,
                    event: .passedYou(newRank: post), timestamp: Date()
                ))
            }
        }

        guard !newActivities.isEmpty else { return }

        householdActivityFeed = Array((newActivities + householdActivityFeed).prefix(50))
        newActivities.forEach { notificationManager?.notifyHouseholdActivity($0) }
        logger.info("🏠 \(newActivities.count) new household activities detected")
    }

    /// Prepare a CKShare + container for presentation in UICloudSharingController.
    /// The share is saved (creating root + share atomically on first call, or
    /// reusing the existing one) so the share sheet has everything it needs
    /// to drive participant invites. The initial data snapshot finishes first
    /// so a recipient can never join an empty or stale share.
    struct PreparedHouseholdShare {
        let share: CKShare
        let container: CKContainer
        let householdID: UUID
        let householdName: String
    }

    func prepareHouseholdShare() async throws -> PreparedHouseholdShare {
        let expectedHouseholdID = activeHouseholdId
        return try await householdWorkspaceStore.withSerializedAccess {
            guard activeHouseholdId == expectedHouseholdID else {
                throw CloudKitSyncError.shareCreationFailed(detail: "active household changed; try again")
            }
            return try await prepareHouseholdShareWhileSerialized()
        }
    }

    private func prepareHouseholdShareWhileSerialized() async throws -> PreparedHouseholdShare {
        guard Features.cloudKitSharing else {
            throw CloudKitSyncError.shareCreationFailed(detail: "cloudKitSharing feature flag is off")
        }
        guard activeHousehold.ownerIsCurrentUser else {
            throw CloudKitSyncError.shareCreationFailed(detail: "cannot share a household joined from someone else")
        }
        AppDelegate.registerForRemoteNotifications()
        await ckSync.setup()
        guard ckSync.isAvailable else {
            throw CloudKitSyncError.iCloudUnavailable(status: ckSync.syncError ?? "unknown")
        }
        let target = try await isolateLegacyOnboardingHouseholdWhileSerialized()
        let share = try await ckSync.createOrFetchShare(for: target)
        await recordShareWhileSerialized(share, for: target.id)
        UserDefaults.standard.set(true, forKey: PrefKey.householdSharingEnabled)
        await ckSync.setupSubscriptions(for: target)
        let sharedTarget = householdIndex.households.first(where: { $0.id == target.id }) ?? target
        // This is still inside HouseholdWorkspaceStore's serialized boundary.
        // The throwing upload prevents a newer task/profile save from reaching
        // CloudKit first and prevents presenting an incomplete share.
        let personalTaskIDs = personalTaskIDsForSync(householdID: sharedTarget.id)
        let privateTaskIDs = privateTaskIDsForCompletionSync()
        let releasedPersonalTaskIDs = householdIndex.households
            .first(where: { $0.id == sharedTarget.id })?
            .pendingPersonalTaskReleases ?? []
        try await ckSync.uploadInitialShareSnapshot(
            tasks: tasks,
            profile: profile,
            completions: completions.filter { !privateTaskIDs.contains($0.taskId) },
            members: householdProfiles,
            personalTaskIDs: personalTaskIDs,
            deletingPersonalTaskIDs: releasedPersonalTaskIDs,
            personalCompletionCleanupHouseholds: householdIndex.households,
            household: sharedTarget
        )
        if !releasedPersonalTaskIDs.isEmpty,
           let householdIndex = householdIndex.households.firstIndex(where: { $0.id == sharedTarget.id }) {
            self.householdIndex.households[householdIndex].pendingPersonalTaskReleases.subtract(releasedPersonalTaskIDs)
            self.householdIndex.households[householdIndex].cloudPersonalTaskIDs.subtract(releasedPersonalTaskIDs)
            await store.saveHouseholdIndex(self.householdIndex)
        }
        return PreparedHouseholdShare(
            share: share,
            container: ckSync.cloudContainer,
            householdID: sharedTarget.id,
            householdName: sharedTarget.name
        )
    }

    // MARK: - iCloud Documents Sync

    /// Registers a MainActor-dispatched observer for `name` and appends its
    /// token to `tokens`. Shared by `startSyncObserver()` and
    /// `startDayRolloverObserver()` so each doesn't re-implement the
    /// addObserver + `Task { @MainActor in ... }` + token-bookkeeping
    /// boilerplate.
    private func observe(_ name: Notification.Name, into tokens: inout [NSObjectProtocol], handler: @escaping @MainActor () async -> Void) {
        tokens.append(
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in await handler() }
            }
        )
    }

    /// Start listening for remote iCloud and CloudKit changes. Safe to call once.
    func startSyncObserver() {
        guard syncObserverTokens.isEmpty else { return }

        observe(.dataDidSync, into: &syncObserverTokens) { [weak self] in
            await self?.load()
            logger.info("☁️ reloaded from iCloud sync")
        }

        observe(.cloudKitRemoteChange, into: &syncObserverTokens) { [weak self] in
            await self?.pullFromCloudKit()
            logger.info("☁️ pulled from CloudKit remote change")
        }
    }

    // MARK: - Midnight Rollover

    /// Start listening for the calendar day changing (or the system clock
    /// jumping, e.g. time zone travel) so `refreshForCurrentDay()` runs
    /// while the app is foregrounded, not only on next launch. Safe to call
    /// once.
    func startDayRolloverObserver() {
        guard dayRolloverObserverTokens.isEmpty else { return }
        for name in [Notification.Name.NSCalendarDayChanged, Notification.Name.NSSystemClockDidChange] {
            observe(name, into: &dayRolloverObserverTokens) { [weak self] in await self?.refreshForCurrentDay() }
        }
        #if os(iOS)
        observe(UIApplication.significantTimeChangeNotification, into: &dayRolloverObserverTokens) { [weak self] in await self?.refreshForCurrentDay() }
        #endif
    }

    /// Re-anchors `currentDay` to today. A no-op if the calendar day hasn't
    /// actually changed. Otherwise recomputes derived due/overdue state
    /// (via the `currentDay` observable), refreshes the widget's snapshot so
    /// its due count updates without requiring an app launch, and
    /// reschedules pending local task reminders against each task's current
    /// occurrence. Call on `scenePhase` becoming `.active` in addition to
    /// the notification-driven path in `startDayRolloverObserver()`, so a
    /// resume-from-background catches a rollover that happened while
    /// suspended.
    func refreshForCurrentDay() async {
        await householdWorkspaceStore.withSerializedAccess {
            let today = Calendar.current.startOfDay(for: Date())
            guard today != currentDay else { return }
            currentDay = today
            // A streak can die at this midnight boundary — recompute it (and
            // re-plan the streak-at-risk warning) rather than showing
            // yesterday's flame count until the next full load().
            refreshStreakState()
            updateWidgetData()
            for task in activeTasks {
                notificationManager?.scheduleTaskReminder(for: task)
            }
            logger.info("🌅 Rolled over to new day, recomputed due/overdue state")
        }
    }

    /// Stages an incoming household without calling `CKContainer.accept`, so
    /// first-time users can review it or choose to create their own household.
    func stagePendingOnboardingShare(_ metadata: CKShare.Metadata) {
        let info = ckSync.shareInfo(from: metadata)
        let recordID = metadata.share.recordID
        pendingOnboardingShare = PendingOnboardingShare(
            id: "\(recordID.zoneID.ownerName)|\(recordID.zoneID.zoneName)|\(recordID.recordName)",
            householdName: info.title,
            inviterName: info.inviterName,
            bootstrapHouseholdID: pristineOnboardingBootstrapID,
            metadata: metadata
        )
        logger.info("🏠 Staged first-launch invite for '\(info.title, privacy: .public)' pending onboarding choice")
    }

    /// Commit the staged first-launch invite after the recipient supplies the
    /// display name household members will see.
    func acceptPendingOnboardingShare(id: String, displayName: String) async throws {
        guard let pendingOnboardingShare, pendingOnboardingShare.id == id else {
            throw IncomingHouseholdShareError.missingPendingShare
        }
        let bootstrapHousehold = await replaceableOnboardingBootstrap(
            withID: pendingOnboardingShare.bootstrapHouseholdID
        )
        if let bootstrapHousehold {
            try await registerJoinedHousehold(
                from: pendingOnboardingShare.metadata,
                commit: .replaceBootstrap(bootstrapHousehold.id)
            )
        } else {
            try await registerJoinedHousehold(from: pendingOnboardingShare.metadata)
        }
        await renameActiveProfile(to: displayName)
        if self.pendingOnboardingShare?.id == pendingOnboardingShare.id {
            self.pendingOnboardingShare = nil
        }
    }

    private var pristineOnboardingBootstrapID: UUID? {
        let household = activeHousehold
        return isLocallyPristineOnboardingBootstrap(household) ? household.id : nil
    }

    private func isLocallyPristineOnboardingBootstrap(_ household: Household) -> Bool {
        household.id == activeHouseholdId
            && household.ownerIsCurrentUser
            && household.name == "My Household"
            && household.shareRecordName == nil
            && household.members.count <= 1
            && tasks.isEmpty
            && supplyStock.isEmpty
    }

    /// Fail closed before deleting the bootstrap: legacy shared households may
    /// have no persisted shareRecordName, so local fields alone cannot prove
    /// there are no collaborators. Joining already requires CloudKit; use that
    /// same online session for a read-only share check before replacement.
    private func replaceableOnboardingBootstrap(withID bootstrapID: UUID?) async -> Household? {
        guard Features.cloudKitSharing,
              let bootstrapID,
              let household = householdIndex.households.first(where: { $0.id == bootstrapID }),
              isLocallyPristineOnboardingBootstrap(household) else {
            return nil
        }
        await ckSync.setup()
        guard ckSync.isAvailable,
              let hasExistingShare = try? await ckSync.hasExistingShare(for: household),
              !hasExistingShare else {
            return nil
        }
        return household
    }

    /// Drop a staged invite without ever accepting CloudKit participation.
    /// The fresh local household remains active for the default onboarding.
    func declinePendingOnboardingShare() {
        pendingOnboardingShare = nil
    }

    /// Handle acceptance of a CKShare invite. Creates a new local `Household`
    /// row pointing at the inviter's shared zone, switches to it, and pulls
    /// its data. Idempotent — re-accepting a share for a zone we already
    /// joined just switches to that existing row.
    private enum JoinedHouseholdCommit {
        case preserveHouseholds
        case replaceBootstrap(UUID)
    }

    private struct JoinedHouseholdRegistration {
        let joined: Household
        let removedBootstrap: Household?
    }

    func registerJoinedHousehold(from metadata: CKShare.Metadata) async throws {
        try await registerJoinedHousehold(from: metadata, commit: .preserveHouseholds)
    }

    private func registerJoinedHousehold(
        from metadata: CKShare.Metadata,
        commit: JoinedHouseholdCommit
    ) async throws {
        guard Features.cloudKitSharing else {
            logger.error("🏠 Ignoring CKShare acceptance: cloudKitSharing feature is off")
            throw IncomingHouseholdShareError.sharingUnavailable
        }
        do {
            UserDefaults.standard.set(true, forKey: PrefKey.householdSharingEnabled)
            AppDelegate.registerForRemoteNotifications()
            await ckSync.setup()
            guard ckSync.isAvailable else {
                logger.error("🏠 acceptShare aborting — CloudKit not available: \(self.ckSync.syncError ?? "unknown", privacy: .public)")
                throw CloudKitSyncError.iCloudUnavailable(status: ckSync.syncError ?? "unknown")
            }
            let info = try await ckSync.acceptShare(from: metadata)
            let registration = await householdWorkspaceStore.withSerializedAccess {
                let registration = await commitAcceptedShareWhileSerialized(info, commit: commit)
                await ckSync.setupSubscriptions(for: registration.joined)
                await pullSerializedWorkspaceFromCloudKit(for: registration.joined)
                return registration
            }
            if let removedBootstrap = registration.removedBootstrap {
                cleanCloudKitAfterLocalRemoval(of: removedBootstrap)
            }
        } catch {
            logger.error("🏠 Failed to accept share: \(error.localizedDescription)")
            throw error
        }
    }

    /// Resolve the stable CloudKit zone identity and commit it in one
    /// serialized operation. Concurrent/repeated accepts therefore reuse the
    /// first row instead of both minting local UUIDs before either is visible.
    private func commitAcceptedShareWhileSerialized(
        _ info: HouseholdShareInfo,
        commit: JoinedHouseholdCommit
    ) async -> JoinedHouseholdRegistration {
        let existing = householdIndex.households.first { household in
            !household.ownerIsCurrentUser
                && household.zoneName == info.zoneName
                && household.ownerUserRecordName == info.ownerUserRecordName
        }

        let joined: Household
        if let existing {
            var updated = existing
            updated.shareRecordName = info.shareRecordName
            updated.inviterName = info.inviterName ?? existing.inviterName
            joined = updated
            logger.info("🏠 Re-joined existing shared household '\(existing.name, privacy: .public)'")
        } else {
            var newHousehold = Household.newJoined(
                name: info.title,
                members: [profile],
                zoneName: info.zoneName,
                ownerUserRecordName: info.ownerUserRecordName,
                inviterName: info.inviterName
            )
            newHousehold.shareRecordName = info.shareRecordName
            joined = newHousehold
            logger.info("🏠 Joined new shared household '\(info.title, privacy: .public)' zone=\(info.zoneName, privacy: .public)")
        }

        switch commit {
        case .preserveHouseholds:
            await performHouseholdTransitionWhileSerialized(.upsertAndActivate(joined))
            return JoinedHouseholdRegistration(joined: joined, removedBootstrap: nil)
        case .replaceBootstrap(let expectedID):
            guard let currentBootstrap = householdIndex.households.first(where: { $0.id == expectedID }),
                  isLocallyPristineOnboardingBootstrap(currentBootstrap) else {
                await performHouseholdTransitionWhileSerialized(.upsertAndActivate(joined))
                logger.info("🏠 Preserved onboarding household because it changed while the invite was accepted")
                return JoinedHouseholdRegistration(joined: joined, removedBootstrap: nil)
            }
            await performHouseholdTransitionWhileSerialized(
                .replaceAndActivate(removedID: currentBootstrap.id, household: joined)
            )
            return JoinedHouseholdRegistration(joined: joined, removedBootstrap: currentBootstrap)
        }
    }

    /// After joining a shared household, surface a UI prompt if the current
    /// profile name matches an existing member's. Keeps leaderboards and
    /// activity attribution unambiguous.
    private func detectNameClashInJoinedHouseholds() {
        pendingNameClash = nil
        let household = activeHousehold
        guard !household.ownerIsCurrentUser,
              !normalizedProfileName(profile.name).isEmpty,
              self.household(household, hasMemberNamed: profile.name, excluding: profile.id) else { return }
        let others = household.members.filter { $0.id != profile.id }
        pendingNameClash = NameClash(
            householdName: household.name,
            existingNames: others.map { $0.name },
            currentName: profile.name
        )
    }

    /// Resolve the pending name clash by renaming the active profile to a
    /// unique value. No-op when the new name still collides.
    func resolveNameClash(with newName: String) async {
        let expectedHouseholdID = activeHouseholdId
        await mutateActiveWorkspace(expectedHouseholdID: expectedHouseholdID) {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let clash = pendingNameClash else { return }
            guard !clash.existingNames.contains(where: {
                normalizedProfileName($0) == normalizedProfileName(trimmed)
            }), !isProfileNameTakenInActiveHousehold(trimmed) else { return }
            profile.name = trimmed
            await saveCurrentWorkspaceWhileSerialized()
            detectNameClashInJoinedHouseholds()
        }
    }

    // MARK: - Export/Import

    func exportData() async -> Data? {
        await householdWorkspaceStore.withSerializedAccess {
            await store.exportBackup(householdId: activeHouseholdId)
        }
    }

    func importData(_ data: Data) async -> Bool {
        let householdID = activeHouseholdId
        let success = await householdWorkspaceStore.withSerializedAccess {
            await store.importBackup(from: data, householdId: householdID)
        }
        if success { await load() }
        return success
    }

    func resetAll() async throws {
        try await householdWorkspaceStore.withSerializedAccess {
            try await resetAllWhileSerialized()
        }
    }

    private func resetAllWhileSerialized() async throws {
        // Reset clears every local household, so revoke/leave every known
        // CloudKit share first. If that cannot complete, keep local state so
        // the user is not left with an inaccessible shared household.
        try await removeCloudKitDataBeforeLocalDeletion(from: householdIndex.households)
        await store.resetAllData()
        // Pending local notifications reference the data being erased — a
        // stale streak warning or per-task reminder firing after a reset
        // would advertise state that no longer exists.
        notificationManager?.cancelAll()
        // Clear one-shot migration flags so a fresh load seeds a new default
        // household; clear onboarding flags so ContentView falls back to the
        // welcome screen the same way a fresh install would.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PrefKey.householdsLayoutMigratedV2)
        defaults.removeObject(forKey: PrefKey.defaultHouseholdId)
        defaults.removeObject(forKey: PrefKey.hasCompletedOnboarding)
        defaults.removeObject(forKey: PrefKey.onboardingHouseholdName)
        defaults.removeObject(forKey: PrefKey.onboardingPlayerName)
        defaults.removeObject(forKey: PrefKey.householdSharingEnabled)
        tasks = []
        profile = UserProfile()
        completions = []
        supplyStock = [:]
        householdIndex = makeFreshDefaultIndex()
        await saveCurrentWorkspaceWhileSerialized()
    }
}

private extension Array where Element == String {
    mutating func appendIfNew(_ element: String) {
        if !contains(element) { append(element) }
    }
}
