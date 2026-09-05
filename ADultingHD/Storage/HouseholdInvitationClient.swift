import CloudKit

/// Cloud boundaries for invitation transactions. The production flow and its
/// failure/retry tests use the same DataStore transaction and real file store.
@MainActor
struct HouseholdInvitationClient {
    var prepare: () async throws -> Void
    var fetch: (Household) async throws -> CloudKitPayload
    var upload: ([HouseholdTask], UserProfile, Household) async throws -> Void

    static var live: Self {
        let sync = CloudKitSync.shared
        return Self(
            prepare: {
                await sync.setup()
                guard sync.isAvailable else {
                    throw CloudKitSyncError.iCloudUnavailable(status: sync.syncError ?? "Sign in to iCloud and try again.")
                }
            },
            fetch: { try await sync.pullAllRequired(for: $0) },
            upload: { tasks, profile, household in
                try await sync.uploadInitialShareSnapshot(
                    tasks: tasks, profile: profile, completions: [], members: [], household: household
                )
            }
        )
    }
}
