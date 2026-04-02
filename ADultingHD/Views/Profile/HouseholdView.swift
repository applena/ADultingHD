import SwiftUI

struct HouseholdView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showAddMember = false
    @State private var newName = ""

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

                        Image(systemName: member.avatar)
                            .font(.title2)
                            .foregroundStyle(member.id == dataStore.profile.id ? Theme.levelPurple : .secondary)

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
                            Image(systemName: activity.avatar)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.displayTitle)
                                    .font(.subheadline)
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

            // Switch Profile
            if dataStore.householdProfiles.count > 1 {
                Section("Switch Profile") {
                    ForEach(dataStore.householdProfiles.filter { $0.id != dataStore.profile.id }) { member in
                        Button {
                            Task { await dataStore.switchProfile(to: member.id) }
                        } label: {
                            HStack {
                                Image(systemName: member.avatar)
                                Text(member.name)
                                Spacer()
                                Text("Switch")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }

            // Manage
            Section {
                Button {
                    showAddMember = true
                } label: {
                    Label("Add Member", systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle("Household")
        .alert("Add Member", isPresented: $showAddMember) {
            TextField("Name", text: $newName)
            Button("Add") {
                guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                Task {
                    await dataStore.addHouseholdMember(name: newName, avatar: "person.crop.circle.fill")
                    newName = ""
                }
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("Enter a name for the new household member")
        }
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
