import XCTest
@testable import ADultingHD

@MainActor
final class HouseholdInvitationTests: XCTestCase {
    private enum Failure: Error { case acceptance, fetch, upload }

    @MainActor
    private final class CloudBoundary {
        var payload = CloudKitPayload(tasks: [], completions: [], profiles: [], inviterName: "Alex", personalTaskIDs: [])
        var prepareCount = 0
        var acceptCount = 0
        var fetchCount = 0
        var uploads: [[HouseholdTask]] = []
        var failingAcceptance = false
        var failingFetch = false
        var failingUpload = false
        var onFetch: ((Household) async throws -> Void)?

        var client: HouseholdInvitationClient {
            HouseholdInvitationClient(
                prepare: { self.prepareCount += 1 },
                fetch: { household in
                    self.fetchCount += 1
                    if self.failingFetch { throw Failure.fetch }
                    try await self.onFetch?(household)
                    return self.payload
                },
                upload: { tasks, _, _ in
                    self.uploads.append(tasks)
                    if self.failingUpload { throw Failure.upload }
                }
            )
        }

        func accept(_ info: HouseholdShareInfo) throws -> HouseholdShareInfo {
            acceptCount += 1
            if failingAcceptance { throw Failure.acceptance }
            return info
        }
    }

    private struct Fixture {
        let root: URL
        let storage: TaskStore
        let data: DataStore
        let cloud: CloudBoundary
        let sourceID: UUID
    }

    private func fixture() async throws -> Fixture {
        try StorageTestPreferences.preserve(in: self)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let storage = TaskStore(directory: root)
        var profile = UserProfile()
        profile.name = "Taylor"
        profile.totalXP = 120
        profile.coins = 120
        let source = Household.newLocal(name: "Original home", members: [profile])
        await storage.saveProfile(profile)
        try await storage.saveHouseholdIndexReliably(HouseholdIndex(
            households: [source], activeHouseholdId: source.id, schemaVersion: HouseholdIndex.currentSchemaVersion
        ))
        let cloud = CloudBoundary()
        let data = DataStore(store: storage, invitationClient: cloud.client)
        await data.load()
        return Fixture(root: root, storage: storage, data: data, cloud: cloud, sourceID: source.id)
    }

    private func info(owner: String = "owner-alex", zone: String = "shared-home", share: String = "share-1") -> HouseholdShareInfo {
        HouseholdShareInfo(shareRecordName: share, zoneName: zone, ownerUserRecordName: owner,
                           title: "Maple House", inviterName: "Alex")
    }

    private func task(_ name: String, id: UUID = UUID(), supplies: [String] = []) -> HouseholdTask {
        HouseholdTask(id: id, name: name, description: "", category: .general, frequency: .unscheduled,
                      estimatedMinutes: 15, difficulty: .medium, supplies: supplies, isActive: true)
    }

    private func completion(taskID: UUID, profileID: UUID?, householdID: UUID? = nil, date: Date = Date()) -> TaskCompletion {
        TaskCompletion(id: UUID(), taskId: taskID, taskName: "Completed chore", completedAt: date,
                       xpEarned: 25, streakBonus: 0, notes: nil, profileId: profileID, householdId: householdID)
    }

    @discardableResult
    private func stage(_ fixture: Fixture, _ info: HouseholdShareInfo? = nil) throws -> String {
        let invitation = info ?? self.info()
        fixture.data.stageHouseholdInvitation(info: invitation) { try fixture.cloud.accept(invitation) }
        return try XCTUnwrap(fixture.data.pendingHouseholdInvitation?.id)
    }

    func testStagingAndDecliningDoNotAcceptOrChangeExistingHome() async throws {
        let f = try await fixture()
        let sourceTask = task("Water plants")
        await f.data.addCustomTask(sourceTask)
        let id = try stage(f)

        XCTAssertEqual(f.data.pendingHouseholdInvitation?.householdName, "Maple House")
        XCTAssertEqual(f.data.pendingHouseholdInvitation?.inviterName, "Alex")
        XCTAssertEqual(f.data.activeHouseholdId, f.sourceID)
        XCTAssertEqual(f.data.tasks.map(\.id), [sourceTask.id])
        XCTAssertEqual(f.data.invitationMergeSources.map(\.id), [f.sourceID])
        XCTAssertEqual(f.cloud.acceptCount, 0)
        XCTAssertEqual(f.cloud.prepareCount, 0)
        XCTAssertFalse(f.data.isJoiningHousehold)
        f.data.declinePendingHouseholdInvitation()

        XCTAssertNil(f.data.pendingHouseholdInvitation)
        XCTAssertEqual(f.data.listHouseholds().map(\.id), [f.sourceID])
        XCTAssertEqual(f.cloud.acceptCount, 0)
        do {
            try await f.data.acceptPendingHouseholdInvitation(id: id)
            XCTFail("A declined invitation must no longer be accepted")
        } catch IncomingHouseholdShareError.missingPendingShare { }
    }

    func testRepeatedDeliveriesAreDeduplicatedWhileDistinctInvitationsRemainQueued() async throws {
        let f = try await fixture()
        let first = info()
        let second = info(owner: "owner-jamie")
        let firstID = try stage(f, first)
        try stage(f, first)
        try stage(f, second)
        try stage(f, second)
        XCTAssertEqual(f.data.pendingHouseholdInvitation?.id, firstID)

        f.data.declinePendingHouseholdInvitation()
        XCTAssertEqual(f.data.pendingHouseholdInvitation?.id, "owner-jamie|shared-home|share-1")
        f.data.declinePendingHouseholdInvitation()
        XCTAssertNil(f.data.pendingHouseholdInvitation)
        XCTAssertEqual(f.cloud.acceptCount, 0)
    }

    func testAddHomePreservesSourceLoadsInvitedTasksAndPersistsSelection() async throws {
        let f = try await fixture()
        let sourceTask = task("Water plants")
        let invitedTask = task("Feed the cat")
        await f.data.addCustomTask(sourceTask)
        var owner = UserProfile()
        owner.name = "Alex"
        let remoteCompletion = completion(taskID: invitedTask.id, profileID: owner.id)
        f.cloud.payload = CloudKitPayload(tasks: [invitedTask], completions: [remoteCompletion], profiles: [owner],
                                         inviterName: owner.name, personalTaskIDs: [])
        let xpBefore = f.data.profile.totalXP
        let id = try stage(f)
        try await f.data.acceptPendingHouseholdInvitation(id: id)
        let joinedID = f.data.activeHouseholdId

        XCTAssertNotEqual(joinedID, f.sourceID)
        XCTAssertEqual(f.data.listHouseholds().count, 2)
        XCTAssertEqual(f.data.tasks.map(\.id), [invitedTask.id])
        XCTAssertEqual(f.data.profile.totalXP, xpBefore)
        XCTAssertEqual(f.data.completions.first?.householdId, joinedID)
        XCTAssertEqual(f.data.householdProfiles.first(where: { $0.id == owner.id })?.name, "Alex")
        XCTAssertEqual(f.cloud.acceptCount, 1)
        XCTAssertEqual(f.cloud.fetchCount, 1)
        XCTAssertTrue(f.cloud.uploads.isEmpty)
        XCTAssertNil(f.data.pendingHouseholdInvitation)
        let sourceTasks = await f.storage.loadTasks(for: f.sourceID)
        XCTAssertEqual(sourceTasks.map(\.id), [sourceTask.id])

        let reopened = DataStore(store: TaskStore(directory: f.root), invitationClient: f.cloud.client)
        await reopened.load()
        XCTAssertEqual(reopened.activeHouseholdId, joinedID)
        XCTAssertEqual(reopened.tasks.map(\.id), [invitedTask.id])
        XCTAssertEqual(reopened.listHouseholds().count, 2)
    }

    func testFailedAcceptanceKeepsOriginalHomeAndAllowsRetry() async throws {
        let f = try await fixture()
        let sourceTask = task("Water plants")
        await f.data.addCustomTask(sourceTask)
        f.cloud.failingAcceptance = true
        let id = try stage(f)
        do {
            try await f.data.acceptPendingHouseholdInvitation(id: id)
            XCTFail("Acceptance failure must be surfaced")
        } catch Failure.acceptance { }
        XCTAssertEqual(f.data.activeHouseholdId, f.sourceID)
        XCTAssertEqual(f.data.tasks.map(\.id), [sourceTask.id])
        XCTAssertEqual(f.data.listHouseholds().count, 1)
        XCTAssertEqual(f.data.pendingHouseholdInvitation?.id, id)
        XCTAssertFalse(f.data.isJoiningHousehold)
        XCTAssertEqual(f.cloud.fetchCount, 0)

        f.cloud.failingAcceptance = false
        try await f.data.acceptPendingHouseholdInvitation(id: id)
        XCTAssertEqual(f.cloud.acceptCount, 2)
        XCTAssertEqual(f.data.listHouseholds().count, 2)
    }

    func testFailedFetchRetriesWithoutAcceptingParticipationTwice() async throws {
        let f = try await fixture()
        let sourceTask = task("Water plants")
        await f.data.addCustomTask(sourceTask)
        f.cloud.failingFetch = true
        let id = try stage(f)
        do {
            try await f.data.acceptPendingHouseholdInvitation(id: id)
            XCTFail("An incomplete fetch must not complete the join")
        } catch Failure.fetch { }
        XCTAssertEqual(f.data.activeHouseholdId, f.sourceID)
        XCTAssertEqual(f.data.tasks.map(\.id), [sourceTask.id])
        XCTAssertEqual(f.data.listHouseholds().count, 1)
        XCTAssertEqual(f.data.pendingHouseholdInvitation?.id, id)
        XCTAssertEqual(f.cloud.acceptCount, 1)

        f.cloud.failingFetch = false
        try await f.data.acceptPendingHouseholdInvitation(id: id)
        XCTAssertEqual(f.cloud.acceptCount, 1)
        XCTAssertEqual(f.cloud.fetchCount, 2)
        XCTAssertEqual(f.data.listHouseholds().count, 2)
    }

    func testOnboardingOffersRestoredChoresButNotAnEmptyBootstrap() async throws {
        let f = try await fixture()
        await f.data.renameHousehold(f.sourceID, to: "My Household")
        XCTAssertTrue(f.data.onboardingMergeSources.isEmpty)
        await f.data.addCustomTask(task("Clean bathroom"))
        XCTAssertEqual(f.data.onboardingMergeSources.map(\.id), [f.sourceID])
    }

    func testBringChoresAfterJoiningPreservesSourceAndDoesNotReacceptShare() async throws {
        let f = try await fixture()
        let bathroom = task("Clean bathroom")
        var personal = task("Private reminder")
        personal.isPersonal = true
        await f.data.addCustomTask(bathroom)
        await f.data.addCustomTask(personal)
        let destinationTask = task("Vacuum")
        f.cloud.payload = CloudKitPayload(tasks: [destinationTask], completions: [], profiles: [],
                                         inviterName: "Alex", personalTaskIDs: [])
        let invitationID = try stage(f)
        try await f.data.acceptPendingHouseholdInvitation(id: invitationID)
        let destinationID = f.data.activeHouseholdId
        XCTAssertEqual(f.data.tasks.map(\.id), [destinationTask.id])

        try await f.data.mergeChores(from: f.sourceID, into: destinationID)
        XCTAssertEqual(Set(f.data.tasks.map(\.id)), [destinationTask.id, bathroom.id])
        XCTAssertEqual(f.cloud.uploads.last?.map(\.id), [bathroom.id])
        XCTAssertEqual(f.cloud.acceptCount, 1)
        let savedSource = await f.storage.loadTasks(for: f.sourceID)
        XCTAssertEqual(Set(savedSource.map(\.id)), [bathroom.id, personal.id])

        try await f.data.mergeChores(from: f.sourceID, into: destinationID)
        XCTAssertEqual(f.data.tasks.count, 2)
        XCTAssertEqual(f.cloud.uploads.last?.count, 0)
        XCTAssertEqual(f.cloud.acceptCount, 1)
        await f.data.load()
        XCTAssertEqual(f.data.activeHouseholdId, destinationID)
        XCTAssertEqual(Set(f.data.tasks.map(\.id)), [destinationTask.id, bathroom.id])
    }

    func testLaterMergeFailureKeepsBothHomesAndCanBeRetried() async throws {
        let f = try await fixture()
        let bathroom = task("Clean bathroom")
        await f.data.addCustomTask(bathroom)
        let invitationID = try stage(f)
        try await f.data.acceptPendingHouseholdInvitation(id: invitationID)
        let destinationID = f.data.activeHouseholdId
        f.cloud.failingUpload = true
        do {
            try await f.data.mergeChores(from: f.sourceID, into: destinationID)
            XCTFail("Upload failure must not report a completed merge")
        } catch Failure.upload { }
        XCTAssertTrue(f.data.tasks.isEmpty)
        XCTAssertEqual(f.data.listHouseholds().count, 2)
        XCTAssertFalse(f.data.isJoiningHousehold)
        let savedSource = await f.storage.loadTasks(for: f.sourceID)
        XCTAssertEqual(savedSource.map(\.id), [bathroom.id])
        f.cloud.failingUpload = false
        try await f.data.mergeChores(from: f.sourceID, into: destinationID)
        XCTAssertEqual(f.data.tasks.map(\.id), [bathroom.id])
    }

    func testLaterMergeRejectsMissingAndOwnedDestinations() async throws {
        let f = try await fixture()
        for destinationID in [UUID(), f.sourceID] {
            do {
                try await f.data.mergeChores(from: f.sourceID, into: destinationID)
                XCTFail("Must merge into an existing joined home")
            } catch IncomingHouseholdShareError.mergeDestinationUnavailable { }
        }
        XCTAssertEqual(f.cloud.prepareCount, 0)
        XCTAssertTrue(f.cloud.uploads.isEmpty)
    }

    func testMergePreservesDestinationEditsPrivateSourceAndProgressAndIsIdempotent() async throws {
        let f = try await fixture()
        let duplicateID = UUID()
        let sourceConflict = task("Source wording", id: duplicateID, supplies: ["Soap"])
        var destinationConflict = sourceConflict
        destinationConflict.name = "Destination wording"
        var addition = task("Water plants", supplies: ["Plant food"])
        addition.defaultAssigneeId = UUID()
        var personal = task("Private appointment", supplies: ["Private medicine"])
        personal.isPersonal = true
        await f.data.addCustomTask(sourceConflict)
        await f.data.addCustomTask(addition)
        await f.data.addCustomTask(personal)
        await f.data.completeTask(addition)
        await f.data.setSupplyStock("Soap", stock: .low)
        await f.data.setSupplyStock("Plant food", stock: .out)
        await f.data.setSupplyStock("Private medicine", stock: .low)
        let originalCompletions = Set(f.data.completions.map(\.id))
        let xpBefore = f.data.profile.totalXP
        let coinsBefore = f.data.profile.coins
        let taskCountBefore = f.data.profile.totalTasksCompleted
        f.cloud.payload = CloudKitPayload(tasks: [destinationConflict], completions: [], profiles: [],
                                         inviterName: "Alex", personalTaskIDs: [])
        let id = try stage(f)
        try await f.data.acceptPendingHouseholdInvitation(id: id, mergeFrom: f.sourceID)
        let joinedID = f.data.activeHouseholdId

        XCTAssertEqual(Set(f.data.tasks.map(\.id)), [duplicateID, addition.id])
        XCTAssertEqual(f.data.tasks.first(where: { $0.id == duplicateID })?.name, "Destination wording")
        XCTAssertNil(f.data.tasks.first(where: { $0.id == addition.id })?.defaultAssigneeId)
        XCTAssertEqual(f.data.supplyStock, ["Soap": .low, "Plant food": .out])
        XCTAssertEqual(f.cloud.uploads.count, 1)
        XCTAssertEqual(f.cloud.uploads.first?.map(\.id), [addition.id])
        XCTAssertEqual(f.data.profile.totalXP, xpBefore)
        XCTAssertEqual(f.data.profile.coins, coinsBefore)
        XCTAssertEqual(f.data.profile.totalTasksCompleted, taskCountBefore)
        XCTAssertEqual(Set(f.data.completions.map(\.id)), originalCompletions)
        XCTAssertEqual(f.data.completions.first?.householdId, f.sourceID)
        let sourceBackup = await f.storage.loadTasks(for: f.sourceID)
        let sourceStock = await f.storage.loadSupplyStock(for: f.sourceID)
        XCTAssertEqual(Set(sourceBackup.map(\.id)), [duplicateID, addition.id, personal.id])
        XCTAssertEqual(sourceStock["Private medicine"], .low)

        let repeatID = try stage(f)
        try await f.data.acceptPendingHouseholdInvitation(id: repeatID, mergeFrom: f.sourceID)
        XCTAssertEqual(f.data.activeHouseholdId, joinedID)
        XCTAssertEqual(f.data.tasks.count, 2)
        XCTAssertEqual(f.data.listHouseholds().count, 2)
        // A completed join releases its acceptance cache so reopening a link
        // can rejoin after leaving. Only unfinished transactions reuse acceptance.
        XCTAssertEqual(f.cloud.acceptCount, 2)
        XCTAssertEqual(f.cloud.uploads.last?.count, 0)
        XCTAssertEqual(f.data.profile.totalXP, xpBefore)
        XCTAssertEqual(Set(f.data.completions.map(\.id)), originalCompletions)
    }

    func testFailedMergeUploadPreservesSourceAndRetryUsesSameTaskIDs() async throws {
        let f = try await fixture()
        let sourceTask = task("Water plants")
        await f.data.addCustomTask(sourceTask)
        f.cloud.failingUpload = true
        let id = try stage(f)
        do {
            try await f.data.acceptPendingHouseholdInvitation(id: id, mergeFrom: f.sourceID)
            XCTFail("Upload failure must not publish the destination")
        } catch Failure.upload { }
        XCTAssertEqual(f.data.activeHouseholdId, f.sourceID)
        XCTAssertEqual(f.data.tasks.map(\.id), [sourceTask.id])
        XCTAssertEqual(f.data.listHouseholds().count, 1)
        XCTAssertEqual(f.data.pendingHouseholdInvitation?.id, id)

        f.cloud.failingUpload = false
        try await f.data.acceptPendingHouseholdInvitation(id: id, mergeFrom: f.sourceID)
        XCTAssertEqual(f.cloud.acceptCount, 1)
        XCTAssertEqual(f.cloud.uploads.map { $0.map(\.id) }, [[sourceTask.id], [sourceTask.id]])
        let sourceBackup = await f.storage.loadTasks(for: f.sourceID)
        XCTAssertEqual(sourceBackup.map(\.id), [sourceTask.id])
        XCTAssertEqual(f.data.tasks.map(\.id), [sourceTask.id])
    }

    func testFailedLocalWorkspaceWritePreservesOriginalAndPendingInvitation() async throws {
        let f = try await fixture()
        let sourceTask = task("Water plants")
        await f.data.addCustomTask(sourceTask)
        f.cloud.onFetch = { joined in
            let blockedFile = f.root.appendingPathComponent("households/\(joined.id.uuidString)/task_planning.json")
            try FileManager.default.createDirectory(at: blockedFile, withIntermediateDirectories: true)
        }
        let id = try stage(f)
        do {
            try await f.data.acceptPendingHouseholdInvitation(id: id, mergeFrom: f.sourceID)
            XCTFail("A partial local write must not complete the join")
        } catch {
            XCTAssertTrue(error is CocoaError)
        }
        XCTAssertEqual(f.data.activeHouseholdId, f.sourceID)
        XCTAssertEqual(f.data.tasks.map(\.id), [sourceTask.id])
        XCTAssertEqual(f.data.pendingHouseholdInvitation?.id, id)
        XCTAssertEqual(f.data.listHouseholds().count, 1)
        let sourceBackup = await f.storage.loadTasks(for: f.sourceID)
        XCTAssertEqual(sourceBackup.map(\.id), [sourceTask.id])
        f.cloud.onFetch = nil
        try await f.data.acceptPendingHouseholdInvitation(id: id, mergeFrom: f.sourceID)
        XCTAssertEqual(f.cloud.acceptCount, 1)
        XCTAssertEqual(f.data.listHouseholds().count, 2)
    }

    func testFailedIndexCommitDoesNotPublishJoinedHomeAndCanRetry() async throws {
        let f = try await fixture()
        let sourceTask = task("Water plants")
        await f.data.addCustomTask(sourceTask)
        let indexURL = f.root.appendingPathComponent("households.json")
        let preservedIndexURL = f.root.appendingPathComponent("original-index.json")
        f.cloud.onFetch = { _ in
            try FileManager.default.moveItem(at: indexURL, to: preservedIndexURL)
            try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: true)
        }
        let id = try stage(f)
        do {
            try await f.data.acceptPendingHouseholdInvitation(id: id, mergeFrom: f.sourceID)
            XCTFail("Failure saving the household index must not publish a successful join")
        } catch {
            XCTAssertTrue(error is CocoaError)
        }
        XCTAssertEqual(f.data.activeHouseholdId, f.sourceID)
        XCTAssertEqual(f.data.listHouseholds().map(\.id), [f.sourceID])
        XCTAssertEqual(f.data.tasks.map(\.id), [sourceTask.id])
        XCTAssertEqual(f.data.pendingHouseholdInvitation?.id, id)
        let sourceBackup = await f.storage.loadTasks(for: f.sourceID)
        XCTAssertEqual(sourceBackup.map(\.id), [sourceTask.id])

        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.moveItem(at: preservedIndexURL, to: indexURL)
        f.cloud.onFetch = nil
        try await f.data.acceptPendingHouseholdInvitation(id: id, mergeFrom: f.sourceID)
        XCTAssertEqual(f.cloud.acceptCount, 1)
        XCTAssertEqual(f.data.listHouseholds().count, 2)
    }

    func testSameZoneNameOwnedByDifferentPeopleCreatesSeparateHomes() async throws {
        let f = try await fixture()
        let firstID = try stage(f, info(owner: "owner-one"))
        try await f.data.acceptPendingHouseholdInvitation(id: firstID)
        let firstJoinedID = f.data.activeHouseholdId
        let secondID = try stage(f, info(owner: "owner-two"))
        try await f.data.acceptPendingHouseholdInvitation(id: secondID)

        XCTAssertNotEqual(f.data.activeHouseholdId, firstJoinedID)
        XCTAssertEqual(f.data.listHouseholds().count, 3)
        XCTAssertEqual(Set(f.data.listHouseholds().compactMap(\.ownerUserRecordName)), ["owner-one", "owner-two"])
    }

    func testSwitchQueuedDuringJoinCannotRedirectMergeIntoAnotherHome() async throws {
        let f = try await fixture()
        let sourceTask = task("Source chore")
        await f.data.addCustomTask(sourceTask)
        await f.data.createHousehold(name: "Unrelated home")
        let unrelatedID = f.data.activeHouseholdId
        let unrelatedTask = task("Unrelated chore")
        await f.data.addCustomTask(unrelatedTask)
        await f.data.switchHousehold(to: f.sourceID)
        let fetchStarted = expectation(description: "Fetch paused while workspace is locked")
        var releaseFetch: CheckedContinuation<Void, Never>?
        f.cloud.onFetch = { _ in
            await withCheckedContinuation { continuation in
                releaseFetch = continuation
                fetchStarted.fulfill()
            }
        }
        let id = try stage(f)
        let joining = Task { try await f.data.acceptPendingHouseholdInvitation(id: id, mergeFrom: f.sourceID) }
        let fetchResult = await XCTWaiter.fulfillment(of: [fetchStarted], timeout: 2)
        XCTAssertEqual(fetchResult, .completed)
        let switching = Task { await f.data.switchHousehold(to: unrelatedID) }
        releaseFetch?.resume()
        try await joining.value
        await switching.value

        XCTAssertEqual(f.data.activeHouseholdId, unrelatedID)
        XCTAssertEqual(f.data.tasks.map(\.id), [unrelatedTask.id])
        let joined = try XCTUnwrap(f.data.listHouseholds().first(where: { !$0.ownerIsCurrentUser }))
        let joinedTasks = await f.storage.loadTasks(for: joined.id)
        XCTAssertEqual(joinedTasks.map(\.id), [sourceTask.id])
        XCTAssertEqual(f.cloud.uploads.first?.map(\.id), [sourceTask.id])
    }

    func testSharingCompletionsRequiresHouseholdProvenanceAndExcludesPrivateTasks() {
        let householdID = UUID()
        let otherHouseholdID = UUID()
        let catalogTaskID = UUID()
        let privateTaskID = UUID()
        let allowed = completion(taskID: catalogTaskID, profileID: UUID(), householdID: householdID)
        let differentHome = completion(taskID: catalogTaskID, profileID: UUID(), householdID: otherHouseholdID)
        let ambiguousLegacy = completion(taskID: catalogTaskID, profileID: nil)
        let privateCompletion = completion(taskID: privateTaskID, profileID: UUID(), householdID: householdID)
        let shared = DataStore.completionsForSharing([allowed, differentHome, ambiguousLegacy, privateCompletion],
                                                     householdID: householdID, privateTaskIDs: [privateTaskID])
        XCTAssertEqual(shared.map(\.id), [allowed.id])
    }

    func testLegacyAttributionKeepsDuplicateCatalogIDsAndUnknownTasksLocal() {
        let home = UUID()
        let other = UUID()
        let uniqueTaskID = UUID()
        let catalogTaskID = UUID()
        let unique = completion(taskID: uniqueTaskID, profileID: nil)
        let ambiguous = completion(taskID: catalogTaskID, profileID: nil)
        let unknown = completion(taskID: UUID(), profileID: nil)
        let alreadyScoped = completion(taskID: uniqueTaskID, profileID: UUID(), householdID: other)
        let scoped = DataStore.attributingLegacyCompletions([unique, ambiguous, unknown, alreadyScoped], ownersByTaskID: [
            uniqueTaskID: [home], catalogTaskID: [home, other]
        ])
        XCTAssertEqual(scoped[0].householdId, home)
        XCTAssertNil(scoped[1].householdId)
        XCTAssertNil(scoped[2].householdId)
        XCTAssertEqual(scoped[3].householdId, other)
    }

    func testUndoRejectsOtherMembersOtherHomesAndOlderCompletions() async throws {
        let f = try await fixture()
        let own = completion(taskID: UUID(), profileID: f.data.profile.id, householdID: f.sourceID)
        let otherMember = completion(taskID: UUID(), profileID: UUID(), householdID: f.sourceID)
        let otherHome = completion(taskID: UUID(), profileID: f.data.profile.id, householdID: UUID())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let old = completion(taskID: UUID(), profileID: f.data.profile.id, householdID: f.sourceID, date: yesterday)
        XCTAssertTrue(f.data.canUndoCompletion(own))
        XCTAssertFalse(f.data.canUndoCompletion(otherMember))
        XCTAssertFalse(f.data.canUndoCompletion(otherHome))
        XCTAssertFalse(f.data.canUndoCompletion(old))
        f.data.completions = [otherMember]
        let xpBefore = f.data.profile.totalXP
        await f.data.uncompleteTask(otherMember)
        XCTAssertEqual(f.data.completions.map(\.id), [otherMember.id])
        XCTAssertEqual(f.data.profile.totalXP, xpBefore)
    }
}
