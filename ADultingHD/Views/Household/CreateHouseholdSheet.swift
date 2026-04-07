import SwiftUI

/// Modal for naming and creating a new household. Used by both
/// `HouseholdSwitcher` and `HouseholdListView`.
struct CreateHouseholdSheet: View {
    @Environment(DataStore.self) private var dataStore
    @Binding var isPresented: Bool
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New Household") {
                    TextField("Name", text: $name)
                }
                Text("Each household has its own task list and supply stock. Your XP, level, and streak are shared across every household you manage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("Add Household")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        name = ""
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task {
                            await dataStore.createHousehold(name: trimmed)
                            name = ""
                            isPresented = false
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 280)
        #endif
    }
}
