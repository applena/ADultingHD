import SwiftUI

// MARK: - Navigation

enum TaskNavDestination: Hashable {
    case detail(HouseholdTask)
}

enum TaskTab: String, CaseIterable {
    case myTasks = "My Tasks"
    case allTasks = "All Tasks"
}

struct TaskListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    @State private var selectedTab: TaskTab = .myTasks
    @State private var selectedCategory: TaskCategory?
    @State private var assigneeFilter: AssigneeFilter = .all
    @State private var searchText = ""
    @State private var showAddCustom = false
    @State private var showProUpgrade = false

    init(initialTab: TaskTab = .myTasks, initialCategory: TaskCategory? = nil) {
        _selectedTab = State(initialValue: initialTab)
        _selectedCategory = State(initialValue: initialCategory)
    }

    private var canCreateCustomTask: Bool {
        storeManager.canCreateCustomTask(existingCount: dataStore.customTaskCount)
    }

    private var searchPrompt: String {
        selectedTab == .myTasks ? "Search my tasks..." : "Search all tasks..."
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 0) {
                taskHeader
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom, 8)

                Picker("View", selection: $selectedTab) {
                    ForEach(TaskTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: selectedTab) {
                    selectedCategory = nil
                }

                Group {
                    switch selectedTab {
                    case .myTasks:
                        myTasksList
                    case .allTasks:
                        catalogList
                    }
                }
                .rootTabScrollClearance()
            }
        }
        #if os(macOS)
        .searchable(text: $searchText, prompt: searchPrompt)
        #else
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(searchPrompt, text: $searchText)
                        .textFieldStyle(.plain)
                        .accessibilityLabel(searchPrompt)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 280)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
        #endif
        .rootTabNavigation("Tasks")
        .navigationDestination(for: TaskNavDestination.self) { destination in
            switch destination {
            case .detail(let task):
                TaskDetailView(task: task)
            }
        }
        .sheet(isPresented: $showAddCustom) {
            AddTaskView()
        }
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeView()
        }
    }

    private var taskHeader: some View {
        let isCatalog = selectedTab == .allTasks
        return LandingHeader(
            eyebrow: isCatalog ? "Task catalog" : dataStore.activeHousehold.name,
            title: isCatalog ? "Add work that matches your home" : "Your quest log",
            subtitle: isCatalog
                ? "\(taskCatalog.count) ready-made tasks plus custom chores when the catalog is not specific enough."
                : "\(dataStore.activeTasks.count) active · \(dataStore.tasks.count - dataStore.activeTasks.count) paused · \(dataStore.dueTasks.count) due now.",
            icon: isCatalog ? "square.grid.2x2.fill" : "checklist",
            color: isCatalog ? Theme.levelPurple : Theme.accent
        )
        .accessibilityIdentifier("tasks-root-header")
    }

    // MARK: - My Tasks

    private var filteredTasks: [HouseholdTask] {
        var result = dataStore.tasks
        if let cat = selectedCategory { result = result.filter { $0.category == cat } }
        // Only apply the assignee filter while its chip row is visible — if a
        // household shrinks back to one member (a share is revoked or a
        // member leaves) while "Mine"/"Unassigned" was selected, the row
        // disappears along with any way to reset it; silently continuing to
        // filter would leave the list looking incomplete with no visible cause.
        if dataStore.hasMultipleAssignees {
            result = result.filter { $0.matches(assigneeFilter, currentProfileId: dataStore.profile.id) }
        }
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

    private var myTasksList: some View {
        List {
            categoryFilter
            assigneeFilterRow

            if groupedTasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks Yet", systemImage: "checklist")
                } description: {
                    Text("Browse the catalog to add a focused starter set, then come back here to manage what is active.")
                }
            }

            ForEach(groupedTasks, id: \.0) { category, tasks in
                let dueCount = tasks.filter { $0.isDue && $0.isActive }.count
                Section {
                    ForEach(tasks) { task in
                        TaskRow(task: task)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Label(category.rawValue, systemImage: category.icon)
                            .foregroundStyle(Theme.categoryColor(category))
                        Spacer()
                        if dueCount > 0 {
                            Text("\(dueCount) due")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.streakOrange)
                        }
                        Text("\(tasks.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - All Tasks Catalog

    private var existingTaskNames: Set<String> {
        Set(dataStore.tasks.map { $0.name.lowercased() })
    }

    private var filteredCatalog: [CatalogTask] {
        var result = taskCatalog
        if let cat = selectedCategory { result = result.filter { $0.category == cat } }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var groupedCatalog: [(TaskCategory, [CatalogTask])] {
        Dictionary(grouping: filteredCatalog, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    private var catalogList: some View {
        List {
            categoryFilter

            Section {
                Button {
                    if canCreateCustomTask {
                        showAddCustom = true
                    } else {
                        showProUpgrade = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canCreateCustomTask ? Theme.accent : Theme.xpGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create Custom Task")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            if canCreateCustomTask {
                                Text("Add your own task with a custom schedule")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Upgrade to Pro for unlimited custom tasks")
                                    .font(.caption)
                                    .foregroundStyle(Theme.xpGold)
                            }
                        }
                        Spacer()
                        if canCreateCustomTask {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.xpGold)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            ForEach(groupedCatalog, id: \.0) { category, tasks in
                Section {
                    ForEach(tasks) { catalogTask in
                        CatalogRow(
                            catalogTask: catalogTask,
                            alreadyAdded: existingTaskNames.contains(catalogTask.name.lowercased())
                        )
                    }
                } header: {
                    HStack {
                        Label(category.rawValue, systemImage: category.icon)
                            .foregroundStyle(Theme.categoryColor(category))
                        Spacer()
                        Text("\(tasks.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Shared

    private var categoryFilter: some View {
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
    }

    /// "Mine" / "Unassigned" / "All" chip row, shown only once a household
    /// has more than one member — solo households have only one possible
    /// assignee, so the filter would be a no-op.
    @ViewBuilder
    private var assigneeFilterRow: some View {
        if dataStore.hasMultipleAssignees {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AssigneeFilter.allCases) { filter in
                        FilterChip(label: filter.rawValue, isSelected: assigneeFilter == filter) {
                            assigneeFilter = filter
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Task Row

struct TaskRow: View {
    @Environment(DataStore.self) private var dataStore
    let task: HouseholdTask

    var body: some View {
        let status = task.dueStatus()
        HStack(spacing: 8) {
            Button {
                Task { await dataStore.toggleTask(task) }
            } label: {
                Image(systemName: task.isActive ? "checkmark.circle.fill" : "pause.circle")
                    .font(.title3)
                    .foregroundStyle(task.isActive ? Theme.successGreen : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isActive ? "Pause \(task.name)" : "Restore \(task.name)")
            .accessibilityValue(task.isActive ? "Active" : "Paused")

            NavigationLink(value: TaskNavDestination.detail(task)) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(task.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(task.isActive ? .primary : .secondary)
                                .strikethrough(!task.isActive, color: .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if status.isDue && task.isActive {
                                Image(systemName: status.isOverdue ? "exclamationmark.circle.fill" : "clock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(status.isOverdue ? Theme.overdueRed : Theme.streakOrange)
                                    .accessibilityHidden(true)
                            }
                        }

                        HStack(spacing: 8) {
                            Text(task.isActive ? task.frequency.rawValue : "Paused")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(task.estimatedMinutes)m")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            if task.isActive, status.isOverdue {
                                Text("\(status.daysOverdue)d overdue")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.overdueRed)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    Text("+\(task.xpReward) XP")
                        .font(.caption)
                        .foregroundStyle(Theme.xpGold.opacity(0.8))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(task.name)")
            .accessibilityHint("View or edit task details")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Catalog Row

struct CatalogRow: View {
    @Environment(DataStore.self) private var dataStore
    let catalogTask: CatalogTask
    let alreadyAdded: Bool
    @State private var justAdded = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(catalogTask.name)
                    .font(.body.weight(.medium))

                Text(catalogTask.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                TaskMetadataRow(frequency: catalogTask.suggestedFrequency, difficulty: catalogTask.difficulty, estimatedMinutes: catalogTask.estimatedMinutes)
            }

            Spacer()

            if alreadyAdded || justAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.successGreen)
                    .imageScale(.large)
            } else {
                Button {
                    let task = catalogTask.toHouseholdTask()
                    Task { await dataStore.addCustomTask(task) }
                    withAnimation { justAdded = true }
                    FeedbackManager.taskCompleted()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(catalogTask.name)")
                .accessibilityHint("Adds this task to your quest log")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Task Metadata Row

struct TaskMetadataRow: View {
    let frequency: TaskFrequency
    let difficulty: Difficulty
    let estimatedMinutes: Int

    var body: some View {
        HStack(spacing: 8) {
            Label(frequency.rawValue, systemImage: frequency.icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(difficulty.label, systemImage: difficulty.icon)
                .font(.caption)
                .foregroundStyle(Theme.difficultyColor(difficulty))

            Text("\(estimatedMinutes)m")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
            .frame(minHeight: 44)
            .background(isSelected ? Theme.accent : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
