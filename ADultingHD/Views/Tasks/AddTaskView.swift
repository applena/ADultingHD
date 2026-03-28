import SwiftUI

struct AddTaskView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TaskFormView(title: "New Task", buttonLabel: "Add") { task in
            await dataStore.addCustomTask(task)
        }
    }
}

struct EditTaskView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    let task: HouseholdTask

    var body: some View {
        TaskFormView(title: "Edit Task", buttonLabel: "Save", existingTask: task) { updated in
            await dataStore.updateTask(updated)
        }
    }
}

// MARK: - Shared Task Form

private struct TaskFormView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let buttonLabel: String
    let onSave: (HouseholdTask) async -> Void

    @State private var name: String
    @State private var description: String
    @State private var category: TaskCategory
    @State private var frequency: TaskFrequency
    @State private var estimatedMinutes: Int
    @State private var difficulty: Difficulty
    @State private var suppliesText: String

    private let existingTask: HouseholdTask?

    init(title: String, buttonLabel: String, existingTask: HouseholdTask? = nil,
         onSave: @escaping (HouseholdTask) async -> Void) {
        self.title = title
        self.buttonLabel = buttonLabel
        self.existingTask = existingTask
        self.onSave = onSave
        _name = State(initialValue: existingTask?.name ?? "")
        _description = State(initialValue: existingTask?.description ?? "")
        _category = State(initialValue: existingTask?.category ?? .general)
        _frequency = State(initialValue: existingTask?.frequency ?? .weekly)
        _estimatedMinutes = State(initialValue: existingTask?.estimatedMinutes ?? 15)
        _difficulty = State(initialValue: existingTask?.difficulty ?? .medium)
        _suppliesText = State(initialValue: existingTask?.supplies.joined(separator: "\n") ?? "")
    }

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
                    HStack {
                        Text("XP Reward")
                        Spacer()
                        Text("+\(HouseholdTask.computeXP(difficulty: difficulty, frequency: frequency, estimatedMinutes: estimatedMinutes)) XP")
                            .bold()
                            .foregroundStyle(Theme.xpGold)
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(buttonLabel) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let supplies = HouseholdTask.parseSupplies(from: suppliesText)

        var task = existingTask ?? HouseholdTask(
            id: UUID(), name: "", description: "", category: .general,
            frequency: .weekly, estimatedMinutes: 15, difficulty: .medium,
            supplies: [], isActive: true
        )
        task.name = name.trimmingCharacters(in: .whitespaces)
        task.description = description.trimmingCharacters(in: .whitespaces)
        task.category = category
        task.frequency = frequency
        task.estimatedMinutes = estimatedMinutes
        task.difficulty = difficulty
        task.supplies = supplies

        Task {
            await onSave(task)
            dismiss()
        }
    }
}
