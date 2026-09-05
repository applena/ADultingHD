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
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    let title: String
    let buttonLabel: String
    let onSave: (HouseholdTask) async -> Void

    @State private var name: String
    @State private var description: String
    @State private var room: String
    @State private var frequency: TaskFrequency
    @State private var estimatedMinutes: Int
    @State private var difficulty: Difficulty
    @State private var suppliesText: String
    @State private var scheduledWeekdays: Set<Int>
    @State private var scheduledDayOfMonth: Int
    @State private var scheduledMonth: Int
    @State private var hasOneTimeDueDate: Bool
    @State private var oneTimeDueDate: Date
    @State private var checklist: [ChecklistItem]
    @State private var expandedChecklistId: UUID?
    @State private var assigneeId: UUID?
    @State private var isPersonal: Bool
    @State private var isSaving = false

    private let existingTask: HouseholdTask?

    init(title: String, buttonLabel: String, existingTask: HouseholdTask? = nil,
         onSave: @escaping (HouseholdTask) async -> Void) {
        self.title = title
        self.buttonLabel = buttonLabel
        self.existingTask = existingTask
        self.onSave = onSave
        _name = State(initialValue: existingTask?.name ?? "")
        _description = State(initialValue: existingTask?.description ?? "")
        _room = State(initialValue: existingTask?.room ?? "")
        let initialFrequency = existingTask?.frequency ?? .unscheduled
        _frequency = State(initialValue: initialFrequency)
        _estimatedMinutes = State(initialValue: existingTask?.estimatedMinutes ?? 15)
        _difficulty = State(initialValue: existingTask?.difficulty ?? .medium)
        _suppliesText = State(initialValue: existingTask?.supplies.joined(separator: "\n") ?? "")
        let initialWeekdays = existingTask?.scheduledWeekdays ?? []
        _scheduledWeekdays = State(initialValue: Set(initialWeekdays.isEmpty ? initialFrequency.defaultWeekdays : initialWeekdays))
        _scheduledDayOfMonth = State(initialValue: existingTask?.scheduledDayOfMonth ?? 1)
        _scheduledMonth = State(initialValue: existingTask?.scheduledMonth ?? 1)
        _hasOneTimeDueDate = State(initialValue: initialFrequency == .unscheduled && existingTask?.scheduledOverrideDate != nil)
        _oneTimeDueDate = State(initialValue: existingTask?.scheduledOverrideDate ?? Date())
        _checklist = State(initialValue: existingTask?.checklist ?? [])
        _assigneeId = State(initialValue: existingTask?.defaultAssigneeId)
        _isPersonal = State(initialValue: existingTask?.isPersonal ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Info") {
                    TextField("Task Name", text: $name)
                        .accessibilityIdentifier("task-form-name")
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Details") {
                    TextField("Room or context (optional)", text: $room)
                        .textContentType(.location)
                    if roomNameIsReserved {
                        Text("“No Room” is reserved for tasks without a room. Choose another name or leave this blank.")
                            .font(.caption)
                            .foregroundStyle(Theme.warningRed)
                    }

                    Picker("Schedule", selection: $frequency) {
                        ForEach(TaskFrequency.allCases) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                    .accessibilityIdentifier("task-form-schedule")
                    .onChange(of: frequency) { _, new in
                        applyScheduleDefaults(for: new)
                    }

                    if frequency == .unscheduled {
                        Toggle("Set a one-time due date", isOn: $hasOneTimeDueDate)
                        if hasOneTimeDueDate {
                            DatePicker("Due", selection: $oneTimeDueDate, displayedComponents: .date)
                        }
                    }

                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { diff in
                            Label(diff.label, systemImage: diff.icon).tag(diff)
                        }
                    }

                    Stepper("Estimated: \(estimatedMinutes) min", value: $estimatedMinutes, in: 1...480, step: 5)

                    if dataStore.hasMultipleAssignees && !isPersonal {
                        AssigneePicker(profiles: dataStore.householdProfiles, selection: $assigneeId)
                    }
                }

                Section("Task Scope") {
                    if canChangePersonalScope {
                        Toggle(isOn: $isPersonal) {
                            Label("Personal task", systemImage: "person.fill")
                        }
                    } else {
                        Label("Personal task", systemImage: "person.fill")
                            .foregroundStyle(.secondary)
                        Text("Only the household owner can make a shared task personal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isPersonal {
                        Text("Only you can complete this task. It won't be shared with household members.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || roomNameIsReserved || !scheduleIsValid || isSaving)
                        .accessibilityIdentifier("task-form-save")
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
        if freq != .unscheduled {
            hasOneTimeDueDate = false
        }
        if freq.weekdayCount > 0, scheduledWeekdays.count != freq.weekdayCount {
            scheduledWeekdays = Set(freq.defaultWeekdays)
        }
        if freq.usesDayOfMonth, scheduledDayOfMonth < 1 || scheduledDayOfMonth > 28 {
            scheduledDayOfMonth = 1
        }
        if freq == .yearly, scheduledMonth < 1 || scheduledMonth > 12 {
            scheduledMonth = 1
        }
    }

    private var canChangePersonalScope: Bool {
        guard let existingTask else { return true }
        return existingTask.isPersonal || dataStore.activeHousehold.ownerIsCurrentUser
    }

    private var roomNameIsReserved: Bool {
        room.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("No Room") == .orderedSame
    }

    private var scheduleIsValid: Bool {
        TaskScheduleValidation.isValid(
            frequency: frequency,
            weekdays: scheduledWeekdays,
            dayOfMonth: scheduledDayOfMonth,
            month: scheduledMonth
        )
    }

    private func save() {
        guard !roomNameIsReserved, scheduleIsValid, !isSaving,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSaving = true
        let supplies = HouseholdTask.parseSupplies(from: suppliesText)

        var task = existingTask ?? HouseholdTask(
            id: UUID(), name: "", description: "", category: .general,
            frequency: .unscheduled, estimatedMinutes: 15, difficulty: .medium,
            supplies: [], isActive: true
        )
        task.name = name.trimmingCharacters(in: .whitespaces)
        task.description = description.trimmingCharacters(in: .whitespaces)
        task.room = HouseholdTask.normalizedRoom(room)
        task.frequency = frequency
        task.estimatedMinutes = estimatedMinutes
        task.difficulty = difficulty
        task.supplies = supplies
        let scopeIsPersonal = canChangePersonalScope ? isPersonal : (existingTask?.isPersonal ?? false)
        task.isPersonal = scopeIsPersonal
        task.defaultAssigneeId = scopeIsPersonal ? dataStore.profile.id : assigneeId
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
        if frequency == .unscheduled {
            task.scheduledOverrideDate = hasOneTimeDueDate
                ? Calendar.current.startOfDay(for: oneTimeDueDate)
                : nil
        }

        Task {
            await onSave(task)
            dismiss()
        }
    }
}

// MARK: - Shared Assignee Picker

/// "Who is this for" picker shared by the task creation/edit form
/// (`TaskFormView`) and the tap-to-edit sheet on `TaskDetailView`
/// (`AssigneePickerSheet`). `nil` selection means "Anyone."
struct AssigneePicker: View {
    let profiles: [UserProfile]
    @Binding var selection: UUID?

    var body: some View {
        Picker("Assignee", selection: $selection) {
            Text("Anyone").tag(UUID?.none)
            ForEach(profiles) { member in
                Text(member.name).tag(UUID?.some(member.id))
            }
        }
    }
}

// MARK: - Shared Schedule Picker

/// Both schedule editors validate the same selection before saving it.
enum TaskScheduleValidation {
    static func isValid(frequency: TaskFrequency, weekdays: Set<Int>, dayOfMonth: Int, month: Int) -> Bool {
        if frequency.weekdayCount > 0 {
            return weekdays.count == frequency.weekdayCount && weekdays.allSatisfy { (1...7).contains($0) }
        }
        if frequency.usesDayOfMonth && !(1...28).contains(dayOfMonth) { return false }
        return frequency != .yearly || (1...12).contains(month)
    }
}

struct SchedulePickerSection: View {
    let frequency: TaskFrequency
    @Binding var weekdays: Set<Int>
    @Binding var dayOfMonth: Int
    @Binding var month: Int

    var body: some View {
        if frequency.weekdayCount > 0 {
            Section(frequency.weekdayCount == 1 ? "Day of Week" : "Days of Week") {
                weekdayChips
                if weekdays.count != frequency.weekdayCount {
                    Text(frequency.weekdayCount == 1 ? "Pick one day to continue." : "Pick two days to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
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
                .accessibilityIdentifier("schedule-weekday-\(day.rawValue)")
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
