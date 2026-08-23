import Foundation

/// A named workspace of tasks, supplies, and members. Free users get one;
/// Pro unlocks additional households and CKShare collaborator invites.
/// XP/level/streak are global across all households (only the task list
/// and supply stock are scoped).
struct Household: Identifiable, Codable {
    enum Ownership: Codable, Equatable {
        case owned
        case joined(ownerUserRecordName: String, inviterName: String?)
    }

    let id: UUID
    var name: String
    let createdAt: Date
    var members: [UserProfile]
    /// CKShare root record name; `nil` until the household is shared.
    var shareRecordName: String?
    /// CloudKit ownership and inviter identity are one value so a joined
    /// household can never exist without the owner record name needed to
    /// address its shared zone.
    private(set) var ownership: Ownership
    /// CloudKit custom zone name. The default migrated household reuses
    /// `ZoneName.household` so existing TestFlight users don't lose records
    /// (CloudKit can't rename zones).
    var zoneName: String
    /// Task IDs that have been marked personal in this household, including
    /// tasks since deleted locally. Keeping ownership separately from the
    /// current task array prevents private completion history from being
    /// uploaded after a personal task is removed or a household is switched.
    var personalTaskIDs: Set<UUID>
    /// Personal markers currently present in this household's CloudKit zone.
    /// This is separate from local ownership so a cleared remote tombstone is
    /// reconciled without erasing private history kept on this device.
    var cloudPersonalTaskIDs: Set<UUID>
    /// Personal markers waiting to be deleted because the task was explicitly
    /// changed back to household scope. Persisting this retry state prevents a
    /// failed/offline transition from being lost across app launches.
    var pendingPersonalTaskReleases: Set<UUID>

    var ownerIsCurrentUser: Bool {
        if case .owned = ownership { return true }
        return false
    }

    var ownerUserRecordName: String? {
        guard case .joined(let ownerUserRecordName, _) = ownership else { return nil }
        return ownerUserRecordName
    }

    var inviterName: String? {
        get {
            guard case .joined(_, let inviterName) = ownership else { return nil }
            return inviterName
        }
        set {
            guard case .joined(let ownerUserRecordName, _) = ownership else { return }
            ownership = .joined(ownerUserRecordName: ownerUserRecordName, inviterName: newValue)
        }
    }

    private init(
        id: UUID,
        name: String,
        createdAt: Date = Date(),
        members: [UserProfile],
        shareRecordName: String? = nil,
        ownership: Ownership,
        zoneName: String,
        personalTaskIDs: Set<UUID> = [],
        cloudPersonalTaskIDs: Set<UUID> = [],
        pendingPersonalTaskReleases: Set<UUID> = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.members = members
        self.shareRecordName = shareRecordName
        self.ownership = ownership
        self.zoneName = zoneName
        self.personalTaskIDs = personalTaskIDs
        self.cloudPersonalTaskIDs = cloudPersonalTaskIDs
        self.pendingPersonalTaskReleases = pendingPersonalTaskReleases
    }

    /// Convenience constructor for a locally-owned household. New households
    /// get a unique CloudKit zone; the legacy zone is opt-in for migration.
    static func newLocal(
        id: UUID? = nil,
        name: String,
        members: [UserProfile],
        zoneName: String? = nil
    ) -> Household {
        let householdID = id ?? UUID()
        return Household(
            id: householdID,
            name: name,
            members: members,
            ownership: .owned,
            zoneName: zoneName ?? ZoneName.uniqueHousehold(for: householdID)
        )
    }

    /// Convenience constructor for a household joined via a CKShare invite.
    /// `zoneName` and `ownerUserRecordName` come from the share metadata's
    /// `recordID.zoneID` and let CloudKit calls target `sharedCloudDatabase`
    /// after app restart without losing track of which shared zone backs
    /// this row.
    static func newJoined(
        id: UUID = UUID(),
        name: String,
        members: [UserProfile],
        zoneName: String,
        ownerUserRecordName: String,
        inviterName: String? = nil
    ) -> Household {
        Household(
            id: id,
            name: name,
            members: members,
            ownership: .joined(
                ownerUserRecordName: ownerUserRecordName,
                inviterName: inviterName
            ),
            zoneName: zoneName
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, members, shareRecordName, ownership, zoneName, personalTaskIDs, cloudPersonalTaskIDs, pendingPersonalTaskReleases
        // Schema-v3 compatibility. `ownership` is authoritative; these
        // shadow fields are dual-written so older synced clients still load.
        case ownerIsCurrentUser, ownerUserRecordName, inviterName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        members = try container.decode([UserProfile].self, forKey: .members)
        shareRecordName = try container.decodeIfPresent(String.self, forKey: .shareRecordName)
        zoneName = try container.decode(String.self, forKey: .zoneName)
        personalTaskIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .personalTaskIDs) ?? []
        cloudPersonalTaskIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .cloudPersonalTaskIDs) ?? []
        pendingPersonalTaskReleases = try container.decodeIfPresent(Set<UUID>.self, forKey: .pendingPersonalTaskReleases) ?? []

        let legacyOwnerIsCurrentUser = try container.decodeIfPresent(Bool.self, forKey: .ownerIsCurrentUser) ?? true
        let legacyOwnerUserRecordName = try container.decodeIfPresent(String.self, forKey: .ownerUserRecordName)

        if let decodedOwnership = try container.decodeIfPresent(Ownership.self, forKey: .ownership) {
            ownership = decodedOwnership
        } else if !legacyOwnerIsCurrentUser, let legacyOwnerUserRecordName {
            ownership = .joined(
                ownerUserRecordName: legacyOwnerUserRecordName,
                inviterName: try container.decodeIfPresent(String.self, forKey: .inviterName)
            )
        } else {
            ownership = .owned
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(members, forKey: .members)
        try container.encodeIfPresent(shareRecordName, forKey: .shareRecordName)
        try container.encode(ownership, forKey: .ownership)
        try container.encode(zoneName, forKey: .zoneName)
        try container.encode(personalTaskIDs, forKey: .personalTaskIDs)
        try container.encode(cloudPersonalTaskIDs, forKey: .cloudPersonalTaskIDs)
        try container.encode(pendingPersonalTaskReleases, forKey: .pendingPersonalTaskReleases)
        // Dual-write schema-v3 ownership keys while household indexes sync
        // through iCloud to devices that may still run an older app build.
        switch ownership {
        case .owned:
            try container.encode(true, forKey: .ownerIsCurrentUser)
        case .joined(let ownerUserRecordName, let inviterName):
            try container.encode(false, forKey: .ownerIsCurrentUser)
            try container.encode(ownerUserRecordName, forKey: .ownerUserRecordName)
            try container.encodeIfPresent(inviterName, forKey: .inviterName)
        }
    }
}

/// Top-level file (households.json) listing all known households and the active one.
struct HouseholdIndex: Codable {
    var households: [Household]
    var activeHouseholdId: UUID
    var schemaVersion: Int

    static let currentSchemaVersion = 4

    var activeHousehold: Household? {
        households.first { $0.id == activeHouseholdId }
    }
}
