import SwiftUI

struct DashboardView: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                // Level & XP Header
                levelHeader

                // Streak
                streakCard

                // Today's Stats
                todayStats

                // Due Tasks
                if !dataStore.dueTasks.isEmpty {
                    dueTasksSection
                }

                // Recent Completions
                if !dataStore.todayCompletions.isEmpty {
                    recentCompletionsSection
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }

    // MARK: - Level Header

    private var levelHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Level \(dataStore.profile.level)")
                        .font(.title.bold())
                    Text(dataStore.profile.levelTitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(dataStore.profile.totalXP) XP")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.xpGold)
                    Text("Total earned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // XP Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: dataStore.profile.xpProgress)
                    .tint(Theme.levelPurple)
                HStack {
                    Text("Lv \(dataStore.profile.level)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    let xpNeeded = dataStore.profile.xpForNextLevel - dataStore.profile.totalXP
                    Text("\(xpNeeded) XP to Lv \(dataStore.profile.level + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(dataStore.profile.currentStreak > 0 ? Theme.streakOrange : .gray)
                Text("\(dataStore.profile.currentStreak)")
                    .font(.title2.bold())
                Text("Current Streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.title)
                    .foregroundStyle(Theme.xpGold)
                Text("\(dataStore.profile.longestStreak)")
                    .font(.title2.bold())
                Text("Best Streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.successGreen)
                Text("\(dataStore.profile.totalTasksCompleted)")
                    .font(.title2.bold())
                Text("All Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Theme.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Today Stats

    private var todayStats: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Due Today",
                value: "\(dataStore.dueTasks.count)",
                icon: "exclamationmark.circle",
                color: dataStore.dueTasks.isEmpty ? Theme.successGreen : Theme.streakOrange
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Due Tasks", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Spacer()
                Text("\(dataStore.dueTasks.count)")
                    .font(.subheadline)
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
        .padding(Theme.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Recent Completions

    private var recentCompletionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(Theme.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
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
                    if task.isOverdue {
                        Text("OVERDUE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.warningRed, in: Capsule())
                    }
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
            .confirmationDialog("Complete \(task.name)?", isPresented: $showComplete) {
                Button("Complete (+\(task.xpReward) XP)") {
                    Task { await dataStore.completeTask(task) }
                }
            }
        }
        .padding(.vertical, 4)
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
        .padding(Theme.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
