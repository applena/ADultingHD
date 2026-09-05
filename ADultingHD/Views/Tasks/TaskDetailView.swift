import SwiftUI

struct TaskDetailView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    let task: HouseholdTask
    @State private var showComplete = false
    @State private var showFrequencyPicker = false
    @State private var showAssigneePicker = false
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false

    private var currentTask: HouseholdTask {
        dataStore.tasks.first { $0.id == task.id } ?? task
    }

    private var recentCompletions: [TaskCompletion] {
        Array(dataStore.completions.filter { $0.taskId == task.id }.prefix(20))
    }

    var body: some View {
        let task = currentTask
        let completions = recentCompletions
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                headerCard(task)
                detailsCard(task)

                if !task.checklist.isEmpty {
                    checklistCard(task)
                }

                if !task.supplies.isEmpty {
                    suppliesCard(task)
                }

                if task.isActive {
                    completeButton(task)
                }

                if !completions.isEmpty {
                    historySection(completions)
                }
            }
            .padding()
        }
        .navigationTitle(task.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showEditSheet = true } label: {
                        Label("Edit Task", systemImage: "pencil")
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditTaskView(task: currentTask)
        }
        .confirmationDialog("Delete Task?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    await dataStore.deleteTask(currentTask)
                    dismiss()
                }
            }
        } message: {
            Text("This will permanently delete \"\(currentTask.name)\" and cannot be undone.")
        }
    }

    // MARK: - Header

    private func headerCard(_ task: HouseholdTask) -> some View {
        let status = task.dueStatus()
        return VStack(spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: task.category.icon)
                    .font(.largeTitle)
                    .foregroundStyle(Theme.roomColor(task.room))

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(task.roomDisplayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if task.isPersonal {
                            Label("Personal", systemImage: "person.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("+\(task.xpReward) XP")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.xpGold)
                    if status.isOverdue {
                        Text("\(status.daysOverdue)D OVERDUE")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.overdueRed, in: Capsule())
                    } else if status.isDue {
                        Text("DUE")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.streakOrange, in: Capsule())
                    }
                }
            }

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card()
    }

    // MARK: - Details

    private func frequencyDisplay(for task: HouseholdTask) -> String {
        if let summary = task.scheduleSummary {
            if task.frequency == .unscheduled { return "One time · \(summary)" }
            return "\(task.frequency.rawValue) · \(summary)"
        }
        return task.frequency.rawValue
    }

    private func assigneeDisplay(for task: HouseholdTask) -> String {
        guard let id = task.defaultAssigneeId else { return "Anyone" }
        return dataStore.householdProfiles.first { $0.id == id }?.name ?? "Anyone"
    }

    private func detailsCard(_ task: HouseholdTask) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Button { showFrequencyPicker = true } label: {
                DetailItem(
                    label: "Schedule",
                    value: frequencyDisplay(for: task),
                    icon: task.frequency.icon
                )
            }
            .buttonStyle(.plain)

            DetailItem(label: "Difficulty", value: task.difficulty.label, icon: task.difficulty.icon)
            DetailItem(label: "Room", value: task.roomDisplayName, icon: task.category.icon)
            DetailItem(label: "Est. Time", value: "\(task.estimatedMinutes) min", icon: "clock")
            DetailItem(
                label: "Scope",
                value: task.isPersonal ? "Personal" : "Household",
                icon: task.isPersonal ? "person.fill" : "person.3"
            )

            if let days = task.daysSinceLastCompleted {
                DetailItem(label: "Last Done", value: "\(days)d ago", icon: "calendar.badge.clock")
            } else {
                DetailItem(label: "Last Done", value: "Never", icon: "calendar.badge.clock")
            }

            if !task.isPersonal && dataStore.hasMultipleAssignees {
                Button { showAssigneePicker = true } label: {
                    DetailItem(label: "Assignee", value: assigneeDisplay(for: task), icon: "person.crop.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .card()
        .sheet(isPresented: $showFrequencyPicker) {
            FrequencyPickerSheet(task: task)
        }
        .sheet(isPresented: $showAssigneePicker) {
            AssigneePickerSheet(task: task)
        }
    }

    // MARK: - Checklist

    private func checklistCard(_ task: HouseholdTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Checklist", systemImage: "checklist")
                .font(.headline)

            ForEach(Array(task.checklist.enumerated()), id: \.element.id) { idx, step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(step.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !step.instructions.isEmpty {
                        Text(step.instructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Supplies

    private func suppliesCard(_ task: HouseholdTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Supplies Needed", systemImage: "cart")
                .font(.headline)

            ForEach(task.supplies, id: \.self) { supply in
                Label(supply, systemImage: "circle.fill")
                    .font(.subheadline)
                    .labelStyle(SupplyLabelStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Complete Button

    private func completeButton(_ task: HouseholdTask) -> some View {
        Button {
            showComplete = true
        } label: {
            Label("Mark Complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.successGreen, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showComplete) {
            CompleteTaskSheet(task: task)
        }
    }

    // MARK: - History

    private func historySection(_ completions: [TaskCompletion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent History", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            ForEach(completions) { completion in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(completion.completedAt, style: .date)
                            .font(.subheadline)
                        Text(completion.completedAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("+\(completion.xpEarned + completion.streakBonus) XP")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.xpGold)
                    }
                    if let notes = completion.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .card()
    }
}

// MARK: - Frequency Picker

struct FrequencyPickerSheet: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    let task: HouseholdTask
    @State private var selected: TaskFrequency
    @State private var weekdays: Set<Int>
    @State private var dayOfMonth: Int
    @State private var month: Int
    @State private var hasOneTimeDueDate: Bool
    @State private var oneTimeDueDate: Date

    init(task: HouseholdTask) {
        self.task = task
        self._selected = State(initialValue: task.frequency)
        let initialWeekdays = task.scheduledWeekdays.isEmpty ? task.frequency.defaultWeekdays : task.scheduledWeekdays
        self._weekdays = State(initialValue: Set(initialWeekdays))
        self._dayOfMonth = State(initialValue: task.scheduledDayOfMonth ?? 1)
        self._month = State(initialValue: task.scheduledMonth ?? 1)
        self._hasOneTimeDueDate = State(initialValue: task.frequency == .unscheduled && task.scheduledOverrideDate != nil)
        self._oneTimeDueDate = State(initialValue: task.scheduledOverrideDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule") {
                    Picker("Schedule", selection: $selected) {
                        ForEach(TaskFrequency.allCases) { freq in
                            Label(freq.rawValue, systemImage: freq.icon).tag(freq)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: selected) { _, new in applyDefaults(for: new) }

                    if selected == .unscheduled {
                        Toggle("Set a one-time due date", isOn: $hasOneTimeDueDate)
                        if hasOneTimeDueDate {
                            DatePicker("Due", selection: $oneTimeDueDate, displayedComponents: .date)
                        }
                    }
                }

                SchedulePickerSection(
                    frequency: selected,
                    weekdays: $weekdays,
                    dayOfMonth: $dayOfMonth,
                    month: $month
                )
            }
            .navigationTitle("Schedule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(!isValid || isUnchanged)
                }
            }
        }
    }

    private var isValid: Bool {
        TaskScheduleValidation.isValid(
            frequency: selected,
            weekdays: weekdays,
            dayOfMonth: dayOfMonth,
            month: month
        )
    }

    private var isUnchanged: Bool {
        let oneTimeDateIsUnchanged = selected != .unscheduled || (
            hasOneTimeDueDate == (task.scheduledOverrideDate != nil)
                && (!hasOneTimeDueDate || Calendar.current.isDate(
                    oneTimeDueDate,
                    inSameDayAs: task.scheduledOverrideDate ?? .distantPast
                ))
        )
        return selected == task.frequency
            && Array(weekdays).sorted() == task.scheduledWeekdays.sorted()
            && (!selected.usesDayOfMonth || dayOfMonth == (task.scheduledDayOfMonth ?? -1))
            && (selected != .yearly || month == (task.scheduledMonth ?? -1))
            && oneTimeDateIsUnchanged
    }

    private func applyDefaults(for freq: TaskFrequency) {
        if freq != .unscheduled {
            hasOneTimeDueDate = false
        }
        if freq.weekdayCount > 0 && weekdays.count != freq.weekdayCount {
            weekdays = Set(freq.defaultWeekdays)
        }
    }

    private func saveAndDismiss() {
        guard isValid else { return }
        var updated = task
        updated.frequency = selected
        if selected.weekdayCount > 0 {
            updated.scheduledWeekdays = weekdays.sorted()
            updated.scheduledDayOfMonth = nil
            updated.scheduledMonth = nil
        } else if selected.usesDayOfMonth {
            updated.scheduledWeekdays = []
            updated.scheduledDayOfMonth = dayOfMonth
            updated.scheduledMonth = selected == .yearly ? month : nil
        } else {
            updated.scheduledWeekdays = []
            updated.scheduledDayOfMonth = nil
            updated.scheduledMonth = nil
        }
        if selected == .unscheduled {
            updated.scheduledOverrideDate = hasOneTimeDueDate
                ? Calendar.current.startOfDay(for: oneTimeDueDate)
                : nil
        }
        Task { await dataStore.updateTask(updated) }
        dismiss()
    }
}

// MARK: - Assignee Picker

struct AssigneePickerSheet: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    let task: HouseholdTask
    @State private var selected: UUID?

    init(task: HouseholdTask) {
        self.task = task
        self._selected = State(initialValue: task.defaultAssigneeId)
    }

    var body: some View {
        NavigationStack {
            Form {
                if task.isPersonal {
                    Text("Personal tasks can only be completed by you.")
                        .foregroundStyle(.secondary)
                } else {
                    AssigneePicker(profiles: dataStore.householdProfiles, selection: $selected)
                        .pickerStyle(.inline)
                        .labelsHidden()
                }
            }
            .navigationTitle("Assignee")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(task.isPersonal || selected == task.defaultAssigneeId)
                }
            }
        }
    }

    private func saveAndDismiss() {
        guard !task.isPersonal else {
            dismiss()
            return
        }
        var updated = task
        updated.defaultAssigneeId = selected
        Task { await dataStore.updateTask(updated) }
        dismiss()
    }
}

// MARK: - Detail Item

struct DetailItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
        }
    }
}
