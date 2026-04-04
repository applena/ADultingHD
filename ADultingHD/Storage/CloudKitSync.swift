import Foundation
import CloudKit
import os

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "CloudKitSync")

// MARK: - CloudKit record type names

private enum RecordType {
    static let task       = "HouseholdTask"
    static let completion = "TaskCompletion"
    static let profile    = "MemberProfile"
}

private enum ZoneName {
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

    private let container = CKContainer(identifier: "iCloud.net.shadowpuppet.ADultingHD")
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    private var zone: CKRecordZone { CKRecordZone(zoneName: ZoneName.household) }

    private var subscriptionsConfigured = false

    private init() {}

    // MARK: - Setup

    func setup() async {
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                logger.info("☁️ iCloud not available: \(String(describing: status))")
                return
            }
            isAvailable = true
            try await createZoneIfNeeded()
            logger.info("☁️ CloudKit ready")
        } catch {
            logger.error("☁️ CloudKit setup failed: \(error.localizedDescription)")
            syncError = error.localizedDescription
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
        let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.isAtomic = false
        do {
            let db = try await resolveDatabase()
            db.add(op)
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

    func createOrFetchShare() async throws -> CKShare {
        // Check for existing share on the zone
        let shares = try await privateDB.fetchAllRecordZoneChanges()
        if let existing = shares.first(where: { $0.recordType == "cloudkit.share" }) {
            return existing as! CKShare // swiftlint:disable:this force_cast
        }

        let share = CKShare(rootRecord: CKRecord(recordType: "_householdRoot",
                                                  recordID: CKRecord.ID(recordName: "root",
                                                                         zoneID: zone.zoneID)))
        share[CKShare.SystemFieldKey.title] = "ADultingHD Household" as CKRecordValue
        share.publicPermission = .none

        let (savedRecords, _) = try await privateDB.modifyRecords(saving: [share], deleting: [])
        guard let savedShare = savedRecords.first(where: { $0 is CKShare }) as? CKShare else {
            throw CloudKitSyncError.shareCreationFailed
        }
        shareURL = savedShare.url
        logger.info("☁️ Created household share: \(savedShare.url?.absoluteString ?? "no url")")
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

enum CloudKitSyncError: Error {
    case shareCreationFailed
    case zoneNotFound
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

    func fetchAllRecordZoneChanges() async throws -> [CKRecord] {
        // Lightweight share lookup — just fetch root record
        let id = CKRecord.ID(recordName: "root",
                              zoneID: CKRecordZone(zoneName: ZoneName.household).zoneID)
        return (try? await self.record(for: id)).map { [$0] } ?? []
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
            op.perRecordSaveBlock = { _, result in
                if case .success(let r) = result { saved.append(r) }
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
        r["quality"]     = quality?.rawValue as CKRecordValue?
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
        self.quality = (record["quality"] as? Int).flatMap(CompletionQuality.init)
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
