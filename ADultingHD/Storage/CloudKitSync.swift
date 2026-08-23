import Foundation
import CloudKit
import os

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "CloudKitSync")

private let sharedJSONEncoder = JSONEncoder()
private let sharedJSONDecoder = JSONDecoder()

// MARK: - CloudKit record type names

enum RecordType {
    static let task       = "HouseholdTask"
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

    @Published var isAvailable = false
    @Published var syncError: String?

    // Lazy so the CKContainer is only constructed when CloudKit is actually used.
    // CKContainer(identifier:) traps when the iCloud entitlement is missing
    // (e.g. unsigned builds for tests with CODE_SIGNING_ALLOWED=NO), so eager
    // construction would crash the host app at launch during test runs even
    // though all real CloudKit code paths are gated behind isHouseholdSharingEnabled.
    private lazy var container = CKContainer(identifier: "iCloud.net.shadowpuppet.ADultingHD")
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
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                logger.info("☁️ iCloud not available: \(String(describing: status), privacy: .public)")
                syncError = "iCloud account status: \(status)"
                isAvailable = false
                return
            }
            isAvailable = true
            syncError = nil
            logger.info("☁️ CloudKit ready")
        } catch {
            logger.error("☁️ CloudKit setup failed: \(error.localizedDescription, privacy: .public)")
            syncError = error.localizedDescription
            isAvailable = false
        }
    }

    /// Ensure the household's zone exists in `privateCloudDatabase`. No-op
    /// for joined households — CloudKit auto-mirrors the owner's zone into
    /// our `sharedCloudDatabase` when the share is accepted.
    private func ensureOwnedZoneExists(for household: Household) async throws {
        guard household.ownerIsCurrentUser else { return }
        let zones = try await privateDB.allRecordZones()
        if zones.contains(where: { $0.zoneID.zoneName == household.zoneName }) { return }
        _ = try await privateDB.save(CKRecordZone(zoneName: household.zoneName))
        logger.info("☁️ Created zone \(household.zoneName, privacy: .public)")
    }

    func setupSubscriptions(for household: Household) async {
        guard isAvailable else { return }
        let zoneName = household.zoneName
        guard !configuredSubscriptionZones.contains(zoneName) else { return }
        let subscriptionID = "household-zone-changes-\(zoneName)"
        do {
            let db = database(for: household)
            let zoneID = zoneID(for: household)
            let existing = try await db.fetchAllSubscriptions()
            if !existing.contains(where: { $0.subscriptionID == subscriptionID }) {
                let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                sub.notificationInfo = info
                _ = try await db.saveSubscription(sub)
                logger.info("☁️ CloudKit zone subscription registered for \(zoneName, privacy: .public)")
            }
            configuredSubscriptionZones.insert(zoneName)
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
                        logger.info("☁️ Deleted household zone \(household.zoneName, privacy: .public) and revoked participants")
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
                        logger.info("☁️ Left shared household zone \(household.zoneName, privacy: .public)")
                    }
                } catch {
                    // A zone already removed by its owner is already cleaned
                    // up from this participant's point of view.
                    if !isMissingCloudKitObject(error) { throw error }
                }
            }
            configuredSubscriptionZones.remove(household.zoneName)
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

    func pushTasks(_ tasks: [HouseholdTask], household: Household) async {
        guard isAvailable else { return }
        let zoneID = zoneID(for: household)
        let rootID = rootRecordID(for: household)
        let records = tasks.map { $0.toCKRecord(zoneID: zoneID, parentRecordID: rootID) }
        await saveRecords(records, in: database(for: household))
    }

    func pushProfile(_ profile: UserProfile, household: Household) async {
        guard isAvailable else { return }
        let record = profile.toCKRecord(zoneID: zoneID(for: household), parentRecordID: rootRecordID(for: household))
        await saveRecords([record], in: database(for: household))
    }

    func pushCompletion(_ completion: TaskCompletion, household: Household) async {
        guard isAvailable else { return }
        let record = completion.toCKRecord(zoneID: zoneID(for: household), parentRecordID: rootRecordID(for: household))
        await saveRecords([record], in: database(for: household))
    }

    /// Upload every record a newly invited participant needs before the share
    /// sheet is presented. Unlike ordinary best-effort sync, this path is
    /// fail-closed: every per-record result must succeed or invite preparation
    /// throws and the user can retry without sending an incomplete household.
    func uploadInitialShareSnapshot(
        tasks: [HouseholdTask],
        profile: UserProfile,
        completions: [TaskCompletion],
        members: [UserProfile],
        household: Household
    ) async throws {
        guard isAvailable else {
            throw CloudKitSyncError.iCloudUnavailable(status: syncError ?? "unknown")
        }

        let zoneID = zoneID(for: household)
        let rootID = rootRecordID(for: household)
        let db = database(for: household)
        var profilesByID = members.reduce(into: [UUID: UserProfile]()) { profiles, member in
            profiles[member.id] = member
        }
        profilesByID[profile.id] = profile
        let records = tasks.map { $0.toCKRecord(zoneID: zoneID, parentRecordID: rootID) }
            + completions.map { $0.toCKRecord(zoneID: zoneID, parentRecordID: rootID) }
            + profilesByID.values.map { $0.toCKRecord(zoneID: zoneID, parentRecordID: rootID) }

        // Stay comfortably below CloudKit's per-operation record limit while
        // retaining exact per-record validation for large completion histories.
        let batchSize = 200
        for batchStart in stride(from: 0, to: records.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, records.count)
            try await saveRequiredRecords(Array(records[batchStart..<batchEnd]), in: db)
        }
        logger.info("☁️ Initial share snapshot uploaded: \(records.count) records")
    }

    private func saveRecords(_ records: [CKRecord], in db: CKDatabase) async {
        guard !records.isEmpty else { return }
        do {
            _ = try await db.modifyRecords(saving: records, deleting: [])
            logger.info("☁️ Pushed \(records.count) records")
        } catch {
            logger.error("☁️ Push failed: \(error.localizedDescription)")
            syncError = error.localizedDescription
        }
    }

    private func saveRequiredRecords(_ records: [CKRecord], in db: CKDatabase) async throws {
        guard !records.isEmpty else { return }
        do {
            let results = try await db.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            var failures: [String] = []
            for record in records {
                guard let result = results.saveResults[record.recordID] else {
                    failures.append("\(record.recordID.recordName): no result returned")
                    continue
                }
                if case .failure(let error) = result {
                    failures.append("\(record.recordID.recordName): \(error.localizedDescription)")
                }
            }
            guard failures.isEmpty else {
                throw CloudKitSyncError.shareCreationFailed(
                    detail: "initial household upload failed: \(failures.joined(separator: " | "))"
                )
            }
            logger.info("☁️ Pushed required batch of \(records.count) records")
        } catch {
            syncError = error.localizedDescription
            if let cloudKitError = error as? CloudKitSyncError { throw cloudKitError }
            throw CloudKitSyncError.shareCreationFailed(
                detail: "initial household upload failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Pull (CloudKit → local)

    func pullAll(for household: Household) async -> CloudKitPayload? {
        guard isAvailable else { return nil }
        let db = database(for: household)
        let zoneID = zoneID(for: household)
        do {
            async let tasks       = fetchRecords(ofType: RecordType.task,       from: db, zoneID: zoneID)
            async let completions = fetchRecords(ofType: RecordType.completion, from: db, zoneID: zoneID)
            async let profileRecords = fetchRecords(ofType: RecordType.profile, from: db, zoneID: zoneID)

            let (t, c, p) = try await (tasks, completions, profileRecords)
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
                inviterName: inviterName
            )
            logger.info("☁️ Pulled \(payload.tasks.count) tasks, \(payload.completions.count) completions, \(payload.profiles.count) profiles from \(household.zoneName, privacy: .public)")
            return payload
        } catch {
            logger.error("☁️ Pull failed: \(error.localizedDescription)")
            syncError = error.localizedDescription
            return nil
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
            let (records, nextCursor) = try await withCheckedThrowingContinuation { cont in
                var batch: [CKRecord] = []
                op.recordMatchedBlock = { _, result in
                    if case .success(let r) = result { batch.append(r) }
                }
                op.queryResultBlock = { result in
                    switch result {
                    case .success(let c): cont.resume(returning: (batch, c))
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
        logger.info("☁️ createOrFetchShare zone=\(household.zoneName, privacy: .public) rootID=\(rootID.recordName, privacy: .public)")

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
                    logger.info("☁️ Reusing household share: \(existingShare.url?.absoluteString ?? "no url", privacy: .public)")
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
        logger.info("☁️ Saving root + share atomically (share.recordID=\(share.recordID.recordName, privacy: .public))")

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
            logger.error("☁️ modifyRecords top-level threw: \(error.localizedDescription, privacy: .public)")
            logger.error("☁️ underlying: \(String(describing: error), privacy: .public)")
            throw CloudKitSyncError.shareCreationFailed(underlying: error)
        }

        // Log every per-record result so we can see which one failed and why.
        var savedRecords: [CKRecord] = []
        var failures: [String] = []
        for (recordID, result) in saveResults {
            switch result {
            case .success(let record):
                savedRecords.append(record)
                logger.info("☁️ saved \(record.recordType, privacy: .public) id=\(recordID.recordName, privacy: .public)")
            case .failure(let error):
                let msg = "\(recordID.recordName): \(error.localizedDescription)"
                failures.append(msg)
                logger.error("☁️ save failed for \(msg, privacy: .public) — \(String(describing: error), privacy: .public)")
            }
        }

        guard let savedShare = savedRecords.compactMap({ $0 as? CKShare }).first else {
            let typeList = savedRecords.map(\.recordType).joined(separator: ",")
            let failureList = failures.isEmpty ? "no per-record failures reported" : failures.joined(separator: " | ")
            throw CloudKitSyncError.shareCreationFailed(
                detail: "saved=[\(typeList)] failures=[\(failureList)]"
            )
        }
        logger.info("☁️ Created household share: \(savedShare.url?.absoluteString ?? "no url", privacy: .public)")
        return savedShare
    }

    /// Accept a CKShare invite. Returns the data needed to register a new
    /// joined household locally — caller is responsible for inserting the
    /// row into `householdIndex` (this layer doesn't know about it). The
    /// metadata's `share.recordID.zoneID` carries both the zoneName and the
    /// inviter's user record name, which together identify the shared zone
    /// against `sharedCloudDatabase` across app restarts.
    func acceptShare(from metadata: CKShare.Metadata) async throws -> HouseholdShareInfo {
        try await container.accept(metadata)
        let info = shareInfo(from: metadata)
        logger.info("☁️ Accepted household share zone=\(info.zoneName, privacy: .public) owner=\(info.ownerUserRecordName, privacy: .public)")
        return info
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
}

// MARK: - Errors

enum CloudKitSyncError: Error, LocalizedError {
    case shareCreationFailed(underlying: Error? = nil, detail: String? = nil)
    case householdCleanupFailed(underlying: Error? = nil, detail: String? = nil)
    case zoneNotFound
    case iCloudUnavailable(status: String)

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
        }
    }
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
                    logger.error("☁️ per-record save failed for \(recordID.recordName, privacy: .public): \(e.localizedDescription, privacy: .public)")
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
        r["category"]         = category.rawValue as CKRecordValue
        r["frequency"]        = frequency.rawValue as CKRecordValue
        r["estimatedMinutes"] = estimatedMinutes as CKRecordValue
        r["difficulty"]       = difficulty.rawValue as CKRecordValue
        r["supplies"]         = supplies as CKRecordValue
        r["isActive"]         = (isActive ? 1 : 0) as CKRecordValue
        r["lastCompleted"]    = lastCompleted as CKRecordValue?
        r["defaultAssigneeId"] = defaultAssigneeId?.uuidString as CKRecordValue?
        r["scheduledWeekdays"] = scheduledWeekdays.isEmpty ? nil : scheduledWeekdays as CKRecordValue?
        r["scheduledDayOfMonth"] = scheduledDayOfMonth as CKRecordValue?
        r["scheduledMonth"] = scheduledMonth as CKRecordValue?
        r["checklist"] = checklist.isEmpty ? nil : (try? sharedJSONEncoder.encode(checklist)) as CKRecordValue?
        r["scheduledOverrideDate"] = scheduledOverrideDate as CKRecordValue?
        return r
    }

    init?(from record: CKRecord) {
        guard
            let uuidString = record.recordID.recordName.nilIfEmpty,
            let id = UUID(uuidString: uuidString),
            let name = record["name"] as? String,
            let categoryRaw = record["category"] as? String,
            let category = TaskCategory(rawValue: categoryRaw),
            let frequencyRaw = record["frequency"] as? String,
            let frequency = TaskFrequency(rawValue: frequencyRaw),
            let difficultyRaw = record["difficulty"] as? Int,
            let difficulty = Difficulty(rawValue: difficultyRaw)
        else { return nil }

        self.id = id
        self.name = name
        self.description = record["taskDescription"] as? String ?? ""
        self.category = category
        self.frequency = frequency
        self.estimatedMinutes = record["estimatedMinutes"] as? Int ?? 30
        self.difficulty = difficulty
        self.supplies = record["supplies"] as? [String] ?? []
        self.isActive = (record["isActive"] as? Int ?? 1) == 1
        self.lastCompleted = record["lastCompleted"] as? Date
        // `createdAt` was added after the production schema was deployed, so
        // it is intentionally not uploaded as a custom field. Use the
        // server-managed record creation date to keep recurrence anchors
        // stable for shared tasks, while still accepting any older records
        // that may already contain the custom field in Development.
        self.createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        self.defaultAssigneeId = (record["defaultAssigneeId"] as? String).flatMap(UUID.init)
        self.scheduledWeekdays = record["scheduledWeekdays"] as? [Int] ?? []
        self.scheduledDayOfMonth = record["scheduledDayOfMonth"] as? Int
        self.scheduledMonth = record["scheduledMonth"] as? Int
        if let data = record["checklist"] as? Data,
           let decoded = try? sharedJSONDecoder.decode([ChecklistItem].self, from: data) {
            self.checklist = decoded
        } else {
            self.checklist = []
        }
        self.scheduledOverrideDate = record["scheduledOverrideDate"] as? Date
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
