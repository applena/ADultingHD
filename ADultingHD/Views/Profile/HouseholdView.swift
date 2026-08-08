import SwiftUI

struct HouseholdView: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        List {
            // Leaderboard
            Section("Leaderboard") {
                ForEach(Array(dataStore.leaderboard.enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(index == 0 ? Theme.xpGold : .secondary)
                            .frame(width: 24)

                        CompactAvatarView(avatarState: member.avatarState, size: 40)
                            .overlay {
                                Circle()
                                    .stroke(
                                        member.id == dataStore.profile.id ? Theme.levelPurple : .clear,
                                        lineWidth: 2
                                    )
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(member.name)
                                    .font(.subheadline.weight(.medium))
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
                            Text("\(member.totalXP)")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.xpGold)
                            Text("XP")
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
                            CompactAvatarView(avatarState: activity.avatarState, size: 28)

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
        .navigationTitle("Household")
    }

    private func activityColor(_ activity: HouseholdActivity) -> Color {
        switch activity.event {
        case .completedTask: Theme.successGreen
        case .leveledUp: Theme.levelPurple
        case .achievementUnlocked: Theme.xpGold
        case .passedYou: Theme.streakOrange
        }
    }
}
