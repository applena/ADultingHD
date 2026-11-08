import SwiftUI

struct HouseholdView: View {
    @Environment(DataStore.self) private var dataStore

    @State private var metric: ContributionMetric = .tasks
    @State private var period: ContributionPeriod = .week

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            leaderboard(at: context.date)
        }
        .navigationTitle("Household")
    }

    private func leaderboard(at date: Date) -> some View {
        let contributions = dataStore.householdContributions
        let entries = WeeklyLeaderboard.entries(
            members: dataStore.householdProfiles, completions: contributions,
            referenceDate: date, period: period, metric: metric
        )
        let champions = WeeklyLeaderboard.previousWeekChampions(
            members: dataStore.householdProfiles, completions: contributions, referenceDate: date
        )
        return List {
            Section {
                Picker("Time period", selection: $period) {
                    ForEach(ContributionPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Rank by", selection: $metric) {
                    ForEach(ContributionMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Shared household tasks only. XP includes task and streak XP, excluding personal tasks and consistency bonuses.")
            }

            Section {
                Label("Weekly Champion", systemImage: "crown.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.xpGold)
                if champions.isEmpty {
                    Text("The top XP contributor at the end of each week earns a crown to wear here all next week. Tied leaders share the crown.")
                } else {
                    ForEach(champions) { champion in
                        Label(champion.profile.name, systemImage: "crown.fill")
                            .foregroundStyle(Theme.xpGold)
                        Text("\(champion.taskCount) tasks · \(champion.weeklyXP) XP last week")
                            .font(.caption)
                    }
                    Text("Last week’s top contributors hold the crown this week. Ties share the reward.")
                }
            }

            // Leaderboard
            Section("Leaderboard") {
                if entries.allSatisfy({ $0.taskCount == 0 }) {
                    Text("No shared tasks completed in this period yet. Every contribution counts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    let member = entry.profile
                    let rank = WeeklyLeaderboard.rank(of: entry, among: entries, metric: metric)
                    HStack(spacing: 12) {
                        Text("\(rank)")
                            .font(.headline)
                            .foregroundStyle(rank == 1 ? Theme.xpGold : .secondary)
                            .frame(width: 24)

                        CompactAvatarView(
                            avatarState: member.avatarState,
                            size: 40,
                            isCurrentUser: member.id == dataStore.profile.id
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(member.name)
                                    .font(.subheadline.weight(.medium))
                                if champions.contains(where: { $0.id == member.id }) {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(Theme.xpGold)
                                        .accessibilityLabel("Weekly Champion")
                                }
                                if member.id == dataStore.profile.id {
                                    Text("YOU")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Theme.levelPurple, in: Capsule())
                                }
                            }
                            Text("Level \(member.level) · \(member.levelTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text(metric == .tasks ? "\(entry.taskCount) tasks" : "\(entry.weeklyXP) XP")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.xpGold)
                            Text(metric == .tasks ? "\(entry.weeklyXP) XP" : "\(entry.taskCount) tasks")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Recent Activity
            if !dataStore.householdActivityFeed.isEmpty {
                Section("Recent Activity") {
                    ForEach(dataStore.householdActivityFeed.prefix(10)) { activity in
                        HStack(spacing: 10) {
                            CompactAvatarView(
                                avatarState: activity.avatarState,
                                size: 28,
                                isCurrentUser: activity.profileId == dataStore.profile.id
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.displayTitle)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(activity.timestamp, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: activity.systemImage)
                                .font(.caption)
                                .foregroundStyle(activityColor(activity))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Invite hint — CloudKit sharing is the only way to add members;
            // solo households show a pointer to the Households screen.
            if dataStore.householdProfiles.count == 1 {
                Section {
                    Label("Invite household members from Settings → Households.", systemImage: "person.crop.circle.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func activityColor(_ activity: HouseholdActivity) -> Color {
        switch activity.event {
        case .joinedHousehold: Theme.successGreen
        case .completedTask: Theme.successGreen
        case .leveledUp: Theme.levelPurple
        case .achievementUnlocked: Theme.xpGold
        case .passedYou: Theme.streakOrange
        }
    }
}
