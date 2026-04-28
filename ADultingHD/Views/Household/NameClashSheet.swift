import SwiftUI

struct NameClashSheet: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    let clash: DataStore.NameClash
    @State private var newName: String = ""

    private var trimmed: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var takenLowercased: Set<String> {
        Set(clash.existingNames.map { $0.lowercased() })
    }

    private var isDuplicate: Bool {
        !trimmed.isEmpty && takenLowercased.contains(trimmed.lowercased())
    }

    private var canSave: Bool {
        !trimmed.isEmpty && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 50))
                        .foregroundStyle(Theme.streakOrange)
                        .padding(.top, 16)

                    Text("Pick a unique name")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("Someone in \(clash.householdName) is already named \"\(clash.currentName)\". Choose a new name for the leaderboard.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    TextField("Your household name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        #if os(iOS)
                        .textContentType(.nickname)
                        .autocorrectionDisabled(true)
                        #endif

                    if isDuplicate {
                        Label("That name is already taken in this household", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !clash.existingNames.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Already used:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(clash.existingNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task {
                            await dataStore.resolveNameClash(with: trimmed)
                            dismiss()
                        }
                    } label: {
                        Text("Save")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                            .opacity(canSave ? 1.0 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
                .padding(24)
                .frame(maxWidth: 420)
            }
            .interactiveDismissDisabled()
        }
    }
}
