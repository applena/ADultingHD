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
    @State private var scheduledWeekdays: Set<Int>
    @State private var scheduledDayOfMonth: Int
    @State private var scheduledMonth: Int
    @State private var checklist: [ChecklistItem]
    @State private var expandedChecklistId: UUID?

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
        let initialFrequency = existingTask?.frequency ?? .weekly
        _frequency = State(initialValue: initialFrequency)
        _estimatedMinutes = State(initialValue: existingTask?.estimatedMinutes ?? 15)
        _difficulty = State(initialValue: existingTask?.difficulty ?? .medium)
        _suppliesText = State(initialValue: existingTask?.supplies.joined(separator: "\n") ?? "")
        _scheduledWeekdays = State(initialValue: Set(existingTask?.scheduledWeekdays ?? []))
        _scheduledDayOfMonth = State(initialValue: existingTask?.scheduledDayOfMonth ?? 1)
        _scheduledMonth = State(initialValue: existingTask?.scheduledMonth ?? 1)
        _checklist = State(initialValue: existingTask?.checklist ?? [])
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
                    .onChange(of: frequency) { _, new in
                        applyScheduleDefaults(for: new)
                    }

                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { diff in
                            Label(diff.label, systemImage: diff.icon).tag(diff)
                        }
                    }

                    Stepper("Estimated: \(estimatedMinutes) min", value: $estimatedMinutes, in: 1...480, step: 5)
                }

                SchedulePickerSection(
                    frequency: frequency,
                    weekdays: $scheduledWeekdays,
                    dayOfMonth: $scheduledDayOfMonth,
                    month: $scheduledMonth
                )

                Section("Supplies (one per line)") {
                    TextField("e.g. Sponge\nDish soap", text: $suppliesText, axis: .vertical)
                        .lineLimit(3...6)
                }

                checklistSection

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

    private var checklistSection: some View {
        Section {
            ForEach($checklist) { $item in
                checklistRow(item: $item)
            }
            .onDelete { indexSet in
                checklist.remove(atOffsets: indexSet)
            }
            .onMove { from, to in
                checklist.move(fromOffsets: from, toOffset: to)
            }
            Button {
                let new = ChecklistItem(text: "")
                checklist.append(new)
                expandedChecklistId = new.id
            } label: {
                Label("Add Step", systemImage: "plus.circle")
            }
        } header: {
            Text("Checklist")
        } footer: {
            Text("Optional step-by-step instructions the user checks off while completing the task.")
                .font(.caption)
        }
    }

    private func checklistRow(item: Binding<ChecklistItem>) -> some View {
        let isExpanded = expandedChecklistId == item.wrappedValue.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Step", text: item.text)
                Button {
                    expandedChecklistId = isExpanded ? nil : item.wrappedValue.id
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "text.bubble")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if isExpanded {
                TextField("Instructions (optional)", text: item.instructions, axis: .vertical)
                    .font(.caption)
                    .lineLimit(2...6)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyScheduleDefaults(for freq: TaskFrequency) {
        if freq.weekdayCount > 0, scheduledWeekdays.count != freq.weekdayCount {
            scheduledWeekdays = freq.weekdayCount == 2 ? [2, 5] : [2]
        }
        if freq.usesDayOfMonth, scheduledDayOfMonth < 1 || scheduledDayOfMonth > 28 {
            scheduledDayOfMonth = 1
        }
        if freq == .yearly, scheduledMonth < 1 || scheduledMonth > 12 {
            scheduledMonth = 1
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
        task.checklist = checklist.compactMap { item in
            let trimmed = item.text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return ChecklistItem(
                id: item.id,
                text: trimmed,
                instructions: item.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if frequency.weekdayCount > 0 {
            task.scheduledWeekdays = scheduledWeekdays.sorted()
            task.scheduledDayOfMonth = nil
            task.scheduledMonth = nil
        } else if frequency.usesDayOfMonth {
            task.scheduledWeekdays = []
            task.scheduledDayOfMonth = scheduledDayOfMonth
            task.scheduledMonth = frequency == .yearly ? scheduledMonth : nil
        } else {
            task.scheduledWeekdays = []
            task.scheduledDayOfMonth = nil
            task.scheduledMonth = nil
        }

        Task {
            await onSave(task)
            dismiss()
        }
    }
}

// MARK: - Shared Schedule Picker

struct SchedulePickerSection: View {
    let frequency: TaskFrequency
    @Binding var weekdays: Set<Int>
    @Binding var dayOfMonth: Int
    @Binding var month: Int

    var body: some View {
        if frequency.weekdayCount > 0 {
            Section(frequency.weekdayCount == 1 ? "Day of Week" : "Days of Week") {
                weekdayChips
                if frequency.weekdayCount == 2 {
                    Text("Pick 2 days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if frequency == .yearly {
            Section("Month and Day") {
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) { m in
                        Text(shortMonthName(m)).tag(m)
                    }
                }
                Stepper("Day \(dayOfMonth)", value: $dayOfMonth, in: 1...28)
            }
        } else if frequency.usesDayOfMonth {
            Section("Day of Month") {
                Stepper("Day \(dayOfMonth)", value: $dayOfMonth, in: 1...28)
            }
        }
    }

    private var weekdayChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
            ForEach(Weekday.allCases) { day in
                FilterChip(
                    label: day.shortLabel,
                    isSelected: weekdays.contains(day.rawValue)
                ) {
                    toggleWeekday(day.rawValue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func toggleWeekday(_ raw: Int) {
        if weekdays.contains(raw) {
            weekdays.remove(raw)
            return
        }
        let limit = frequency.weekdayCount
        if limit == 1 {
            weekdays = [raw]
        } else if weekdays.count < limit {
            weekdays.insert(raw)
        } else if let drop = weekdays.min() {
            weekdays.remove(drop)
            weekdays.insert(raw)
        }
    }
}
