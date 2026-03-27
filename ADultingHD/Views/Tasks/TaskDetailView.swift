import SwiftUI

struct TaskDetailView: View {
    @Environment(DataStore.self) private var dataStore
    let task: HouseholdTask
    @State private var showComplete = false
    @State private var showFrequencyPicker = false

    private var currentTask: HouseholdTask {
        dataStore.tasks.first { $0.id == task.id } ?? task
    }

    private var recentCompletions: [TaskCompletion] {
        dataStore.completions
            .filter { $0.taskId == task.id }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                // Header
                headerCard

                // Details
                detailsCard

                // Supplies
                if !currentTask.supplies.isEmpty {
                    suppliesCard
                }

                // Complete Button
                if currentTask.isActive {
                    completeButton
                }

                // History
                if !recentCompletions.isEmpty {
                    historySection
                }
            }
            .padding()
        }
        .navigationTitle(task.name)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: currentTask.category.icon)
                    .font(.largeTitle)
                    .foregroundStyle(Theme.categoryColor(currentTask.category))

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentTask.name)
                        .font(.title2.bold())
                    Text(currentTask.category.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("+\(currentTask.xpReward) XP")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.xpGold)
                    if currentTask.isDue {
                        Text("DUE")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.streakOrange, in: Capsule())
                    }
                }
            }

            Text(currentTask.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
    }

    // MARK: - Details

    private var detailsCard: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Button { showFrequencyPicker = true } label: {
                DetailItem(label: "Frequency", value: currentTask.frequency.rawValue, icon: currentTask.frequency.icon)
            }
            .buttonStyle(.plain)

            DetailItem(label: "Difficulty", value: currentTask.difficulty.label, icon: currentTask.difficulty.icon)
            DetailItem(label: "Est. Time", value: "\(currentTask.estimatedMinutes) min", icon: "clock")

            if let days = currentTask.daysSinceLastCompleted {
                DetailItem(label: "Last Done", value: "\(days)d ago", icon: "calendar.badge.clock")
            } else {
                DetailItem(label: "Last Done", value: "Never", icon: "calendar.badge.clock")
            }
        }
        .card()
        .sheet(isPresented: $showFrequencyPicker) {
            FrequencyPickerSheet(task: currentTask)
        }
    }

    // MARK: - Supplies

    private var suppliesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Supplies Needed", systemImage: "cart")
                .font(.headline)

            ForEach(currentTask.supplies, id: \.self) { supply in
                Label(supply, systemImage: "circle.fill")
                    .font(.subheadline)
                    .labelStyle(SupplyLabelStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Complete Button

    private var completeButton: some View {
        Button {
            showComplete = true
        } label: {
            Label("Mark Complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.successGreen, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showComplete) {
            CompleteTaskSheet(task: currentTask)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent History", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            ForEach(recentCompletions) { completion in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(completion.completedAt, style: .date)
                            .font(.subheadline)
                        Text(completion.completedAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let quality = completion.quality {
                            Label(quality.label, systemImage: quality.icon)
                                .font(.caption2)
                                .foregroundStyle(quality == .deep ? Theme.levelPurple : .secondary)
                        }
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

    init(task: HouseholdTask) {
        self.task = task
        self._selected = State(initialValue: task.frequency)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(TaskFrequency.allCases) { freq in
                    Button {
                        selected = freq
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: freq.icon)
                                .foregroundStyle(Theme.categoryColor(.general))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(freq.rawValue)
                                    .font(.body)
                                Text("Every \(freq.days) day\(freq.days == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if freq == selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.successGreen)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Frequency")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = task
                        updated.frequency = selected
                        Task { await dataStore.updateTask(updated) }
                        dismiss()
                    }
                    .disabled(selected == task.frequency)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
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
