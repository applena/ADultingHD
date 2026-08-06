import Foundation

/// A named workspace of tasks, supplies, and members. Free users get one;
/// Pro unlocks additional households and CKShare collaborator invites.
/// XP/level/streak are global across all households (only the task list
/// and supply stock are scoped).
struct Household: Identifiable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    var members: [UserProfile]
    /// CKShare root record name; `nil` until the household is shared.
    var shareRecordName: String?
    /// `false` when the household was joined via someone else's invite —
    /// records then live in `sharedCloudDatabase` rather than `privateCloudDatabase`.
    var ownerIsCurrentUser: Bool
    /// CloudKit custom zone name. The default migrated household reuses
    /// `ZoneName.household` so existing TestFlight users don't lose records
    /// (CloudKit can't rename zones).
    var zoneName: String
    /// CloudKit user record name of the zone owner. Always nil for
    /// `ownerIsCurrentUser == true`; set to the inviter's user record name
    /// when this household represents an accepted CKShare. Required to
    /// construct a `CKRecordZone.ID` against `sharedCloudDatabase`.
    var ownerUserRecordName: String?

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
            createdAt: Date(),
            members: members,
            shareRecordName: nil,
            ownerIsCurrentUser: true,
            zoneName: zoneName ?? ZoneName.uniqueHousehold(for: householdID),
            ownerUserRecordName: nil
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
        ownerUserRecordName: String
    ) -> Household {
        Household(
            id: id,
            name: name,
            createdAt: Date(),
            members: members,
            shareRecordName: nil,
            ownerIsCurrentUser: false,
            zoneName: zoneName,
            ownerUserRecordName: ownerUserRecordName
        )
    }
}

/// Top-level file (households.json) listing all known households and the active one.
struct HouseholdIndex: Codable {
    var households: [Household]
    var activeHouseholdId: UUID
    var schemaVersion: Int

    static let currentSchemaVersion = 3

    var activeHousehold: Household? {
        households.first { $0.id == activeHouseholdId }
    }
}
