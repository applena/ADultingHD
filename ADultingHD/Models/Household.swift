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

    /// Convenience constructor for a locally-owned household. Defaults zone
    /// to the legacy shared zone when `id` is omitted (callers pass an
    /// explicit zone for newly-created post-migration households).
    static func newLocal(
        id: UUID = UUID(),
        name: String,
        members: [UserProfile],
        zoneName: String = ZoneName.household
    ) -> Household {
        Household(
            id: id,
            name: name,
            createdAt: Date(),
            members: members,
            shareRecordName: nil,
            ownerIsCurrentUser: true,
            zoneName: zoneName
        )
    }
}

/// Top-level file (households.json) listing all known households and the active one.
struct HouseholdIndex: Codable {
    var households: [Household]
    var activeHouseholdId: UUID
    var schemaVersion: Int

    static let currentSchemaVersion = 2

    var activeHousehold: Household? {
        households.first { $0.id == activeHouseholdId }
    }
}
