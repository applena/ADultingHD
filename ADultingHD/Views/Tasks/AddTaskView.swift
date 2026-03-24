import SwiftUI

struct AddTaskView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var category: TaskCategory = .general
    @State private var frequency: TaskFrequency = .weekly
    @State private var estimatedMinutes = 15
    @State private var difficulty: Difficulty = .medium
    @State private var suppliesText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Info") {
                    TextField("Task Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(TaskCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }

                    Picker("Frequency", selection: $frequency) {
                        ForEach(TaskFrequency.allCases) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }

                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { diff in
                            Label(diff.label, systemImage: diff.icon).tag(diff)
                        }
                    }

                    Stepper("Estimated: \(estimatedMinutes) min", value: $estimatedMinutes, in: 1...480, step: 5)
                }

                Section("Supplies (one per line)") {
                    TextField("e.g. Sponge\nDish soap", text: $suppliesText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    let xp = computeXP()
                    HStack {
                        Text("XP Reward")
                        Spacer()
                        Text("+\(xp) XP")
                            .bold()
                            .foregroundStyle(Theme.xpGold)
                    }
                }
            }
            .navigationTitle("New Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addTask()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func computeXP() -> Int {
        let baseXP = difficulty.rawValue * 10
        let frequencyMultiplier = max(1, frequency.days / 7)
        let timeBonus = estimatedMinutes / 10
        return baseXP + (frequencyMultiplier * 5) + (timeBonus * 2)
    }

    private func addTask() {
        let supplies = suppliesText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let task = HouseholdTask(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            category: category,
            frequency: frequency,
            estimatedMinutes: estimatedMinutes,
            difficulty: difficulty,
            supplies: supplies,
            isActive: true
        )

        Task {
            await dataStore.addCustomTask(task)
            dismiss()
        }
    }
}
