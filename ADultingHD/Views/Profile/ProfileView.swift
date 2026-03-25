import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore

    private var unlockedCount: Int { dataStore.profile.unlockedAchievements.count }
    private var totalCount: Int { allAchievements.count }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                // Level Card
                levelCard

                // Stats Grid
                statsGrid

                // Achievements
                achievementsSection

                // Household
                if dataStore.householdProfiles.count > 1 {
                    leaderboardPreview
                }

                // Category Breakdown
                categoryBreakdown
            }
            .padding()
        }
        .navigationTitle("Profile")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        #endif
    }

    // MARK: - Level Card

    private var levelCard: some View {
        VStack(spacing: 16) {
            // Avatar area
            ZStack {
                Circle()
                    .fill(Theme.levelPurple.opacity(0.15))
                    .frame(width: 80, height: 80)
                Text("\(dataStore.profile.level)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.levelPurple)
            }

            Text(dataStore.profile.levelTitle)
                .font(.title2.bold())

            // XP Progress
            VStack(spacing: 6) {
                ProgressView(value: dataStore.profile.xpProgress)
                    .tint(Theme.levelPurple)
                    .scaleEffect(y: 2)

                HStack {
                    Text("\(dataStore.profile.totalXP) XP")
                        .font(.caption.bold())
                    Spacer()
                    Text("\(dataStore.profile.xpForNextLevel) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(Theme.cardPadding)
        .padding(.vertical, 8)
        .cardBackground()
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Tasks Done", value: "\(dataStore.profile.totalTasksCompleted)", icon: "checkmark.circle.fill", color: Theme.successGreen)
            StatCard(title: "Current Streak", value: "\(dataStore.profile.currentStreak)d", icon: "flame.fill", color: Theme.streakOrange)
            StatCard(title: "Best Streak", value: "\(dataStore.profile.longestStreak)d", icon: "trophy.fill", color: Theme.xpGold)
            StatCard(title: "Achievements", value: "\(unlockedCount)/\(totalCount)", icon: "medal.fill", color: Theme.levelPurple)
        }
    }

    // MARK: - Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Achievements", systemImage: "medal.fill")
                    .font(.headline)
                Spacer()
                Text("\(unlockedCount)/\(totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(allAchievements) { achievement in
                    let unlocked = dataStore.profile.unlockedAchievements.contains(achievement.id)
                    let progress = achievement.progressFraction(dataStore.profile, dataStore.completions)
                    AchievementCard(achievement: achievement, unlocked: unlocked, progress: progress)
                }
            }
        }
        .card()
    }

    // MARK: - Leaderboard Preview

    private var leaderboardPreview: some View {
        NavigationLink {
            HouseholdView()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label("Household", systemImage: "person.3.fill")
                    .font(.headline)

                ForEach(dataStore.leaderboard.prefix(3)) { member in
                    HStack {
                        Image(systemName: member.avatar)
                            .foregroundStyle(member.id == dataStore.profile.id ? Theme.levelPurple : .secondary)
                        Text(member.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(member.totalXP) XP")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.xpGold)
                    }
                }
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Breakdown

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tasks by Category", systemImage: "chart.bar")
                .font(.headline)

            ForEach(TaskCategory.allCases) { category in
                let tasks = dataStore.tasksByCategory[category] ?? []
                let active = tasks.filter(\.isActive).count
                let total = tasks.count

                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .foregroundStyle(Theme.categoryColor(category))
                        .frame(width: 20)
                    Text(category.rawValue)
                        .font(.subheadline)
                    Spacer()
                    Text("\(active)/\(total) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: total > 0 ? Double(active) / Double(total) : 0)
                        .tint(Theme.categoryColor(category))
                        .frame(width: 60)
                }
            }
        }
        .card()
    }
}

// MARK: - Achievement Card

struct AchievementCard: View {
    let achievement: Achievement
    let unlocked: Bool
    var progress: Double = 0

    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: achievement.icon)
                    .font(.title2)
                    .foregroundStyle(unlocked ? Theme.xpGold : .gray.opacity(0.4))
                Text(achievement.name)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)

                if unlocked {
                    Text(achievement.requirement)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView(value: progress)
                        .tint(Theme.xpGold)
                        .scaleEffect(y: 0.8)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(unlocked ? Theme.xpGold.opacity(0.1) : Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .opacity(unlocked ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            AchievementDetailView(achievement: achievement, unlocked: unlocked, progress: progress)
        }
    }
}

struct AchievementDetailView: View {
    let achievement: Achievement
    let unlocked: Bool
    let progress: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: achievement.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(unlocked ? Theme.xpGold : .gray.opacity(0.4))

                Text(achievement.name)
                    .font(.title.bold())

                Text(achievement.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(achievement.flavorText)
                    .font(.subheadline.italic())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 8) {
                    ProgressView(value: unlocked ? 1.0 : progress)
                        .tint(Theme.xpGold)
                        .scaleEffect(y: 2)
                        .padding(.horizontal, 40)

                    if unlocked {
                        Label("Unlocked", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.successGreen)
                    } else {
                        Text("\(Int(progress * 100))% complete")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
