import SwiftUI

/// An incoming invitation takes over the root page until the user decides.
/// The source household is captured explicitly rather than inferred at save.
struct HouseholdInvitationView: View {
    @Environment(DataStore.self) private var dataStore
    let invitation: DataStore.PendingHouseholdInvitation

    @State private var wantsMerge = false
    @State private var mergeSourceID: UUID?
    @State private var errorMessage: String?

    private var mergeSources: [Household] { dataStore.invitationMergeSources }
    private var isExistingHousehold: Bool { invitation.existingHouseholdID != nil }
    private var selectedSource: Household? { mergeSources.first { $0.id == mergeSourceID } }
    private var canAccept: Bool {
        !dataStore.isJoiningHousehold && (!wantsMerge || selectedSource != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    header
                    if isExistingHousehold {
                        Text("This household is already in your list. Open it, or bring shared chores from another home you own.")
                            .foregroundStyle(.secondary)
                    }
                    if !isExistingHousehold || !mergeSources.isEmpty {
                        choices
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("household-invitation-error")
                    }
                    actions
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background { ScreenBackground() }
            .navigationTitle("Household invitation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .interactiveDismissDisabled(dataStore.isJoiningHousehold)
        }
        .accessibilityIdentifier("household-invitation-page")
        .onChange(of: dataStore.invitationMergeSources.map(\.id)) { _, ids in
            if let mergeSourceID, !ids.contains(mergeSourceID) {
                self.mergeSourceID = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.hearthGold)
                .accessibilityHidden(true)
            Text(invitation.householdName)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("household-invitation-name")
            Text(invitation.inviterName.map { "\($0) invited you to share this household." }
                ?? "You’ve been invited to share this household.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How would you like to join?")
                .font(.headline)
            choice(
                title: isExistingHousehold ? "Open this household" : "Add this household",
                detail: "Keep your households separate. Switch between them whenever you need.",
                selected: !wantsMerge,
                identifier: "household-invitation-add"
            ) { wantsMerge = false }

            if !mergeSources.isEmpty {
                choice(
                    title: "Merge chores into this household",
                    detail: "Bring shared chores and your local supply checklist from a household you own.",
                    selected: wantsMerge,
                    identifier: "household-invitation-merge"
                ) {
                    wantsMerge = true
                    if mergeSourceID == nil { mergeSourceID = mergeSources.first?.id }
                }
                if wantsMerge {
                    HouseholdChoreSourcePicker(
                        sources: mergeSources, selection: $mergeSourceID,
                        emptyTitle: "Choose a household",
                        accessibilityID: "household-invitation-merge-source"
                    )
                    .card()
                }
            }
        }
        .disabled(dataStore.isJoiningHousehold)
    }

    private func choice(
        title: String,
        detail: String,
        selected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier(identifier)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: accept) {
                HStack(spacing: 10) {
                    if dataStore.isJoiningHousehold { ProgressView().tint(.white) }
                    Text(dataStore.isJoiningHousehold ? "Joining household…" : acceptTitle)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
                .adventurePrimaryAction()
            }
            .buttonStyle(.plain)
            .disabled(!canAccept)
            .opacity(canAccept || dataStore.isJoiningHousehold ? 1 : 0.5)
            .accessibilityIdentifier("household-invitation-accept")

            Button("Not now") { dataStore.declinePendingHouseholdInvitation() }
                .frame(minHeight: 44)
                .disabled(dataStore.isJoiningHousehold)
                .accessibilityIdentifier("household-invitation-decline")
        }
    }

    private var acceptTitle: String {
        if errorMessage != nil { return "Try again" }
        if isExistingHousehold && !wantsMerge { return "Open household" }
        return wantsMerge ? "Join and merge chores" : "Join household"
    }

    private func accept() {
        guard canAccept else { return }
        let sourceID = wantsMerge ? selectedSource?.id : nil
        errorMessage = nil
        Task {
            do {
                try await dataStore.acceptPendingHouseholdInvitation(id: invitation.id, mergeFrom: sourceID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
