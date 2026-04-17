import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Pro-gated management screen for listing and managing all households the
/// device user owns or has joined. Supports rename, delete (refuses the last
/// remaining household), switching active, and creating new ones.
struct HouseholdListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager

    @State private var renameTarget: Household?
    @State private var renameText: String = ""
    @State private var deleteTarget: Household?
    @State private var showCreateSheet = false
    @State private var inviteURL: URL?
    @State private var inviteError: String?
    @State private var isGeneratingInvite = false

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
                        Task { await generateInvite() }
                    } label: {
                        HStack {
                            if isGeneratingInvite {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text(isGeneratingInvite ? "Generating…" : "Invite someone to this household")
                        }
                    }
                    .disabled(isGeneratingInvite)
                    if let inviteError {
                        Text(inviteError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let url = inviteURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Invite link")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(url.absoluteString)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                            HStack {
                                #if os(iOS)
                                ShareLink(item: url) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                #endif
                                Button {
                                    copyInviteURL(url)
                                } label: {
                                    Label("Copy Link", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Text("Share the generated link via Messages, Mail, or AirDrop. They'll accept in their own ADultingHD app to join.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Invite Collaborators") {
                    Label("Coming soon", systemImage: "clock.badge")
                        .foregroundStyle(.secondary)
                    Text("Cross-device household sharing is in development. For now, each device manages its own household list locally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Task { await dataStore.deleteHousehold(target.id) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text("This deletes the household's task list and supply stock. Members will be removed. Your XP, level, and streak are unaffected.")
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

    private func generateInvite() async {
        isGeneratingInvite = true
        defer { isGeneratingInvite = false }
        inviteError = nil
        let result = await dataStore.generateHouseholdInvite()
        inviteError = result.errorMessage
        if let url = result.url {
            inviteURL = url
        }
    }

    private func copyInviteURL(_ url: URL) {
        #if os(iOS)
        UIPasteboard.general.string = url.absoluteString
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
    }
}
