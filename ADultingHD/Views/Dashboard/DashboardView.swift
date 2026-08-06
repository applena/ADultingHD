import SwiftUI

// MARK: - Tips

private let gameTips: [String] = [
    "Clear all your due tasks in a day to earn a 25 XP bonus!",
    "Complete every active task in a week for a 75 XP consistency bonus.",
    "Hit every task in a month and you'll earn a massive 150 XP bonus.",
    "Keep your streak alive! Each day adds up to +50 bonus XP per task.",
    "When completing a task, expand the description to see exactly what's involved.",
    "Add notes when you complete a task to track what you did.",
    "Tap the frequency on any task to change how often it's due.",
    "Coins are earned alongside XP — spend them in the Avatar Shop!",
    "Unlock new characters, hats, and accessories as you level up.",
    "Complete 5 tasks in one day to unlock the \"Productive Day\" achievement.",
    "Your streak resets if you skip a day — don't break the chain!",
    "Higher-difficulty tasks earn more XP. Challenge yourself!",
    "Less-frequent tasks (monthly, quarterly) earn extra XP per completion.",
    "Browse the All Tasks tab to discover new tasks to add to your list.",
    "You can create your own custom tasks from the All Tasks tab.",
    "Check the Supplies view to track what cleaning products you need.",
    "Longer tasks earn a time bonus — every 10 minutes adds +2 XP.",
    "Reach level 5 to unlock the Panda and the Crown in the shop!",
    "Completing a task early (before it's due) can unlock the Early Bird achievement.",
    "Seasonal tasks appear on your dashboard — add them before the season ends!",
]

struct DashboardView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    @AppStorage(PrefKey.showSeasonalSection) private var showSeasonalSection = false
    @State private var showAddTask = false
    @State private var showProUpgrade = false

    private var seasonalSectionVisible: Bool { storeManager.isPro && showSeasonalSection }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning!"
        case 12..<17: return "Good afternoon!"
        case 17..<21: return "Good evening!"
        default: return "Night owl mode!"
        }
    }

    private var subtitle: String {
        let due = dataStore.dueTasks.count
        let overdue = dataStore.overdueTasks.count
        let streak = dataStore.profile.currentStreak
        if due == 0 { return "All caught up — you're crushing it!" }
        if overdue > 0 { return "\(overdue) overdue — \(overdue == 1 ? "it's" : "they're") been waiting the longest." }
        if streak >= 7 { return "\(streak)-day streak! Keep it going." }
        if due > 5 { return "\(due) quests ready to conquer." }
        return "You've got \(due) tasks to tackle. You got this!"
    }

    private var currentTip: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return gameTips[day % gameTips.count]
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                #if os(macOS)
                macOSLayout
                #else
                iOSLayout
                #endif
            }
            .rootTabScrollClearance()
        }
        .rootTabNavigation("")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HouseholdSwitcher()
            }
        }
        #endif
        .sheet(isPresented: $showAddTask) {
            AddTaskView()
        }
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeView()
        }
    }

    @ViewBuilder
    private var primaryTaskSection: some View {
        if dataStore.tasks.isEmpty { emptyTasksSection }
        else if dataStore.dueTasks.isEmpty { caughtUpSection }
        else { dueTasksSection }
    }

    #if os(iOS)
    private var iOSLayout: some View {
        VStack(spacing: Theme.sectionSpacing) {
            heroSection
            tipBanner
            statsRow
            primaryTaskSection
            if !dataStore.todayCompletions.isEmpty { recentCompletionsSection }
            if seasonalSectionVisible { seasonalSection }
        }
        .padding()
    }
    #endif

    #if os(macOS)
    private var hasRightColumnContent: Bool {
        !dataStore.todayCompletions.isEmpty || (seasonalSectionVisible && !seasonalSuggestions.isEmpty)
    }

    private var macOSLayout: some View {
        VStack(spacing: Theme.sectionSpacing) {
            // Full-width top strip: hero + stats side by side
            HStack(alignment: .top, spacing: Theme.sectionSpacing) {
                heroSection
                    .frame(maxWidth: .infinity)
                VStack(spacing: Theme.sectionSpacing) {
                    statsRow
                    tipBanner
                }
                .frame(maxWidth: 320)
            }

            // Main body: due tasks left, secondary content right
            HStack(alignment: .top, spacing: Theme.sectionSpacing) {
                primaryTaskSection
                    .frame(maxWidth: .infinity)
                if hasRightColumnContent {
                    VStack(spacing: Theme.sectionSpacing) {
                        if !dataStore.todayCompletions.isEmpty { recentCompletionsSection }
                        if seasonalSectionVisible { seasonalSection }
                    }
                    .frame(maxWidth: 320)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }
    #endif

    // MARK: - Hero Section

    private var heroSection: some View {
        let hasDueTasks = !dataStore.dueTasks.isEmpty
        let hasOverdueTasks = !dataStore.overdueTasks.isEmpty
        return VStack(alignment: .leading, spacing: 16) {
            LandingHeader(
                eyebrow: dataStore.activeHousehold.name,
                title: greeting,
                subtitle: subtitle,
                icon: hasDueTasks ? "clock.badge.exclamationmark.fill" : "checkmark.seal.fill",
                color: !hasDueTasks
                    ? Theme.successGreen
                    : (hasOverdueTasks ? Theme.overdueRed : Theme.streakOrange)
            )
            .accessibilityIdentifier("home-root-header")

            HStack(alignment: .top, spacing: 12) {
                CompactAvatarView(avatarState: dataStore.profile.avatarState, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dataStore.profile.levelTitle)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: dataStore.profile.xpProgress)
                        .tint(Theme.levelPurple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(dataStore.profile.totalXP)")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.xpGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Total XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    // MARK: - Tip Banner

    private var tipBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.title3)
                .foregroundStyle(Theme.xpGold)

            Text(currentTip)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.xpGold.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Streak",
                value: "\(dataStore.profile.currentStreak)d",
                icon: "flame.fill",
                color: dataStore.profile.currentStreak > 0 ? Theme.streakOrange : .secondary
            )
            StatCard(
                title: "Done Today",
                value: "\(dataStore.todayCompletions.count)",
                icon: "checkmark.circle.fill",
                color: Theme.successGreen
            )
            StatCard(
                title: "XP Today",
                value: "+\(dataStore.todayXP)",
                icon: "star.fill",
                color: Theme.xpGold
            )
        }
    }

    private var canCreateCustomTask: Bool {
        storeManager.canCreateCustomTask(existingCount: dataStore.customTaskCount)
    }

    private var emptyTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No tasks yet", systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(Theme.accent)

            Text("Add your first task and it'll show up here whenever it's due.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if canCreateCustomTask { showAddTask = true }
                else { showProUpgrade = true }
            } label: {
                Label("Add A Task", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private var caughtUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today is clear", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.successGreen)

            Text("No tasks are currently due. Browse the catalog, check supplies, or keep the streak alive when the next task appears.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                MetricPill(title: "Active", value: "\(dataStore.activeTasks.count)", icon: "checklist", color: Theme.accent)
                MetricPill(title: "Done today", value: "\(dataStore.todayCompletions.count)", icon: "checkmark.circle.fill", color: Theme.successGreen)
            }
        }
        .card()
    }

    // MARK: - Due Tasks

    private var dueTasksSection: some View {
        let overdueCount = dataStore.overdueTasks.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Up Next", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                Spacer()
                if overdueCount > 0 {
                    Text("\(overdueCount) overdue")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.overdueRed)
                }
                Text("\(dataStore.dueTasks.count) tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(dataStore.dueTasks.prefix(10)) { task in
                DueTaskRow(task: task)
            }

            if dataStore.dueTasks.count > 10 {
                Text("+ \(dataStore.dueTasks.count - 10) more...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .card()
    }

    // MARK: - Seasonal Suggestions

    private var seasonalSuggestions: [SeasonalSuggestion] {
        let existingNames = Set(dataStore.tasks.map(\.name))
        return currentSeasonSuggestions().filter { !existingNames.contains($0.name) }
    }

    private var seasonalSection: some View {
        Group {
            if !seasonalSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("\(Season.current.rawValue) Tasks", systemImage: Season.current.icon)
                            .font(.headline)
                        Spacer()
                        Button {
                            withAnimation { showSeasonalSection = false }
                        } label: {
                            Text("Hide")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(seasonalSuggestions) { suggestion in
                        HStack(spacing: 10) {
                            Image(systemName: suggestion.category.icon)
                                .foregroundStyle(Theme.categoryColor(suggestion.category))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name)
                                    .font(.subheadline.weight(.medium))
                                Text("\(suggestion.estimatedMinutes)m · \(suggestion.difficulty.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                Task { await dataStore.addCustomTask(suggestion.toTask()) }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Recent Completions

    private var recentCompletionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Completed Today", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Theme.successGreen)

            ForEach(dataStore.todayCompletions) { completion in
                HStack {
                    Text(completion.taskName)
                        .font(.subheadline)
                    Spacer()
                    Text("+\(completion.xpEarned + completion.streakBonus) XP")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.xpGold)
                    Text(completion.completedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }
}

// MARK: - Due Task Row

struct DueTaskRow: View {
    @Environment(DataStore.self) private var dataStore
    let task: HouseholdTask
    @State private var showComplete = false

    var body: some View {
        let status = task.dueStatus()
        HStack(spacing: 10) {
            Image(systemName: task.category.icon)
                .foregroundStyle(Theme.categoryColor(task.category))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if status.isOverdue {
                        Text("\(status.daysOverdue)d overdue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.overdueRed)
                    } else {
                        Text("\(task.estimatedMinutes)m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("+\(task.xpReward) XP")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.xpGold)
                }
            }

            Spacer()

            Button {
                showComplete = true
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.successGreen)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showComplete) {
                CompleteTaskSheet(task: task)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Complete Task Sheet

struct CompleteTaskSheet: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    let task: HouseholdTask
    @State private var showDescription = false
    @State private var notes = ""
    @State private var checkedStepIds: Set<UUID> = []
    @State private var expandedStepId: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: task.category.icon)
                            .foregroundStyle(Theme.categoryColor(task.category))
                        Text(task.name)
                            .font(.headline)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                            Text("+\(task.xpReward) XP")
                                .font(.subheadline.bold())
                        }
                        .foregroundStyle(Theme.xpGold)
                    }

                    if !task.description.isEmpty {
                        Button {
                            withAnimation { showDescription.toggle() }
                        } label: {
                            HStack {
                                Text("What's involved")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: showDescription ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if showDescription {
                            Text(task.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !task.checklist.isEmpty {
                    Section {
                        ForEach(task.checklist) { step in
                            checklistRow(step)
                        }
                    } header: {
                        HStack {
                            Text("Checklist")
                            Spacer()
                            Text("\(checkedStepIds.count)/\(task.checklist.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !task.supplies.isEmpty {
                    Section("Supplies needed") {
                        ForEach(task.supplies, id: \.self) { supply in
                            Label(supply, systemImage: "circle.fill")
                                .font(.subheadline)
                                .labelStyle(SupplyLabelStyle())
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextField("How did it go?", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Complete Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            await dataStore.completeTask(task, notes: notes.isEmpty ? nil : notes)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func checklistRow(_ step: ChecklistItem) -> some View {
        let checked = checkedStepIds.contains(step.id)
        let expanded = expandedStepId == step.id
        let hasInstructions = !step.instructions.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    toggleChecked(step.id)
                } label: {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(checked ? Theme.successGreen : .secondary)
                }
                .buttonStyle(.plain)

                Text(step.text)
                    .font(.subheadline)
                    .strikethrough(checked, color: .secondary)
                    .foregroundStyle(checked ? .secondary : .primary)

                Spacer()

                if hasInstructions {
                    Button {
                        expandedStepId = expanded ? nil : step.id
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if expanded && hasInstructions {
                Text(step.instructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleChecked(step.id) }
    }

    private func toggleChecked(_ id: UUID) {
        if checkedStepIds.contains(id) { checkedStepIds.remove(id) }
        else { checkedStepIds.insert(id) }
    }
}

struct SupplyLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}
