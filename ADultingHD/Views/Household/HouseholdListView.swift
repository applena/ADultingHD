import SwiftUI

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
    @State private var deletionWasLeave = false
    @State private var showCreateSheet = false
    @State private var sharePresentation = HouseholdSharePresentation()

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
                        Task { await sharePresentation.prepare(using: dataStore) }
                    } label: {
                        HStack {
                            if sharePresentation.isPreparing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                            }
                            Text(sharePresentation.isPreparing ? "Preparing…" : "Invite someone to this household")
                        }
                    }
                    .disabled(sharePresentation.isPreparing)
                    if let errorMessage = sharePresentation.errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                            if let errorCode = sharePresentation.errorCode {
                                Text("Error code: \(errorCode)")
                                    .font(.caption2.monospaced().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Button {
                                    sharePresentation.copyErrorDetails()
                                } label: {
                                    Label("Copy error details", systemImage: "doc.on.doc")
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    Text("Send an invitation to \(dataStore.activeHousehold.name). The recipient can review the household, then choose to add it or bring chores from a household they own.")
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
            deleteTarget.map { "\($0.ownerIsCurrentUser ? "Delete" : "Leave") \"\($0.name)\"?" } ?? "Remove household?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button(target.ownerIsCurrentUser ? "Delete Household" : "Leave Household", role: .destructive) {
                deletionWasLeave = !target.ownerIsCurrentUser
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
        .alert(deletionWasLeave ? "Couldn't leave household" : "Couldn't delete household", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "The household could not be cleaned up.")
        }
        .sheet(item: sharePresentation.payloadBinding) { payload in
            CloudShareSheet(
                share: payload.share,
                container: payload.container,
                householdName: payload.householdName,
                onDismiss: sharePresentation.dismiss
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
                        Label(
                            household.ownerIsCurrentUser ? "Delete Household" : "Leave Household",
                            systemImage: household.ownerIsCurrentUser ? "trash" : "rectangle.portrait.and.arrow.right"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Options for \(household.name)")
        }
        .padding(.vertical, 4)
    }
}
