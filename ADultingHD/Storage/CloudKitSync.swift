import Foundation
import CloudKit
import os
#if os(macOS)
import Security
#endif

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "CloudKitSync")

private let sharedJSONEncoder = JSONEncoder()
private let sharedJSONDecoder = JSONDecoder()

// MARK: - CloudKit record type names

enum RecordType {
    static let task       = "HouseholdTask"
    static let personalTaskTombstone = "PersonalTaskTombstone"
    static let completion = "TaskCompletion"
    static let profile    = "MemberProfile"
    /// Root record for the shared household zone. CKShare needs a concrete
    /// root record to hang off of; this is that placeholder. Record type
    /// names must NOT start with `_` — those are reserved by CloudKit and
    /// saving one will fail.
    static let householdRoot = "HouseholdRoot"
}

private enum RootRecordName {
    static let household = "household-root"
}

enum ZoneName {
    /// The pre-multi-household zone retained only for migrating existing users.
    static let household = "HouseholdZone"

    /// CloudKit zones are the sharing boundary, so every new local household
    /// must have an identity that cannot collide with a prior share.
    static func uniqueHousehold(for id: UUID) -> String {
        "Household-\(id.uuidString)"
    }
}

// MARK: - CloudKitSync

/// Manages CloudKit sharing for households. Each `Household` maps to a single
/// custom `CKRecordZone`. When `ownerIsCurrentUser` is true the zone lives in
/// the user's `privateCloudDatabase`; when false, it lives in `sharedCloudDatabase`
/// owned by the inviter. All push/pull/share APIs take a `Household` so a
/// single device with multiple households (some owned, some joined) routes
/// each operation to the correct zone + database.
@MainActor
final class CloudKitSync: ObservableObject {

    static let shared = CloudKitSync()
    nonisolated static let containerIdentifier = CloudConfig.containerID

    @Published var isAvailable = false
    @Published var syncError: String?

    // Lazy so the CKContainer is only constructed when CloudKit is actually used.
    // CKContainer(identifier:) traps when the iCloud entitlement is missing
    // (e.g. unsigned builds for tests with CODE_SIGNING_ALLOWED=NO), so eager
    // construction would crash the host app at launch during test runs even
    // though all real CloudKit code paths are gated behind isHouseholdSharingEnabled.
    private lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    /// Expose the container so SwiftUI share-sheet wrappers (UICloudSharingController)
    /// can be constructed. Safe to read only after setup() has marked `isAvailable`.
    var cloudContainer: CKContainer { container }

    /// In-memory dedupe of zoneNames whose subscription was saved this
    /// session, so repeated `setupSubscriptions(for:)` calls don't keep
    /// hitting `fetchAllSubscriptions`. Cleared on relaunch — the underlying
    /// CloudKit subscription persists server-side.
    private var configuredSubscriptionZones: Set<String> = []

    private init() {}

    // MARK: - Setup

    func setup() async {
        guard Self.runtimeSupportsCloudKit else {
            isAvailable = false
            syncError = "This installation is not signed for household sharing."
            return
        }
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                logger.info("☁️ iCloud not available: \(String(describing: status), privacy: .private)")
                syncError = "iCloud account status: \(status)"
                isAvailable = false
                return
            }
            isAvailable = true
            syncError = nil
            logger.info("☁️ CloudKit ready")
        } catch {
            logger.error("☁️ CloudKit setup failed: \(error.localizedDescription, privacy: .private)")
            syncError = error.localizedDescription
            isAvailable = false
        }
    }

    /// SecTask is public on macOS only. The generated signing flag rejects
    /// unsigned iOS builds before CKContainer can trap; deploy.sh validates
    /// actual release entitlements after signing. CloudKit integration tests
    /// additionally require an explicit opt-in and a signed host.
    nonisolated static var runtimeSupportsCloudKit: Bool {
        guard signingExpected(Bundle.main.object(forInfoDictionaryKey: "CloudKitSigningExpected")) else { return false }
        let environment = ProcessInfo.processInfo.environment
        let runningTests = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
        guard !runningTests || environment["CLOUDKIT_INTEGRATION_TESTS"] == "1" else { return false }
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String]
        let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String]
        return permitsCloudKit(services: services, containers: containers)
        #else
        return true
        #endif
    }

    nonisolated static func signingExpected(_ value: Any?) -> Bool {
        (value as? String)?.uppercased() == "YES" || (value as? Bool) == true
    }

    nonisolated static func permitsCloudKit(services: [String]?, containers: [String]?) -> Bool {
        services?.contains("CloudKit") == true && containers?.contains(containerIdentifier) == true
    }

    nonisolated static func validateContainerIdentifier(_ identifier: String) throws {
        guard identifier == containerIdentifier else { throw CloudKitSyncError.invalidShareContainer }
    }

    nonisolated static func subscriptionID(for household: Household) -> String {
        if household.ownerIsCurrentUser {
            return "household-private-zone-\(household.zoneName)"
        }
        // A database subscription covers every owner's zones. CloudKit does
        // not permit zone subscriptions in the shared database.
        return "household-shared-database-changes"
    }

    /// Ensure the household's zone exists in `privateCloudDatabase`. No-op
    /// for joined households — CloudKit auto-mirrors the owner's zone into
    /// our `sharedCloudDatabase` when the share is accepted.
    private func ensureOwnedZoneExists(for household: Household) async throws {
        guard household.ownerIsCurrentUser else { return }
        let zones = try await privateDB.allRecordZones()
        if zones.contains(where: { $0.zoneID.zoneName == household.zoneName }) { return }
        _ = try await privateDB.save(CKRecordZone(zoneName: household.zoneName))
        logger.info("☁️ Created zone \(household.zoneName, privacy: .private)")
    }

    func setupSubscriptions(for household: Household) async {
        guard isAvailable else { return }
        let subscriptionID = Self.subscriptionID(for: household)
        guard !configuredSubscriptionZones.contains(subscriptionID) else { return }
        do {
            let db = database(for: household)
            let zoneID = zoneID(for: household)
            let existing = try await db.fetchAllSubscriptions()
            if !existing.contains(where: { $0.subscriptionID == subscriptionID }) {
                let sub: CKSubscription = household.ownerIsCurrentUser
                    ? CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)
                    : CKDatabaseSubscription(subscriptionID: subscriptionID)
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                sub.notificationInfo = info
                _ = try await db.saveSubscription(sub)
                logger.info("☁️ CloudKit change subscription registered")
            }
            configuredSubscriptionZones.insert(subscriptionID)
        } catch {
            logger.error("☁️ Subscription setup failed: \(error.localizedDescription)")
        }
    }

    /// Permanently removes a household's CloudKit data before its local row is
    /// deleted. Owners delete the private zone, which also removes its share
    /// and revokes every participant. Joined users delete their share record
    /// from the shared database, which leaves the owner's household intact.
    func removeHouseholdCloudData(for household: Household) async throws {
        guard isAvailable else {
            throw CloudKitSyncError.iCloudUnavailable(status: syncError ?? "unknown")
        }

        do {
            if household.ownerIsCurrentUser {
                let zones = try await privateDB.allRecordZones()
                let exists = zones.contains { $0.zoneID.zoneName == household.zoneName }
                if exists {
                    do {
                        try await privateDB.deleteZone(withID: zoneID(for: household))
                        logger.info("☁️ Deleted household zone \(household.zoneName, privacy: .private) and revoked participants")
                    } catch {
                        // A second device may have completed the deletion
                        // after the zone list was fetched. Treat that race as
                        // already-cleaned data so local deletion can finish.
                        if !isMissingCloudKitObject(error) { throw error }
                    }
                }
            } else {
                let rootID = rootRecordID(for: household)
                do {
                    let root = try await sharedDB.record(for: rootID)
                    if let shareReference = root.share {
                        _ = try await sharedDB.modifyRecords(saving: [], deleting: [shareReference.recordID])
                        logger.info("☁️ Left shared household zone \(household.zoneName, privacy: .private)")
                    }
                } catch {
                    // A zone already removed by its owner is already cleaned
                    // up from this participant's point of view.
                    if !isMissingCloudKitObject(error) { throw error }
                }
            }
            configuredSubscriptionZones.remove(Self.subscriptionID(for: household))
        } catch let error as CloudKitSyncError {
            throw error
        } catch {
            throw CloudKitSyncError.householdCleanupFailed(underlying: error)
        }
    }

    /// Read-only check for whether an owned household already has a live
    /// CKShare, without creating one. `createOrFetchShare` can't be reused
    /// for this — its first-time-setup path creates the zone/root/share on
    /// demand, which would silently start sharing a household that was
    /// never actually shared. Needed because builds before this feature
    /// never persisted `Household.shareRecordName`, so an owned household
    /// shared under an older build can still show it as `nil`.
    func hasExistingShare(for household: Household) async throws -> Bool {
        guard isAvailable else {
            throw CloudKitSyncError.iCloudUnavailable(status: syncError ?? "unknown")
        }
        guard household.ownerIsCurrentUser else { return false }
        let zones = try await privateDB.allRecordZones()
        guard zones.contains(where: { $0.zoneID.zoneName == household.zoneName }) else { return false }
        do {
            let root = try await privateDB.record(for: rootRecordID(for: household))
            return root.share != nil
        } catch {
            // A genuinely missing root proves there is no live share. Every
            // other CloudKit error is inconclusive and must propagate so
            // callers that may delete local data can fail closed.
            guard isMissingCloudKitObject(error) else { throw error }
            return false
        }
    }

    // MARK: - Push (local → CloudKit)

    @discardableResult
    func pushTasks(
        _ tasks: [HouseholdTask],
        personalTaskIDs: Set<UUID> = [],
        deletingPersonalTaskIDs: Set<UUID> = [],
        personalCompletionCleanupHouseholds: [Household] = [],
        household: Household
    ) async -> Bool {
        guard isAvailable else { return false }
        let zoneID = zoneID(for: household)
        let rootID = rootRecordID(for: household)
        let db = database(for: household)
        let personalIDs = personalTaskIDs.union(tasks.filter(\.isPersonal).map(\.id))
        let sharedTasks = tasks.filter { !$0.isPersonal && !personalIDs.contains($0.id) }
        let records = sharedTasks.map { $0.toCKRecord(zoneID: zoneID, parentRecordID: rootID) }
            + personalIDs.map {
                PersonalTaskTombstone(taskID: $0).toCKRecord(zoneID: zoneID, parentRecordID: rootID)
            }
        let taskRecordNames = Set(personalIDs.map(\.uuidString))
        let releasedTaskRecordNames = Set(deletingPersonalTaskIDs.map(\.uuidString))
        let releasedTombstoneRecordNames = Set(deletingPersonalTaskIDs.map {
            PersonalTaskTombstone.recordID(for: $0, zoneID: zoneID).recordName
        })
        let taskIDsToDelete: Set<CKRecord.ID>
        let releasedTaskIDsToDelete: Set<CKRecord.ID>
        let completionIDsToDelete: Set<CKRecord.ID>
        let releasedTombstoneIDs: Set<CKRecord.ID>
        do {
            taskIDsToDelete = try await existingRecordIDs(
                ofType: RecordType.task,
                recordNames: taskRecordNames,
                from: db,
                zoneID: zoneID
            )
            releasedTaskIDsToDelete = try await existingRecordIDs(
                ofType: RecordType.task,
                recordNames: releasedTaskRecordNames,
                from: db,
                zoneID: zoneID
            )
            completionIDsToDelete = Set(try await remoteCompletionIDs(for: personalIDs, from: db, zoneID: zoneID))
            releasedTombstoneIDs = try await existingRecordIDs(
                ofType: RecordType.personalTaskTombstone,
                recordNames: releasedTombstoneRecordNames,
                from: db,
                zoneID: zoneID
            )
        } catch {
            logger.error("☁️ Could not enumerate personal cleanup records: \(error.localizedDescription)")
            syncError = error.localizedDescription
            return false
        }
        // A previously personal task record may still carry `isPersonal = 1`.
        // Delete that record before saving the household-scoped replacement;
        // omitting the field with `.changedKeys` does not clear it remotely.
        guard await saveRecords([], deleting: Array(releasedTaskIDsToDelete), in: db) else { return false }
        let saved = await saveRecords(
            records,
            deleting: Array(taskIDsToDelete)
                + Array(completionIDsToDelete)
                + Array(releasedTombstoneIDs),
            in: db
        )
        guard saved else { return false }
        return await purgePersonalCompletions(
            for: personalIDs,
            from: personalCompletionCleanupHouseholds,
            excluding: household
        )
    }

    func pushProfile(_ profile: UserProfile, household: Household) async {
        guard isAvailable else { return }
        let record = profile.toCKRecord(zoneID: zoneID(for: household), parentRecordID: rootRecordID(for: household))
        _ = await saveRecords([record], in: database(for: household))
    }

    func pushCompletion(_ completion: TaskCompletion, household: Household) async {
        guard isAvailable else { return }
        let record = completion.toCKRecord(zoneID: zoneID(for: household), parentRecordID: rootRecordID(for: household))
        _ = await saveRecords([record], in: database(for: household))
    }

    /// Upload every record a newly invited participant needs before the share
    /// sheet is presented. Unlike ordinary best-effort sync, this path is
    /// fail-closed: every per-record result must succeed or invite preparation
    /// throws and the user can retry without sending an incomplete household.
    func uploadInitialShareSnapshot(
        tasks: [HouseholdTask],
        profile: UserProfile,
        completions: [TaskCompletion],
        members _: [UserProfile],
        personalTaskIDs: Set<UUID> = [],
        deletingPersonalTaskIDs: Set<UUID> = [],
        personalCompletionCleanupHouseholds: [Household] = [],
        household: Household
    ) async throws {
        guard isAvailable else {
            throw CloudKitSyncError.iCloudUnavailable(status: syncError ?? "unknown")
        }

        let zoneID = zoneID(for: household)
        let rootID = rootRecordID(for: household)
        let db = database(for: household)
        // Personal tasks stay in the owner's local workspace and are not part
        // of the household snapshot presented to a new participant.
        let personalIDs = personalTaskIDs.union(tasks.filter(\.isPersonal).map(\.id))
        let sharedTasks = tasks.filter { !$0.isPersonal && !personalIDs.contains($0.id) }
        let sharedCompletions = completions.filter { !personalIDs.contains($0.taskId) }
        let records = sharedTasks.map { $0.toCKRecord(zoneID: zoneID, parentRecordID: rootID) }
            + personalIDs.map {
                PersonalTaskTombstone(taskID: $0).toCKRecord(zoneID: zoneID, parentRecordID: rootID)
            }
            + sharedCompletions.map { $0.toCKRecord(zoneID: zoneID, parentRecordID: rootID) }
            // Other members' cached profiles may be stale. Only their own
            // devices can authoritatively publish their profile changes.
            + [profile.toCKRecord(zoneID: zoneID, parentRecordID: rootID)]

        let taskRecordNames = Set(personalIDs.map(\.uuidString))
        let releasedTaskRecordNames = Set(deletingPersonalTaskIDs.map(\.uuidString))
        let releasedTombstoneRecordNames = Set(deletingPersonalTaskIDs.map {
            PersonalTaskTombstone.recordID(for: $0, zoneID: zoneID).recordName
        })
        let taskIDsToDelete: Set<CKRecord.ID>
        let releasedTaskIDsToDelete: Set<CKRecord.ID>
        let completionIDsToDelete: Set<CKRecord.ID>
        let releasedTombstoneIDs: Set<CKRecord.ID>
        do {
            taskIDsToDelete = try await existingRecordIDs(
                ofType: RecordType.task,
                recordNames: taskRecordNames,
                from: db,
                zoneID: zoneID
            )
            releasedTaskIDsToDelete = try await existingRecordIDs(
                ofType: RecordType.task,
                recordNames: releasedTaskRecordNames,
                from: db,
                zoneID: zoneID
            )
            completionIDsToDelete = Set(try await remoteCompletionIDs(for: personalIDs, from: db, zoneID: zoneID))
            releasedTombstoneIDs = try await existingRecordIDs(
                ofType: RecordType.personalTaskTombstone,
                recordNames: releasedTombstoneRecordNames,
                from: db,
                zoneID: zoneID
            )
        } catch {
            throw CloudKitSyncError.shareCreationFailed(
                detail: "could not enumerate personal cleanup records: \(error.localizedDescription)"
            )
        }
        // Recreate released records so a legacy `isPersonal = 1` field cannot
        // survive a `.changedKeys` update that omits the field.
        try await saveRequiredRecords([], deleting: Array(releasedTaskIDsToDelete), in: db)
        let recordsToDelete = Array(taskIDsToDelete)
            + Array(completionIDsToDelete)
            + Array(releasedTombstoneIDs)

        // Keep the combined save + delete count within CloudKit's operation
        // limit while retaining exact per-record validation for every batch.
        let batchLimit = 200
        var saveOffset = 0
        var deleteOffset = 0
        while saveOffset < records.count || deleteOffset < recordsToDelete.count {
            let deletesInBatch = min(batchLimit, recordsToDelete.count - deleteOffset)
            let savesInBatch = min(
                batchLimit - deletesInBatch,
                records.count - saveOffset
            )
            let saves = Array(records[saveOffset..<(saveOffset + savesInBatch)])
            let deletes = Array(recordsToDelete[deleteOffset..<(deleteOffset + deletesInBatch)])
            try await saveRequiredRecords(saves, deleting: deletes, in: db)
            saveOffset += savesInBatch
            deleteOffset += deletesInBatch
        }
        guard await purgePersonalCompletions(
            for: personalIDs,
            from: personalCompletionCleanupHouseholds,
            excluding: household
        ) else {
            throw CloudKitSyncError.shareCreationFailed(
                detail: "could not purge personal completions from every household zone"
            )
        }
        logger.info("☁️ Initial share snapshot uploaded: \(records.count) records")
    }

    private func saveRecords(_ records: [CKRecord], deleting recordIDs: [CKRecord.ID] = [], in db: CKDatabase) async -> Bool {
        guard !records.isEmpty || !recordIDs.isEmpty else { return true }
        let batchLimit = 200
        var saveOffset = 0
        var deleteOffset = 0

        while saveOffset < records.count || deleteOffset < recordIDs.count {
            let deletesInBatch = min(batchLimit, recordIDs.count - deleteOffset)
            let savesInBatch = min(
                batchLimit - deletesInBatch,
                records.count - saveOffset
            )
            let saves = Array(records[saveOffset..<(saveOffset + savesInBatch)])
            let deletes = Array(recordIDs[deleteOffset..<(deleteOffset + deletesInBatch)])
            var failures: [String] = []
            do {
                let results = try await db.modifyRecords(
                    saving: saves,
                    deleting: deletes,
                    savePolicy: .changedKeys,
                    atomically: false
                )
                let batchFailures = recordFailureDetails(
                    saving: saves,
                    deleting: deletes,
                    saveResults: results.saveResults,
                    deleteResults: results.deleteResults
                )
                if batchFailures.contains(where: containsAtomicFailure) {
                    failures = await retryRecordsIndividually(
                        saving: saves,
                        deleting: deletes,
                        savePolicy: .changedKeys,
                        in: db
                    )
                } else {
                    failures = batchFailures
                }
            } catch {
                if isAtomicCloudKitFailure(error) {
                    logger.error(
                        "☁️ Atomic batch failure; retrying \(saves.count) saves and \(deletes.count) deletes individually"
                    )
                    failures = await retryRecordsIndividually(
                        saving: saves,
                        deleting: deletes,
                        savePolicy: .changedKeys,
                        in: db
                    )
                } else {
                    let details = cloudKitErrorDetails(error)
                    logger.error("☁️ Push failed: \(details)")
                    syncError = details
                    return false
                }
            }
            guard failures.isEmpty else {
                let detail = "CloudKit task sync failed: \(failures.joined(separator: " | "))"
                logger.error("☁️ Push failed: \(detail)")
                syncError = detail
                return false
            }
            saveOffset += savesInBatch
            deleteOffset += deletesInBatch
        }

        if recordIDs.isEmpty {
            logger.info("☁️ Pushed \(records.count) records")
        } else {
            logger.info("☁️ Pushed \(records.count) records and removed \(recordIDs.count) personal-scope records")
        }
        return true
    }

    private func saveRequiredRecords(
        _ records: [CKRecord],
        deleting recordIDs: [CKRecord.ID] = [],
        in db: CKDatabase
    ) async throws {
        guard !records.isEmpty || !recordIDs.isEmpty else { return }
        var failures: [String] = []
        do {
            let results = try await db.modifyRecords(
                saving: records,
                deleting: recordIDs,
                savePolicy: .allKeys,
                atomically: false
            )
            let batchFailures = recordFailureDetails(
                saving: records,
                deleting: recordIDs,
                saveResults: results.saveResults,
                deleteResults: results.deleteResults
            )
            if batchFailures.contains(where: containsAtomicFailure) {
                logger.error(
                    "☁️ Atomic initial-upload failure; retrying \(records.count) saves and \(recordIDs.count) deletes individually"
                )
                failures = await retryRecordsIndividually(
                    saving: records,
                    deleting: recordIDs,
                    savePolicy: .allKeys,
                    in: db
                )
            } else {
                failures = batchFailures
            }
        } catch {
            if isAtomicCloudKitFailure(error) {
                logger.error(
                    "☁️ Atomic initial-upload failure; retrying \(records.count) saves and \(recordIDs.count) deletes individually"
                )
                failures = await retryRecordsIndividually(
                    saving: records,
                    deleting: recordIDs,
                    savePolicy: .allKeys,
                    in: db
                )
            } else {
                let details = cloudKitErrorDetails(error)
                syncError = details
                throw CloudKitSyncError.shareCreationFailed(
                    detail: "initial household upload failed: \(details)"
                )
            }
        }
        guard failures.isEmpty else {
            let detail = "initial household upload failed: \(failures.joined(separator: " | "))"
            syncError = detail
            throw CloudKitSyncError.shareCreationFailed(detail: detail)
        }
        logger.info("☁️ Pushed required batch of \(records.count) records")
    }

    /// CloudKit custom-zone writes are atomic even when `atomically` is false.
    /// A single invalid record therefore makes the other records report only
    /// `batchRequestFailed` (localized as "Atomic failure"). Retry each item
    /// on its own so the server returns the actual rejected field.
    private func retryRecordsIndividually(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        in db: CKDatabase
    ) async -> [String] {
        var failures: [String] = []
        for record in records {
            do {
                let results = try await db.modifyRecords(
                    saving: [record],
                    deleting: [],
                    savePolicy: savePolicy,
                    atomically: false
                )
                failures.append(contentsOf: recordFailureDetails(
                    saving: [record],
                    deleting: [],
                    saveResults: results.saveResults,
                    deleteResults: results.deleteResults
                ))
            } catch {
                failures.append("save \(record.recordID.recordName): \(cloudKitErrorDetails(error))")
            }
        }
        for recordID in recordIDs {
            do {
                let results = try await db.modifyRecords(
                    saving: [],
                    deleting: [recordID],
                    savePolicy: savePolicy,
                    atomically: false
                )
                failures.append(contentsOf: recordFailureDetails(
                    saving: [],
                    deleting: [recordID],
                    saveResults: results.saveResults,
                    deleteResults: results.deleteResults
                ))
            } catch {
                failures.append("delete \(recordID.recordName): \(cloudKitErrorDetails(error))")
            }
        }
        return failures
    }

    private func recordFailureDetails(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        saveResults: [CKRecord.ID: Result<CKRecord, Error>],
        deleteResults: [CKRecord.ID: Result<Void, Error>]
    ) -> [String] {
        var failures: [String] = []
        for record in records {
            guard let result = saveResults[record.recordID] else {
                failures.append("save \(record.recordID.recordName): no result returned")
                continue
            }
            if case .failure(let error) = result {
                failures.append("save \(record.recordID.recordName): \(cloudKitErrorDetails(error))")
            }
        }
        for recordID in recordIDs {
            guard let result = deleteResults[recordID] else {
                failures.append("delete \(recordID.recordName): no result returned")
                continue
            }
            if case .failure(let error) = result {
                failures.append("delete \(recordID.recordName): \(cloudKitErrorDetails(error))")
            }
        }
        return failures
    }

    /// `CKError.batchRequestFailed` is the per-item representation of an
    /// atomic custom-zone failure. Keep the localized-string check as a
    /// compatibility fallback for older OS releases that surface only the
    /// server's "Atomic failure" text.
    private func isAtomicCloudKitFailure(_ error: Error) -> Bool {
        if let cloudKitError = error as? CKError {
            if cloudKitError.code == .partialFailure || cloudKitError.code == .batchRequestFailed {
                return true
            }
            if cloudKitError.partialErrorsByItemID?.values.contains(where: { nestedError in
                if let nestedCloudKitError = nestedError as? CKError {
                    return nestedCloudKitError.code == .partialFailure
                        || nestedCloudKitError.code == .batchRequestFailed
                }
                return containsAtomicFailure(nestedError.localizedDescription)
            }) == true {
                return true
            }
        }
        return containsAtomicFailure(error.localizedDescription)
    }

    private func containsAtomicFailure(_ details: String) -> Bool {
        details.localizedCaseInsensitiveContains("atomic failure")
            || details.localizedCaseInsensitiveContains("batch request failed")
    }

    /// Preserve CloudKit's nested per-item errors instead of reducing a
    /// partial failure to its unhelpful top-level "Atomic failure" text.
    private func cloudKitErrorDetails(_ error: Error) -> String {
        guard let cloudKitError = error as? CKError,
              let partialErrors = cloudKitError.partialErrorsByItemID,
              !partialErrors.isEmpty else {
            return error.localizedDescription
        }

        let itemDetails = partialErrors.map { key, itemError in
            let recordName = (key as? CKRecord.ID)?.recordName ?? String(describing: key)
            return "\(recordName): \(itemError.localizedDescription)"
        }
        .sorted()
        .joined(separator: " | ")
        return "\(error.localizedDescription) [\(itemDetails)]"
    }

    // MARK: - Pull (CloudKit → local)

    func pullAll(for household: Household) async -> CloudKitPayload? {
        try? await pullAllRequired(for: household)
    }

    func pullAllRequired(for household: Household) async throws -> CloudKitPayload {
        guard isAvailable else {
            throw CloudKitSyncError.iCloudUnavailable(status: syncError ?? "unknown")
        }
        let db = database(for: household)
        let zoneID = zoneID(for: household)
        do {
            async let tasks       = fetchRecords(ofType: RecordType.task,       from: db, zoneID: zoneID)
            async let personalTaskTombstones = fetchRecords(ofType: RecordType.personalTaskTombstone, from: db, zoneID: zoneID)
            async let completions = fetchRecords(ofType: RecordType.completion, from: db, zoneID: zoneID)
            async let profileRecords = fetchRecords(ofType: RecordType.profile, from: db, zoneID: zoneID)

            let (t, tombstones, c, p) = try await (tasks, personalTaskTombstones, completions, profileRecords)
            let personalTaskIDs = Set(tombstones.compactMap(PersonalTaskTombstone.taskID(from:)))
                .union(t.compactMap { task in
                    guard (task["isPersonal"] as? Int ?? 0) == 1 else { return nil }
                    return UUID(uuidString: task.recordID.recordName)
                })
            let decodedProfiles = p.compactMap { UserProfile(from: $0) }
            let inviterName = household.ownerUserRecordName.flatMap { ownerRecordName in
                p.lazy
                    .filter { $0.creatorUserRecordID?.recordName == ownerRecordName }
                    .compactMap { UserProfile(from: $0)?.name.trimmedNilIfEmpty }
                    .first
            }
            let payload = CloudKitPayload(
                tasks:       t.compactMap { HouseholdTask(from: $0) },
                completions: c.compactMap { TaskCompletion(from: $0) },
                profiles:    decodedProfiles,
                inviterName: inviterName,
                personalTaskIDs: personalTaskIDs
            )
            logger.info("☁️ Pulled \(payload.tasks.count) tasks, \(payload.completions.count) completions, \(payload.profiles.count) profiles and \(payload.personalTaskIDs.count) personal task markers from \(household.zoneName, privacy: .private)")
            return payload
        } catch {
            logger.error("☁️ Pull failed: \(error.localizedDescription)")
            syncError = error.localizedDescription
            throw error
        }
    }

    private func fetchRecords(ofType type: String, from db: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        var results: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil

        repeat {
            let op: CKQueryOperation = cursor.map(CKQueryOperation.init) ?? CKQueryOperation(query: query)
            op.zoneID = zoneID
            op.resultsLimit = CKQueryOperation.maximumResults
            let (records, nextCursor) = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<([CKRecord], CKQueryOperation.Cursor?), Error>) in
                var batch: [CKRecord] = []
                var recordFailure: Error?
                op.recordMatchedBlock = { _, result in
                    switch result {
                    case .success(let record): batch.append(record)
                    case .failure(let error): recordFailure = recordFailure ?? error
                    }
                }
                op.queryResultBlock = { result in
                    switch result {
                    case .success(let c):
                        if let recordFailure { cont.resume(throwing: recordFailure) }
                        else { cont.resume(returning: (batch, c)) }
                    case .failure(let e): cont.resume(throwing: e)
                    }
                }
                db.add(op)
            }
            results.append(contentsOf: records)
            cursor = nextCursor
        } while cursor != nil

        return results
    }

    /// Completion records are copied into whichever household zone was active
    /// when a save occurred. When a task becomes personal, enumerate every
    /// known zone so old copies cannot remain visible to collaborators in a
    /// different household.
    private func purgePersonalCompletions(
        for personalTaskIDs: Set<UUID>,
        from households: [Household],
        excluding excludedHousehold: Household
    ) async -> Bool {
        guard !personalTaskIDs.isEmpty else { return true }

        let excludedZoneKey = zoneKey(for: excludedHousehold)
        var seenZoneKeys: Set<String> = []
        var succeeded = true
        for household in households {
            // An owned household without a share has no custom zone to query;
            // restricting the sweep avoids turning every ordinary local
            // household into a needless zone-not-found request.
            guard household.shareRecordName != nil || !household.ownerIsCurrentUser else { continue }
            let key = zoneKey(for: household)
            guard key != excludedZoneKey, seenZoneKeys.insert(key).inserted else { continue }

            let db = database(for: household)
            let zoneID = zoneID(for: household)
            do {
                let completionIDs = try await remoteCompletionIDs(
                    for: personalTaskIDs,
                    from: db,
                    zoneID: zoneID
                )
                guard !completionIDs.isEmpty else { continue }
                if !(await saveRecords([], deleting: completionIDs, in: db)) {
                    succeeded = false
                }
            } catch {
                if isMissingCloudKitObject(error) { continue }
                logger.error("☁️ Could not purge personal completions from \(household.zoneName, privacy: .private): \(error.localizedDescription)")
                syncError = error.localizedDescription
                succeeded = false
            }
        }
        return succeeded
    }

    private func remoteCompletionIDs(
        for personalTaskIDs: Set<UUID>,
        from db: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> [CKRecord.ID] {
        guard !personalTaskIDs.isEmpty else { return [] }
        let records = try await fetchRecords(ofType: RecordType.completion, from: db, zoneID: zoneID)
        return records.compactMap { record in
            guard let taskID = (record["taskId"] as? String).flatMap(UUID.init),
                  personalTaskIDs.contains(taskID) else { return nil }
            return record.recordID
        }
    }

    private func existingRecordIDs(
        ofType type: String,
        recordNames: Set<String>,
        from db: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> Set<CKRecord.ID> {
        guard !recordNames.isEmpty else { return [] }
        let records = try await fetchRecords(ofType: type, from: db, zoneID: zoneID)
        return Set(records.compactMap { record in
            recordNames.contains(record.recordID.recordName) ? record.recordID : nil
        })
    }

    // MARK: - Sharing (household invite)

    /// Returns a CKShare for the household's root record, creating one the
    /// first time and reusing it thereafter. Root record and share are
    /// always saved together — CloudKit requires both in the same operation.
    /// Only valid for households where `ownerIsCurrentUser == true`.
    func createOrFetchShare(for household: Household) async throws -> CKShare {
        guard isAvailable else {
            logger.error("☁️ createOrFetchShare called but isAvailable=false")
            throw CloudKitSyncError.iCloudUnavailable(status: syncError ?? "unknown")
        }
        guard household.ownerIsCurrentUser else {
            throw CloudKitSyncError.shareCreationFailed(detail: "cannot share a household joined from someone else")
        }

        try await ensureOwnedZoneExists(for: household)

        let zone = CKRecordZone(zoneName: household.zoneName)
        let rootID = CKRecord.ID(recordName: RootRecordName.household, zoneID: zone.zoneID)
        logger.info("☁️ createOrFetchShare zone=\(household.zoneName, privacy: .private) rootID=\(rootID.recordName, privacy: .private)")

        // If the root already exists, it carries a reference to its share.
        // Pull the share through that reference rather than guessing IDs.
        if let existingRoot = try? await privateDB.record(for: rootID) {
            logger.info("☁️ Root record already exists")
            if let shareReference = existingRoot.share {
                if let existingShare = try? await privateDB.record(for: shareReference.recordID) as? CKShare {
                    let existingTitle = existingShare[CKShare.SystemFieldKey.title] as? String
                    if existingTitle != household.name {
                        existingShare[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
                        let updatedShare = try await privateDB.save(existingShare)
                        guard let updatedShare = updatedShare as? CKShare else {
                            throw CloudKitSyncError.shareCreationFailed(detail: "updated share had an unexpected record type")
                        }
                        logger.info("☁️ Reusing household share with refreshed title")
                        return updatedShare
                    }
                    logger.info("☁️ Reusing household share")
                    return existingShare
                }
                logger.error("☁️ Root has share reference but fetching share failed")
            } else {
                logger.error("☁️ Root exists but has no share reference — prior partial save")
            }
        }

        // First-time setup: create the root record and its share atomically.
        let rootRecord = CKRecord(recordType: RecordType.householdRoot, recordID: rootID)
        rootRecord["title"] = household.name as CKRecordValue

        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
        share.publicPermission = .none
        logger.info("☁️ Saving root + share atomically (share.recordID=\(share.recordID.recordName, privacy: .private))")

        // Use Apple's native async API directly — it returns per-record
        // Result values so we can surface the individual server error for
        // whichever record (root or share) fails. Our custom wrapper was
        // collapsing failures into a silent empty-success.
        let saveResults: [CKRecord.ID: Result<CKRecord, Error>]
        do {
            let results = try await privateDB.modifyRecords(
                saving: [rootRecord, share],
                deleting: [],
                savePolicy: .allKeys,      // new CKShare needs allKeys, not changedKeys
                atomically: true           // both-or-nothing, matches CloudKit's share rules
            )
            saveResults = results.saveResults
        } catch {
            let details = cloudKitErrorDetails(error)
            logger.error("☁️ modifyRecords top-level threw: \(details, privacy: .private)")
            logger.error("☁️ underlying: \(String(describing: error), privacy: .private)")
            throw CloudKitSyncError.shareCreationFailed(detail: details)
        }

        // Log every per-record result so we can see which one failed and why.
        var savedRecords: [CKRecord] = []
        var failures: [String] = []
        for (recordID, result) in saveResults {
            switch result {
            case .success(let record):
                savedRecords.append(record)
                logger.info("☁️ saved \(record.recordType, privacy: .private) id=\(recordID.recordName, privacy: .private)")
            case .failure(let error):
                let msg = "\(recordID.recordName): \(cloudKitErrorDetails(error))"
                failures.append(msg)
                logger.error("☁️ save failed for \(msg, privacy: .private) — \(String(describing: error), privacy: .private)")
            }
        }

        guard let savedShare = savedRecords.compactMap({ $0 as? CKShare }).first else {
            let typeList = savedRecords.map(\.recordType).joined(separator: ",")
            let failureList = failures.isEmpty ? "no per-record failures reported" : failures.joined(separator: " | ")
            throw CloudKitSyncError.shareCreationFailed(
                detail: "saved=[\(typeList)] failures=[\(failureList)]"
            )
        }
        logger.info("☁️ Created household share")
        return savedShare
    }

    /// Accept a CKShare invite. Returns the data needed to register a new
    /// joined household locally — caller is responsible for inserting the
    /// row into `householdIndex` (this layer doesn't know about it). The
    /// metadata's `share.recordID.zoneID` carries both the zoneName and the
    /// inviter's user record name, which together identify the shared zone
    /// against `sharedCloudDatabase` across app restarts.
    func acceptShare(from metadata: CKShare.Metadata) async throws -> HouseholdShareInfo {
        try Self.validateContainerIdentifier(metadata.containerIdentifier)
        guard isAvailable else {
            throw CloudKitSyncError.iCloudUnavailable(status: syncError ?? "unknown")
        }
        try await container.accept(metadata)
        let info = shareInfo(from: metadata)
        logger.info("☁️ Accepted household share")
        return info
    }

    func fetchShareMetadata(from url: URL) async throws -> CKShare.Metadata {
        guard let url = ShareAcceptance.validatedURL(url) else { throw CloudKitSyncError.invalidShareURL }
        await setup()
        guard isAvailable else {
            throw CloudKitSyncError.iCloudUnavailable(status: syncError ?? "unknown")
        }
        let metadata = try await container.shareMetadata(for: url)
        try Self.validateContainerIdentifier(metadata.containerIdentifier)
        return metadata
    }

    /// Read the household and owner identity embedded in share metadata
    /// without accepting it. First-launch onboarding uses this preview so a
    /// recipient can choose to create their own household before this app
    /// commits their CloudKit participation.
    func shareInfo(from metadata: CKShare.Metadata) -> HouseholdShareInfo {
        let zoneID = metadata.share.recordID.zoneID
        // CKShare title is set when the owner created the share. Fallback to
        // a generic name when missing — the joiner can rename later.
        let title = (metadata.share[CKShare.SystemFieldKey.title] as? String)?.nilIfEmpty
            ?? "Shared Household"
        let inviterName = metadata.ownerIdentity.nameComponents
            .map { PersonNameComponentsFormatter().string(from: $0) }
            .flatMap(\.trimmedNilIfEmpty)
        return HouseholdShareInfo(
            shareRecordName: metadata.share.recordID.recordName,
            zoneName: zoneID.zoneName,
            ownerUserRecordName: zoneID.ownerName,
            title: title,
            inviterName: inviterName
        )
    }

    // MARK: - Helpers

    private func zoneKey(for household: Household) -> String {
        let zoneID = zoneID(for: household)
        return "\(zoneID.ownerName)|\(zoneID.zoneName)"
    }

    private func database(for household: Household) -> CKDatabase {
        switch household.ownership {
        case .owned: privateDB
        case .joined: sharedDB
        }
    }

    /// Joined households embed the inviter's user record name so the zone
    /// resolves correctly in `sharedCloudDatabase`.
    private func zoneID(for household: Household) -> CKRecordZone.ID {
        switch household.ownership {
        case .owned:
            return CKRecordZone.ID(zoneName: household.zoneName)
        case .joined(let ownerUserRecordName, _):
            return CKRecordZone.ID(zoneName: household.zoneName, ownerName: ownerUserRecordName)
        }
    }

    /// The record itself is created lazily by `createOrFetchShare` — push
    /// records may dangle until then, which is fine.
    private func rootRecordID(for household: Household) -> CKRecord.ID {
        CKRecord.ID(recordName: RootRecordName.household, zoneID: zoneID(for: household))
    }

    private func isMissingCloudKitObject(_ error: Error) -> Bool {
        guard let cloudKitError = error as? CKError else { return false }
        return cloudKitError.code == .unknownItem || cloudKitError.code == .zoneNotFound
    }
}

/// Returned by `CloudKitSync.acceptShare` so `DataStore` can persist the new
/// joined household row with the zone identity needed to address it across
/// future app launches.
struct HouseholdShareInfo: Sendable {
    let shareRecordName: String
    let zoneName: String
    let ownerUserRecordName: String
    let title: String
    let inviterName: String?
}

// MARK: - Payload

struct CloudKitPayload {
    let tasks: [HouseholdTask]
    let completions: [TaskCompletion]
    let profiles: [UserProfile]
    let inviterName: String?
    let personalTaskIDs: Set<UUID>
}

// MARK: - Errors

enum CloudKitSyncError: Error, LocalizedError {
    case shareCreationFailed(underlying: Error? = nil, detail: String? = nil)
    case householdCleanupFailed(underlying: Error? = nil, detail: String? = nil)
    case zoneNotFound
    case iCloudUnavailable(status: String)
    case invalidShareURL
    case invalidShareContainer

    var errorDescription: String? {
        switch self {
        case .shareCreationFailed(let underlying, let detail):
            if let detail { return "Share creation failed: \(detail)" }
            if let underlying { return "Share creation failed: \(underlying.localizedDescription)" }
            return "Share creation failed (no detail)"
        case .householdCleanupFailed(let underlying, let detail):
            if let detail { return "Household cleanup failed: \(detail)" }
            if let underlying { return "Household cleanup failed: \(underlying.localizedDescription)" }
            return "Household cleanup failed (no detail)"
        case .zoneNotFound:
            return "CloudKit zone not found"
        case .iCloudUnavailable(let status):
            return "iCloud not available (status: \(status))"
        case .invalidShareURL:
            return "This link is not an iCloud household invitation."
        case .invalidShareContainer:
            return "This invitation belongs to another app. Open an ADultingHD household invitation."
        }
    }
}

/// CloudKit uses `batchRequestFailed` for records that were rejected only
/// because a different item in the same request failed. Its localized text is
/// usually just "Atomic failure", which is not the underlying cause.
func isCloudKitBatchRequestFailure(_ error: Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == CKErrorDomain
        && nsError.code == CKError.Code.batchRequestFailed.rawValue
}

/// Preserve the readable server message while also including the numeric
/// CloudKit code. The latter remains useful when CloudKit supplies a vague or
/// localized description that does not name the rejected field.
func cloudKitFailureDetails(_ error: Error) -> String {
    let nsError = error as NSError
    guard nsError.domain == CKErrorDomain else { return error.localizedDescription }
    return "\(error.localizedDescription) [CKError \(nsError.code)]"
}

// MARK: - CKDatabase convenience

private extension CKDatabase {
    func allRecordZones() async throws -> [CKRecordZone] {
        try await withCheckedThrowingContinuation { cont in
            let op = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
            var zones: [CKRecordZone] = []
            op.perRecordZoneResultBlock = { _, result in
                if case .success(let z) = result { zones.append(z) }
            }
            op.fetchRecordZonesResultBlock = { result in
                switch result {
                case .success: cont.resume(returning: zones)
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            self.add(op)
        }
    }

    func save(_ zone: CKRecordZone) async throws -> CKRecordZone {
        try await withCheckedThrowingContinuation { cont in
            let op = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success: cont.resume(returning: zone)
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            self.add(op)
        }
    }

    func deleteZone(withID zoneID: CKRecordZone.ID) async throws {
        try await withCheckedThrowingContinuation { cont in
            let op = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: [zoneID])
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: ())
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
            self.add(op)
        }
    }

    func record(for id: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { cont in
            self.fetch(withRecordID: id) { record, error in
                if let record { cont.resume(returning: record) }
                else { cont.resume(throwing: error ?? CloudKitSyncError.zoneNotFound) }
            }
        }
    }

    func fetchAllSubscriptions() async throws -> [CKSubscription] {
        try await withCheckedThrowingContinuation { cont in
            self.fetchAllSubscriptions { subs, error in
                if let subs { cont.resume(returning: subs) }
                else { cont.resume(throwing: error ?? CloudKitSyncError.zoneNotFound) }
            }
        }
    }

    func saveSubscription(_ sub: CKSubscription) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { cont in
            self.save(sub) { saved, error in
                if let saved { cont.resume(returning: saved) }
                else { cont.resume(throwing: error ?? CloudKitSyncError.zoneNotFound) }
            }
        }
    }

    func modifyRecords(saving: [CKRecord], deleting: [CKRecord.ID]) async throws -> ([CKRecord], [CKRecord.ID]) {
        try await withCheckedThrowingContinuation { cont in
            let op = CKModifyRecordsOperation(recordsToSave: saving, recordIDsToDelete: deleting)
            op.savePolicy = .changedKeys
            var saved: [CKRecord] = []
            op.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success(let r): saved.append(r)
                case .failure(let e):
                    logger.error("☁️ per-record save failed for \(recordID.recordName, privacy: .private): \(e.localizedDescription, privacy: .private)")
                }
            }
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume(returning: (saved, []))
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            self.add(op)
        }
    }
}

// MARK: - CKRecord conversions

/// A privacy-preserving CloudKit marker for a task that was removed from the
/// shared household because it became personal. The marker carries only the
/// task UUID, so other household members can remove an old shared copy without
/// receiving the task's name, schedule, notes, or checklist.
struct PersonalTaskTombstone {
    private static let recordNamePrefix = "personal-task-"
    let taskID: UUID

    static func recordID(for taskID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: recordNamePrefix + taskID.uuidString, zoneID: zoneID)
    }

    func toCKRecord(zoneID: CKRecordZone.ID, parentRecordID: CKRecord.ID? = nil) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.personalTaskTombstone,
            recordID: Self.recordID(for: taskID, zoneID: zoneID)
        )
        if let parentRecordID {
            record.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
        }
        // CloudKit does not allow an empty custom record type to be promoted
        // from Development to Production. Keep the marker privacy-preserving
        // by storing only the task UUID (the same value already encoded in
        // the record ID); no task content crosses the household boundary.
        record["taskId"] = taskID.uuidString as CKRecordValue
        return record
    }

    static func taskID(from record: CKRecord) -> UUID? {
        guard record.recordType == RecordType.personalTaskTombstone else { return nil }
        guard record.recordID.recordName.hasPrefix(recordNamePrefix) else { return nil }
        return UUID(uuidString: String(record.recordID.recordName.dropFirst(recordNamePrefix.count)))
    }
}

extension HouseholdTask {
    func toCKRecord(zone: CKRecordZone) -> CKRecord {
        toCKRecord(zoneID: zone.zoneID)
    }

    func toCKRecord(zoneID: CKRecordZone.ID, parentRecordID: CKRecord.ID? = nil) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r = CKRecord(recordType: RecordType.task, recordID: recordID)
        if let parentRecordID {
            r.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
        }
        r["name"]             = name as CKRecordValue
        r["taskDescription"]  = description as CKRecordValue
        r["room"]             = HouseholdTask.normalizedRoom(room) as CKRecordValue?
        r["category"]         = category.rawValue as CKRecordValue
        r["scheduleFrequency"] = frequency.rawValue as CKRecordValue
        let legacyFrequency = frequency == .unscheduled ? TaskFrequency.weekly.rawValue : frequency.rawValue
        r["frequency"]        = legacyFrequency as CKRecordValue
        // These snapshots let a newer client detect a later `.changedKeys`
        // update from an older client. Without them, stale additive fields
        // would silently shadow legacy category/frequency edits.
        r["planningSchemaVersion"] = 1 as CKRecordValue
        r["legacyCategorySnapshot"] = category.rawValue as CKRecordValue
        r["legacyFrequencySnapshot"] = legacyFrequency as CKRecordValue
        r["estimatedMinutes"] = estimatedMinutes as CKRecordValue
        r["difficulty"]       = difficulty.rawValue as CKRecordValue
        r["supplies"]         = supplies as CKRecordValue
        r["isActive"]         = (isActive ? 1 : 0) as CKRecordValue
        r["lastCompleted"]    = lastCompleted as CKRecordValue?
        r["defaultAssigneeId"] = defaultAssigneeId?.uuidString as CKRecordValue?
        // Personal tasks are filtered before upload. Keep the field available
        // for defensive round-trips, but omit the false value so existing
        // CloudKit schemas continue to accept ordinary household records.
        if isPersonal {
            r["isPersonal"] = 1 as CKRecordValue
        }
        r["scheduledWeekdays"] = scheduledWeekdays.isEmpty ? nil : scheduledWeekdays as CKRecordValue?
        r["scheduledDayOfMonth"] = scheduledDayOfMonth as CKRecordValue?
        r["scheduledMonth"] = scheduledMonth as CKRecordValue?
        r["checklist"] = checklist.isEmpty ? nil : (try? sharedJSONEncoder.encode(checklist)) as CKRecordValue?
        return r
    }

    init?(from record: CKRecord) {
        guard
            let uuidString = record.recordID.recordName.nilIfEmpty,
            let id = UUID(uuidString: uuidString),
            let name = record["name"] as? String
        else { return nil }

        let planningSchemaVersion = record["planningSchemaVersion"] as? Int ?? 0
        let preferredFrequency = record["scheduleFrequency"] as? String
        let legacyFrequency = record["frequency"] as? String
        let legacyFrequencySnapshot = record["legacyFrequencySnapshot"] as? String
        let legacyFrequencyWasEdited = planningSchemaVersion > 0
            && legacyFrequencySnapshot != nil
            && legacyFrequency != legacyFrequencySnapshot
        let frequency = (legacyFrequencyWasEdited ? legacyFrequency : preferredFrequency)
            .flatMap(TaskFrequency.init(rawValue:))
            ?? legacyFrequency.flatMap(TaskFrequency.init(rawValue:))
            ?? .unscheduled
        let difficulty = (record["difficulty"] as? Int).flatMap(Difficulty.init(rawValue:)) ?? .medium
        let preferredRoom = HouseholdTask.normalizedRoom(record["room"] as? String)
        let legacyCategory = record["category"] as? String
        let legacyRoom = HouseholdTask.roomFromLegacyCategory(legacyCategory)
        let legacyCategorySnapshot = record["legacyCategorySnapshot"] as? String
        let legacyCategoryWasEdited = planningSchemaVersion > 0
            && legacyCategorySnapshot != nil
            && legacyCategory != legacyCategorySnapshot

        self.id = id
        self.name = name
        self.description = record["taskDescription"] as? String ?? ""
        self.room = legacyCategoryWasEdited
            ? legacyRoom
            : (planningSchemaVersion > 0 ? preferredRoom : legacyRoom)
        self.frequency = frequency
        self.estimatedMinutes = record["estimatedMinutes"] as? Int ?? 30
        self.difficulty = difficulty
        self.supplies = record["supplies"] as? [String] ?? []
        self.isActive = (record["isActive"] as? Int ?? 1) == 1
        self.lastCompleted = record["lastCompleted"] as? Date
        // `createdAt` and `scheduledOverrideDate` are local model fields that
        // are absent from the deployed production schema. Ignore any legacy
        // copies so stale Development values cannot resurrect cleared edits.
        self.createdAt = record.creationDate ?? Date()
        self.defaultAssigneeId = (record["defaultAssigneeId"] as? String).flatMap(UUID.init)
        self.isPersonal = (record["isPersonal"] as? Int ?? 0) == 1
        self.scheduledWeekdays = record["scheduledWeekdays"] as? [Int] ?? []
        self.scheduledDayOfMonth = record["scheduledDayOfMonth"] as? Int
        self.scheduledMonth = record["scheduledMonth"] as? Int
        if let data = record["checklist"] as? Data,
           let decoded = try? sharedJSONDecoder.decode([ChecklistItem].self, from: data) {
            self.checklist = decoded
        } else {
            self.checklist = []
        }
        self.scheduledOverrideDate = nil
    }
}

extension TaskCompletion {
    func toCKRecord(zone: CKRecordZone) -> CKRecord {
        toCKRecord(zoneID: zone.zoneID)
    }

    func toCKRecord(zoneID: CKRecordZone.ID, parentRecordID: CKRecord.ID? = nil) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r = CKRecord(recordType: RecordType.completion, recordID: recordID)
        if let parentRecordID {
            r.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
        }
        r["taskId"]      = taskId.uuidString as CKRecordValue
        r["taskName"]    = taskName as CKRecordValue
        r["completedAt"] = completedAt as CKRecordValue
        r["xpEarned"]    = xpEarned as CKRecordValue
        r["streakBonus"] = streakBonus as CKRecordValue
        r["notes"]       = notes as CKRecordValue?
        r["profileId"]   = profileId?.uuidString as CKRecordValue?
        r["oneTimeDueDate"] = oneTimeDueDate as CKRecordValue?
        return r
    }

    init?(from record: CKRecord) {
        guard
            let uuidString = record.recordID.recordName.nilIfEmpty,
            let id = UUID(uuidString: uuidString),
            let taskIdString = record["taskId"] as? String,
            let taskId = UUID(uuidString: taskIdString),
            let taskName = record["taskName"] as? String,
            let completedAt = record["completedAt"] as? Date,
            let xpEarned = record["xpEarned"] as? Int,
            let streakBonus = record["streakBonus"] as? Int
        else { return nil }

        self.id = id
        self.taskId = taskId
        self.taskName = taskName
        self.completedAt = completedAt
        self.xpEarned = xpEarned
        self.streakBonus = streakBonus
        self.notes = record["notes"] as? String
        self.profileId = (record["profileId"] as? String).flatMap(UUID.init)
        self.oneTimeDueDate = record["oneTimeDueDate"] as? Date
    }
}

extension UserProfile {
    func toCKRecord(zone: CKRecordZone) -> CKRecord {
        toCKRecord(zoneID: zone.zoneID)
    }

    func toCKRecord(zoneID: CKRecordZone.ID, parentRecordID: CKRecord.ID? = nil) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r = CKRecord(recordType: RecordType.profile, recordID: recordID)
        if let parentRecordID {
            r.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
        }
        r["name"]                  = name as CKRecordValue
        r["avatar"]                = avatar as CKRecordValue
        r["totalXP"]               = totalXP as CKRecordValue
        r["coins"]                 = coins as CKRecordValue
        r["currentStreak"]         = currentStreak as CKRecordValue
        r["longestStreak"]         = longestStreak as CKRecordValue
        r["totalTasksCompleted"]   = totalTasksCompleted as CKRecordValue
        r["joinDate"]              = joinDate as CKRecordValue
        r["lastActiveDate"]        = lastActiveDate as CKRecordValue?
        r["unlockedAchievements"]  = unlockedAchievements as CKRecordValue
        if let stateData = try? JSONEncoder().encode(avatarState) {
            r["avatarState"] = stateData as CKRecordValue
        }
        return r
    }

    init?(from record: CKRecord) {
        guard
            let uuidString = record.recordID.recordName.nilIfEmpty,
            let id = UUID(uuidString: uuidString),
            let name = record["name"] as? String
        else { return nil }

        self.id = id
        self.name = name
        self.avatar = record["avatar"] as? String ?? "person.crop.circle.fill"
        self.totalXP = record["totalXP"] as? Int ?? 0
        self.coins = record["coins"] as? Int ?? 0
        self.currentStreak = record["currentStreak"] as? Int ?? 0
        self.longestStreak = record["longestStreak"] as? Int ?? 0
        self.totalTasksCompleted = record["totalTasksCompleted"] as? Int ?? 0
        self.joinDate = record["joinDate"] as? Date ?? Date()
        self.lastActiveDate = record["lastActiveDate"] as? Date
        self.unlockedAchievements = record["unlockedAchievements"] as? [String] ?? []
        if let stateData = record["avatarState"] as? Data,
           let state = try? JSONDecoder().decode(AvatarState.self, from: stateData) {
            self.avatarState = state
        } else {
            self.avatarState = AvatarState()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
