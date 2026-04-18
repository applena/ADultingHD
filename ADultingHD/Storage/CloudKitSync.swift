import Foundation
import CloudKit
import os

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "CloudKitSync")

private let sharedJSONEncoder = JSONEncoder()
private let sharedJSONDecoder = JSONDecoder()

// MARK: - CloudKit record type names

private enum RecordType {
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
    static let household = "HouseholdZone"
}

// MARK: - CloudKitSync

/// Manages a shared CKRecordZone in the user's private CloudKit database.
/// The zone owner shares it via CKShare; household members accept the share and
/// gain read/write access to the same tasks, completions, and profiles.
@MainActor
final class CloudKitSync: ObservableObject {

    static let shared = CloudKitSync()

    @Published var shareURL: URL?
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

    private var zone: CKRecordZone { CKRecordZone(zoneName: ZoneName.household) }

    private var subscriptionsConfigured = false

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
            try await createZoneIfNeeded()
            // Only mark available after the zone exists — createOrFetchShare
            // relies on writes landing in HouseholdZone, and a half-setup
            // state where accountStatus passes but zone creation failed
            // would otherwise let the share save run and fail confusingly.
            isAvailable = true
            syncError = nil
            logger.info("☁️ CloudKit ready")
        } catch {
            logger.error("☁️ CloudKit setup failed: \(error.localizedDescription, privacy: .public)")
            syncError = error.localizedDescription
            isAvailable = false
        }
    }

    private func createZoneIfNeeded() async throws {
        let zones = try await privateDB.allRecordZones()
        if zones.contains(where: { $0.zoneID.zoneName == ZoneName.household }) { return }
        _ = try await privateDB.save(zone)
        logger.info("☁️ Created HouseholdZone")
    }

    func setupSubscriptions() async {
        guard isAvailable, !subscriptionsConfigured else { return }
        let subscriptionID = "household-zone-changes"
        do {
            let db = try await resolveDatabase()
            let existing = try await db.fetchAllSubscriptions()
            if !existing.contains(where: { $0.subscriptionID == subscriptionID }) {
                let sub = CKRecordZoneSubscription(zoneID: zone.zoneID, subscriptionID: subscriptionID)
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                sub.notificationInfo = info
                _ = try await db.saveSubscription(sub)
                logger.info("☁️ CloudKit zone subscription registered")
            }
            subscriptionsConfigured = true
        } catch {
            logger.error("☁️ Subscription setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Push (local → CloudKit)

    func pushTasks(_ tasks: [HouseholdTask]) async {
        guard isAvailable else { return }
        let records = tasks.map { $0.toCKRecord(zone: zone) }
        await saveRecords(records)
    }

    func pushProfile(_ profile: UserProfile) async {
        guard isAvailable else { return }
        let record = profile.toCKRecord(zone: zone)
        await saveRecords([record])
    }

    func pushCompletion(_ completion: TaskCompletion) async {
        guard isAvailable else { return }
        let record = completion.toCKRecord(zone: zone)
        await saveRecords([record])
    }

    private func saveRecords(_ records: [CKRecord]) async {
        guard !records.isEmpty else { return }
        do {
            let db = try await resolveDatabase()
            _ = try await db.modifyRecords(saving: records, deleting: [])
            logger.info("☁️ Pushed \(records.count) records")
        } catch {
            logger.error("☁️ Push failed: \(error.localizedDescription)")
            syncError = error.localizedDescription
        }
    }

    // MARK: - Pull (CloudKit → local)

    func pullAll() async -> CloudKitPayload? {
        guard isAvailable else { return nil }
        do {
            let db = try await resolveDatabase()
            async let tasks       = fetchRecords(ofType: RecordType.task,       from: db)
            async let completions = fetchRecords(ofType: RecordType.completion, from: db)
            async let profiles    = fetchRecords(ofType: RecordType.profile,    from: db)

            let (t, c, p) = try await (tasks, completions, profiles)
            let payload = CloudKitPayload(
                tasks:       t.compactMap { HouseholdTask(from: $0) },
                completions: c.compactMap { TaskCompletion(from: $0) },
                profiles:    p.compactMap { UserProfile(from: $0) }
            )
            logger.info("☁️ Pulled \(payload.tasks.count) tasks, \(payload.completions.count) completions, \(payload.profiles.count) profiles")
            return payload
        } catch {
            logger.error("☁️ Pull failed: \(error.localizedDescription)")
            syncError = error.localizedDescription
            return nil
        }
    }

    private func fetchRecords(ofType type: String, from db: CKDatabase) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        var results: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil

        repeat {
            let op: CKQueryOperation = cursor.map(CKQueryOperation.init) ?? CKQueryOperation(query: query)
            op.zoneID = zone.zoneID
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

    /// Returns a CKShare for the household root record, creating one the
    /// first time and reusing it thereafter. Root record and share are
    /// always saved together — CloudKit requires both in the same operation.
    func createOrFetchShare() async throws -> CKShare {
        guard isAvailable else {
            logger.error("☁️ createOrFetchShare called but isAvailable=false")
            throw CloudKitSyncError.iCloudUnavailable(status: syncError ?? "unknown")
        }
        let rootID = CKRecord.ID(recordName: RootRecordName.household, zoneID: zone.zoneID)
        logger.info("☁️ createOrFetchShare zone=\(self.zone.zoneID.zoneName, privacy: .public) rootID=\(rootID.recordName, privacy: .public)")

        // If the root already exists, it carries a reference to its share.
        // Pull the share through that reference rather than guessing IDs.
        if let existingRoot = try? await privateDB.record(for: rootID) {
            logger.info("☁️ Root record already exists")
            if let shareReference = existingRoot.share {
                if let existingShare = try? await privateDB.record(for: shareReference.recordID) as? CKShare {
                    shareURL = existingShare.url
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
        rootRecord["title"] = "ADultingHD Household" as CKRecordValue

        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "ADultingHD Household" as CKRecordValue
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
        shareURL = savedShare.url
        logger.info("☁️ Created household share: \(savedShare.url?.absoluteString ?? "no url", privacy: .public)")
        return savedShare
    }

    func acceptShare(from metadata: CKShare.Metadata) async throws {
        try await container.accept(metadata)
        logger.info("☁️ Accepted household share")
    }

    // MARK: - Helpers

    /// Returns the private DB if we own the zone, or shared DB if we joined someone else's household
    private func resolveDatabase() async throws -> CKDatabase {
        _ = try? await container.userRecordID()
        // Simple heuristic: if zone exists in privateDB, use it; otherwise use sharedDB
        let zones = try await privateDB.allRecordZones()
        if zones.contains(where: { $0.zoneID.zoneName == ZoneName.household }) {
            return privateDB
        }
        return sharedDB
    }
}

// MARK: - Payload

struct CloudKitPayload {
    let tasks: [HouseholdTask]
    let completions: [TaskCompletion]
    let profiles: [UserProfile]
}

// MARK: - Errors

enum CloudKitSyncError: Error, LocalizedError {
    case shareCreationFailed(underlying: Error? = nil, detail: String? = nil)
    case zoneNotFound
    case iCloudUnavailable(status: String)

    var errorDescription: String? {
        switch self {
        case .shareCreationFailed(let underlying, let detail):
            if let detail { return "Share creation failed: \(detail)" }
            if let underlying { return "Share creation failed: \(underlying.localizedDescription)" }
            return "Share creation failed (no detail)"
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
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zone.zoneID)
        let r = CKRecord(recordType: RecordType.task, recordID: recordID)
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
    }
}

extension TaskCompletion {
    func toCKRecord(zone: CKRecordZone) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zone.zoneID)
        let r = CKRecord(recordType: RecordType.completion, recordID: recordID)
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
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zone.zoneID)
        let r = CKRecord(recordType: RecordType.profile, recordID: recordID)
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
}
