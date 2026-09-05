#if DEBUG
import SwiftUI

/// A launch-only fixture for screenshots and UI tests. It exercises the real
/// invitation transaction against temporary files and an in-memory household.
@MainActor
enum HouseholdInvitationPreview {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-household-invitation-preview")
    }

    private static var didStage = false
    private static let info = HouseholdShareInfo(
        shareRecordName: "preview-share",
        zoneName: "preview-maple-home",
        ownerUserRecordName: "preview-owner-alex",
        title: "Maple Home",
        inviterName: "Alex"
    )

    static func makeDataStore() -> DataStore {
        guard isEnabled else { return DataStore() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HouseholdInvitationPreview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let session = Session(failOnce: ProcessInfo.processInfo.arguments.contains("-household-invitation-fail-once"))
        let client = HouseholdInvitationClient(
            prepare: {},
            fetch: { _ in try session.fetch() },
            upload: { tasks, _, _ in session.add(tasks) }
        )
        return DataStore(store: TaskStore(directory: directory), invitationClient: client)
    }

    static func stageIfRequested(in dataStore: DataStore) {
        guard isEnabled, !didStage else { return }
        didStage = true
        dataStore.stageHouseholdInvitation(info: info) { info }
    }

    private final class Session {
        let failOnce: Bool
        var fetchCount = 0
        var tasks: [HouseholdTask] = [HouseholdTask(
            id: UUID(), name: "Water the maple tree", description: "Give the young tree a slow watering.",
            category: .outdoor, frequency: .weekly, estimatedMinutes: 10,
            difficulty: .easy, supplies: ["Watering can"], isActive: true
        )]
        var owner: UserProfile = {
            var profile = UserProfile()
            profile.name = "Alex"
            return profile
        }()

        init(failOnce: Bool) { self.failOnce = failOnce }

        func fetch() throws -> CloudKitPayload {
            fetchCount += 1
            if failOnce && fetchCount == 1 { throw PreviewError.interrupted }
            return CloudKitPayload(
                tasks: tasks, completions: [], profiles: [owner],
                inviterName: "Alex", personalTaskIDs: []
            )
        }

        func add(_ additions: [HouseholdTask]) {
            let knownIDs = Set(tasks.map(\.id))
            tasks.append(contentsOf: additions.filter { !knownIDs.contains($0.id) })
        }
    }

    private enum PreviewError: LocalizedError {
        case interrupted
        var errorDescription: String? { "The connection was interrupted. Try joining again." }
    }
}

struct HouseholdInvitationPreviewAppearance: ViewModifier {
    func body(content: Content) -> some View {
        if HouseholdInvitationPreview.isEnabled {
            content
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-household-invitation-dark") ? .dark : .light)
                .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("-household-invitation-accessibility") ? .accessibility3 : .large)
        } else {
            content
        }
    }
}
#endif
