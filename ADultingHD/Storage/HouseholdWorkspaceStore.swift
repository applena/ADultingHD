import Foundation

/// Serialized operations for the household index and its scoped task/stock
/// workspace. This boundary owns file-operation ordering; DataStore publishes
/// completed snapshots to the UI without maintaining a parallel scheduler.
@MainActor
final class HouseholdWorkspaceStore {
    private enum OperationState {
        case idle
        case occupied(waiters: [CheckedContinuation<Void, Never>])
    }

    enum Transition {
        case upsertAndActivate(Household)
        case replaceAndActivate(removedID: UUID, household: Household)
        case activate(UUID)
        case removeAndActivate(removedID: UUID, activeID: UUID)
        case removeInactive(UUID)
    }

    enum WorkspaceUpdate {
        case unchanged
        case loaded(tasks: [HouseholdTask], supplyStock: [String: SupplyStock])
    }

    struct Snapshot {
        let householdIndex: HouseholdIndex
        let workspaceUpdate: WorkspaceUpdate
    }

    private let store: TaskStore
    private var operationState: OperationState = .idle

    init(store: TaskStore) {
        self.store = store
    }

    /// Serialize every operation that reads or changes the active household
    /// workspace. Reloads, CloudKit pulls, and typed transitions all cross
    /// this boundary, so DataStore never has to coordinate an in-flight file
    /// snapshot with its own parallel lock state.
    func withSerializedAccess<Result>(
        _ operation: @MainActor () async throws -> Result
    ) async rethrows -> Result {
        await acquireAccess()
        defer { releaseAccess() }
        return try await operation()
    }

    private func acquireAccess() async {
        switch operationState {
        case .idle:
            operationState = .occupied(waiters: [])
        case .occupied(var waiters):
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
                operationState = .occupied(waiters: waiters)
            }
        }
    }

    private func releaseAccess() {
        guard case .occupied(var waiters) = operationState else {
            assertionFailure("Released an idle household workspace")
            return
        }
        guard !waiters.isEmpty else {
            operationState = .idle
            return
        }
        let next = waiters.removeFirst()
        operationState = .occupied(waiters: waiters)
        next.resume()
    }

    func commit(
        _ transition: Transition,
        to currentIndex: HouseholdIndex,
        profile: UserProfile
    ) async -> Snapshot {
        var index = currentIndex
        var removedIDs: [UUID] = []
        var shouldLoadWorkspace = false

        switch transition {
        case .upsertAndActivate(let household):
            let isNew = upsert(household, profile: profile, in: &index)
            if isNew {
                await seedEmptyWorkspace(for: household.id)
            }
            index.activeHouseholdId = household.id
            shouldLoadWorkspace = true

        case .replaceAndActivate(let removedID, let household):
            index.households.removeAll { $0.id == removedID && $0.id != household.id }
            if removedID != household.id { removedIDs.append(removedID) }
            let isNew = upsert(household, profile: profile, in: &index)
            if isNew {
                await seedEmptyWorkspace(for: household.id)
            }
            index.activeHouseholdId = household.id
            shouldLoadWorkspace = true

        case .activate(let householdID):
            guard index.households.contains(where: { $0.id == householdID }) else {
                return Snapshot(householdIndex: currentIndex, workspaceUpdate: .unchanged)
            }
            index.activeHouseholdId = householdID
            upsert(profile: profile, in: &index, householdID: householdID)
            shouldLoadWorkspace = true

        case .removeAndActivate(let removedID, let activeID):
            guard removedID != activeID,
                  index.households.contains(where: { $0.id == activeID }) else {
                return Snapshot(householdIndex: currentIndex, workspaceUpdate: .unchanged)
            }
            index.households.removeAll { $0.id == removedID }
            removedIDs.append(removedID)
            index.activeHouseholdId = activeID
            upsert(profile: profile, in: &index, householdID: activeID)
            shouldLoadWorkspace = true

        case .removeInactive(let householdID):
            guard householdID != index.activeHouseholdId else {
                return Snapshot(householdIndex: currentIndex, workspaceUpdate: .unchanged)
            }
            index.households.removeAll { $0.id == householdID }
            removedIDs.append(householdID)
        }

        index.schemaVersion = HouseholdIndex.currentSchemaVersion
        await store.saveHouseholdIndex(index)
        for removedID in removedIDs {
            await store.deleteHouseholdDirectory(removedID)
        }

        guard shouldLoadWorkspace else {
            return Snapshot(householdIndex: index, workspaceUpdate: .unchanged)
        }
        let activeHouseholdID = index.activeHouseholdId
        let tasks = await store.loadTasks(for: activeHouseholdID)
        let supplyStock = await store.loadSupplyStock(for: activeHouseholdID)
        return Snapshot(
            householdIndex: index,
            workspaceUpdate: .loaded(
                tasks: tasks,
                supplyStock: supplyStock
            )
        )
    }

    /// Returns true when the household was inserted rather than updated.
    private func upsert(
        _ household: Household,
        profile: UserProfile,
        in index: inout HouseholdIndex
    ) -> Bool {
        var household = household
        if let memberIndex = household.members.firstIndex(where: { $0.id == profile.id }) {
            household.members[memberIndex] = profile
        } else {
            household.members.append(profile)
        }

        if let householdIndex = index.households.firstIndex(where: { $0.id == household.id }) {
            index.households[householdIndex] = household
            return false
        }
        index.households.append(household)
        return true
    }

    private func upsert(
        profile: UserProfile,
        in index: inout HouseholdIndex,
        householdID: UUID
    ) {
        guard let householdIndex = index.households.firstIndex(where: { $0.id == householdID }) else { return }
        if let memberIndex = index.households[householdIndex].members.firstIndex(where: { $0.id == profile.id }) {
            index.households[householdIndex].members[memberIndex] = profile
        } else {
            index.households[householdIndex].members.append(profile)
        }
    }

    private func seedEmptyWorkspace(for householdID: UUID) async {
        await store.saveTasks([], for: householdID)
        await store.saveSupplyStock([:], for: householdID)
    }
}
