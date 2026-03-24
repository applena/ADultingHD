import SwiftUI

struct TaskListView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var selectedCategory: TaskCategory?
    @State private var searchText = ""
    @State private var showActiveOnly = false
    @State private var showAddTask = false

    private var filteredTasks: [HouseholdTask] {
        var result = dataStore.tasks
        if let cat = selectedCategory { result = result.filter { $0.category == cat } }
        if showActiveOnly { result = result.filter(\.isActive) }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted { ($0.category.rawValue, $0.name) < ($1.category.rawValue, $1.name) }
    }

    private var groupedTasks: [(TaskCategory, [HouseholdTask])] {
        Dictionary(grouping: filteredTasks, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var body: some View {
        List {
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(label: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(TaskCategory.allCases) { category in
                        FilterChip(
                            label: category.rawValue,
                            icon: category.icon,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Toggle
            Toggle("Active tasks only", isOn: $showActiveOnly)

            // Task List
            ForEach(groupedTasks, id: \.0) { category, tasks in
                Section {
                    ForEach(tasks) { task in
                        NavigationLink(value: task) {
                            TaskRow(task: task)
                        }
                    }
                } header: {
                    Label(category.rawValue, systemImage: category.icon)
                        .foregroundStyle(Theme.categoryColor(category))
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search tasks...")
        .navigationTitle("Tasks")
        .navigationDestination(for: HouseholdTask.self) { task in
            TaskDetailView(task: task)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddTask = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskView()
        }
    }
}

// MARK: - Task Row

struct TaskRow: View {
    @Environment(DataStore.self) private var dataStore
    let task: HouseholdTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.isActive ? Theme.successGreen : .gray)
                .onTapGesture {
                    Task { await dataStore.toggleTask(task) }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.body.weight(.medium))
                    .strikethrough(!task.isActive, color: .secondary)

                HStack(spacing: 8) {
                    Label(task.frequency.rawValue, systemImage: task.frequency.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(task.difficulty.label, systemImage: task.difficulty.icon)
                        .font(.caption)
                        .foregroundStyle(Theme.difficultyColor(task.difficulty))

                    Text("\(task.estimatedMinutes)m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(task.xpReward)")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.xpGold)
                Text("XP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if task.isDue && task.isActive {
                Circle()
                    .fill(task.isOverdue ? Theme.warningRed : Theme.streakOrange)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption) }
                Text(label).font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
