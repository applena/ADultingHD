import SwiftUI

struct ProfileView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    #if os(iOS)
    @State private var showSettings = false
    #endif

    private var unlockedCount: Int { dataStore.profile.unlockedAchievements.count }
    private var totalCount: Int { allAchievements.count }

    private var visibleAchievements: [Achievement] {
        if storeManager.isPro { return allAchievements }
        return allAchievements.filter { StoreManager.freeAchievementIDs.contains($0.id) }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: Theme.sectionSpacing) {
                    profileHeader
                    levelCard
                    statsGrid
                    detailedStatsLink
                    achievementsSection
                    if storeManager.isPro && dataStore.householdProfiles.count > 1 {
                        leaderboardPreview
                    }
                    categoryBreakdown
                }
                .padding()
                .macOSContentFrame()
            }
            .rootTabScrollClearance()
        }
        .rootTabNavigation("Profile")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        #endif
    }

    private var profileHeader: some View {
        LandingHeader(
            eyebrow: "Progress",
            title: dataStore.profile.name.isEmpty ? "Your profile" : dataStore.profile.name,
            subtitle: "Level \(dataStore.profile.level) with \(dataStore.profile.totalXP) XP, \(dataStore.profile.currentStreak) day streak, and \(unlockedCount) achievements unlocked.",
            icon: "person.crop.circle.fill",
            color: Theme.levelPurple
        )
        .accessibilityIdentifier("profile-root-header")
    }

    // MARK: - Level Card

    private var levelCard: some View {
        VStack(spacing: 16) {
            // Avatar
            NavigationLink {
                AvatarShopView()
            } label: {
                VStack(spacing: 8) {
                    AvatarView(avatarState: dataStore.profile.avatarState, size: 100)

                    HStack(spacing: 4) {
                        Text("Customize")
                            .font(.caption)
                            .foregroundStyle(Theme.levelPurple)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.levelPurple)
                    }
                }
            }
            .buttonStyle(.plain)

            // Level info
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Theme.levelPurple.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Text("\(dataStore.profile.level)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.levelPurple)
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                }
                Text(dataStore.profile.levelTitle)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(Theme.xpGold)
                    Text("\(dataStore.profile.coins)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.xpGold)
                }
            }

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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: Theme.gridColumns), spacing: 12) {
            StatCard(title: "Tasks Done", value: "\(dataStore.profile.totalTasksCompleted)", icon: "checkmark.circle.fill", color: Theme.successGreen)
            StatCard(title: "Current Streak", value: "\(dataStore.profile.currentStreak)d", icon: "flame.fill", color: Theme.streakOrange)
            StatCard(title: "Best Streak", value: "\(dataStore.profile.longestStreak)d", icon: "trophy.fill", color: Theme.xpGold)
            StatCard(title: "Achievements", value: "\(unlockedCount)/\(totalCount)", icon: "medal.fill", color: Theme.levelPurple)
        }
    }

    private var detailedStatsLink: some View {
        NavigationLink {
            StatsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(Theme.successGreen)
                    .frame(width: 44, height: 44)
                    .background(Theme.successGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Detailed Stats")
                        .font(.headline)
                    Text("Trends, category breakdowns, and XP history")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile-detailed-stats-link")
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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: Theme.gridColumns), spacing: 8) {
                ForEach(visibleAchievements) { achievement in
                    let unlocked = dataStore.profile.unlockedAchievements.contains(achievement.id)
                    let progress = achievement.progressFraction(dataStore.profile, dataStore.completions)
                    AchievementCard(achievement: achievement, unlocked: unlocked, progress: progress)
                }
            }

            if !storeManager.isPro {
                ProPromptCard(title: "All 18 Achievements", icon: "medal.fill")
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
                        CompactAvatarView(
                            avatarState: member.avatarState,
                            size: 28,
                            isCurrentUser: member.id == dataStore.profile.id
                        )
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

    // MARK: - Room Breakdown

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tasks by Room", systemImage: "chart.bar")
                .font(.headline)

            ForEach(dataStore.tasksByRoom.keys.sorted(), id: \.self) { room in
                let tasks = dataStore.tasksByRoom[room] ?? []
                let category = TaskCategory(rawValue: room) ?? .general
                let active = tasks.filter(\.isActive).count
                let total = tasks.count

                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .foregroundStyle(Theme.categoryColor(category))
                        .frame(width: 20)
                    Text(room)
                        .font(.subheadline)
                    Spacer()
                    Text("\(active)/\(total) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: total > 0 ? Double(active) / Double(total) : 0)
                        .tint(Theme.categoryColor(category))
                        .frame(width: 60)
                }
                .accessibilityIdentifier("profile-room-\(room)")
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
                    .fixedSize(horizontal: false, vertical: true)

                if unlocked {
                    Text(achievement.requirement)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView(value: progress)
                        .tint(Theme.xpGold)
                        .scaleEffect(y: 0.8)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(unlocked ? Theme.xpGold.opacity(0.1) : Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
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
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    Image(systemName: achievement.icon)
                        .font(.system(size: 60))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundStyle(unlocked ? Theme.xpGold : .gray.opacity(0.4))

                    Text(achievement.name)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(achievement.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(achievement.flavorText)
                        .font(.subheadline.italic())
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
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

                    Spacer(minLength: 24)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
