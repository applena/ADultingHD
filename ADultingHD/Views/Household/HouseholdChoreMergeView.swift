import SwiftUI

/// Shared by onboarding and the recovery action for an already joined home.
struct HouseholdChoreSourcePicker: View {
    let sources: [Household]
    @Binding var selection: UUID?
    var emptyTitle = "Keep my homes separate"
    var accessibilityID = "household-chore-source"

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Bring chores from", selection: $selection) {
                    Text(emptyTitle).tag(UUID?.none)
                    ForEach(sources) { source in
                        Text(source.name).tag(UUID?.some(source.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier(accessibilityID)
                Text("Only shared chores are copied. Personal tasks stay private, and your original home stays available. Existing destination chores keep their edits. Members and completion history are not copied. Supply stock stays on your devices.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct HouseholdChoreMergeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    let destination: Household
    @State private var sourceID: UUID?
    private enum MergeState: Equatable {
        case ready, merging, complete, failed(String)
    }
    @State private var state = MergeState.ready
    private var isMerging: Bool { state == .merging }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Bring shared chores into \(destination.name).")
                    if state == .complete {
                        Label("Your shared chores are now in \(destination.name).", systemImage: "checkmark.circle.fill")
                            .accessibilityIdentifier("household-merge-success")
                    } else {
                        HouseholdChoreSourcePicker(
                            sources: dataStore.householdMergeSources(excluding: destination.id),
                            selection: $sourceID
                        )
                        .disabled(isMerging)
                        if case .failed(let errorMessage) = state {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                        Button(isMerging ? "Merging chores…" : "Merge shared chores") {
                            guard let sourceID else { return }
                            state = .merging
                            Task {
                                do {
                                    try await dataStore.mergeChores(from: sourceID, into: destination.id)
                                    state = .complete
                                } catch {
                                    state = .failed(error.localizedDescription)
                                }
                            }
                        }
                        .disabled(sourceID == nil || isMerging || dataStore.isJoiningHousehold)
                        .accessibilityIdentifier("household-merge-submit")
                    }
                }
            }
            .navigationTitle("Bring your chores")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(state == .complete ? "Done" : "Cancel") { dismiss() }
                        .disabled(isMerging)
                }
            }
            .interactiveDismissDisabled(isMerging)
        }
    }
}
