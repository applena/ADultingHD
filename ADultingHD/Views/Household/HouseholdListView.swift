import SwiftUI
import CloudKit

/// Pro-gated management screen for listing and managing all households the
/// device user owns or has joined. Supports rename, delete (refuses the last
/// remaining household), switching active, and creating new ones.
struct HouseholdListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager

    @State private var renameTarget: Household?
    @State private var renameText: String = ""
    @State private var deleteTarget: Household?
    @State private var deleteError: String?
    @State private var showCreateSheet = false
    @State private var inviteError: String?
    @State private var isGeneratingInvite = false
    @State private var shareSheetPayload: ShareSheetPayload?

    /// Wraps the CKShare + container so we can present `.sheet(item:)`
    /// (which requires Identifiable) in a single binding update.
    private struct ShareSheetPayload: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
        let householdName: String
    }

    var body: some View {
        let households = dataStore.listHouseholds()
        let canDelete = households.count > 1

        return List {
            Section("Households") {
                ForEach(households) { household in
                    householdRow(household, canDelete: canDelete)
                }
            }

            Section {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create New Household", systemImage: "plus.circle.fill")
                }
            }

            if Features.cloudKitSharing {
                Section("Invite Collaborators") {
                    Button {
                        Task { await presentShareSheet() }
                    } label: {
                        HStack {
                            if isGeneratingInvite {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                            }
                            Text(isGeneratingInvite ? "Preparing…" : "Invite someone to this household")
                        }
                    }
                    .disabled(isGeneratingInvite)
                    if let inviteError {
                        Text(inviteError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Pick contacts by email or phone, or send via Messages, Mail, or AirDrop. They'll tap the invite and land straight in your household.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Section("Invite Collaborators") {
                    Label("Coming soon", systemImage: "clock.badge")
                        .foregroundStyle(.secondary)
                    Text("Cross-device household sharing is in development. For now, each device manages its own household list locally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Households")
        .sheet(isPresented: $showCreateSheet) {
            CreateHouseholdSheet(isPresented: $showCreateSheet)
        }
        .alert("Rename household", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        ), presenting: renameTarget) { target in
            TextField("Name", text: $renameText)
            Button("Save") {
                Task { await dataStore.renameHousehold(target.id, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            deleteTarget.map { "Delete \"\($0.name)\"?" } ?? "Delete household?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await dataStore.deleteHousehold(target.id)
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { target in
            if target.ownerIsCurrentUser {
                Text("This permanently deletes the household's data and removes every collaborator from it. Your XP, level, and streak are unaffected.")
            } else {
                Text("This removes your access to the shared household and deletes its local data on this device. The owner's household is unchanged.")
            }
        }
        .alert("Couldn't delete household", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "The household could not be cleaned up.")
        }
        .sheet(item: $shareSheetPayload) { payload in
            CloudShareSheet(
                share: payload.share,
                container: payload.container,
                householdName: payload.householdName,
                onDismiss: { shareSheetPayload = nil }
            )
        }
    }

    private func householdRow(_ household: Household, canDelete: Bool) -> some View {
        let isActive = household.id == dataStore.activeHouseholdId
        return HStack(spacing: 12) {
            Image(systemName: household.ownerIsCurrentUser ? "house.fill" : "person.2.wave.2.fill")
                .foregroundStyle(isActive ? Theme.accent : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(household.name)
                        .font(.subheadline.weight(.semibold))
                    if isActive {
                        Text("ACTIVE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.accent, in: Capsule())
                    }
                    if !household.ownerIsCurrentUser {
                        Text("SHARED")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.levelPurple, in: Capsule())
                    }
                }
                Text("\(household.members.count) \(household.members.count == 1 ? "member" : "members")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                if !isActive {
                    Button {
                        Task { await dataStore.switchHousehold(to: household.id) }
                    } label: {
                        Label("Switch to this household", systemImage: "arrow.left.arrow.right")
                    }
                }
                Button {
                    renameText = household.name
                    renameTarget = household
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                if canDelete {
                    Button(role: .destructive) {
                        deleteTarget = household
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func presentShareSheet() async {
        isGeneratingInvite = true
        defer { isGeneratingInvite = false }
        inviteError = nil
        do {
            let (share, container) = try await dataStore.prepareHouseholdShare()
            shareSheetPayload = ShareSheetPayload(
                share: share,
                container: container,
                householdName: dataStore.activeHousehold.name
            )
        } catch {
            inviteError = error.localizedDescription
        }
    }
}
