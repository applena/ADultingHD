import SwiftUI

struct DashboardView: View {
    @Environment(DataStore.self) private var dataStore

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
        let streak = dataStore.profile.currentStreak
        if due == 0 { return "All caught up — you're crushing it!" }
        if streak >= 7 { return "\(streak)-day streak! Keep it going." }
        if due > 5 { return "\(due) quests ready to conquer." }
        return "You've got \(due) tasks to tackle. You got this!"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                heroSection
                statsRow

                if !dataStore.dueTasks.isEmpty {
                    dueTasksSection
                }

                if !dataStore.todayCompletions.isEmpty {
                    recentCompletionsSection
                }

                seasonalSection
            }
            .padding()
        }
        .navigationTitle("Home")
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.levelPurple.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text("\(dataStore.profile.level)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.levelPurple)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(dataStore.profile.levelTitle)
                        .font(.subheadline.weight(.medium))
                    ProgressView(value: dataStore.profile.xpProgress)
                        .tint(Theme.levelPurple)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(dataStore.profile.totalXP)")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.xpGold)
                    Text("Total XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
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

    // MARK: - Due Tasks

    private var dueTasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Up Next", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                Spacer()
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
                        Text("Seasonal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        HStack(spacing: 10) {
            Image(systemName: task.category.icon)
                .foregroundStyle(Theme.categoryColor(task.category))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text("\(task.estimatedMinutes)m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    @State private var quality: CompletionQuality = .normal
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: task.category.icon)
                            .foregroundStyle(Theme.categoryColor(task.category))
                        Text(task.name)
                            .font(.headline)
                    }
                }

                Section("How thorough?") {
                    Picker("Quality", selection: $quality) {
                        ForEach(CompletionQuality.allCases) { q in
                            Label(q.label, systemImage: q.icon).tag(q)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("XP Reward")
                        Spacer()
                        Text("+\(Int(Double(task.xpReward) * quality.xpMultiplier)) XP")
                            .bold()
                            .foregroundStyle(Theme.xpGold)
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
                            await dataStore.completeTask(task, notes: notes.isEmpty ? nil : notes, quality: quality)
                            dismiss()
                        }
                    }
                }
            }
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
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}
