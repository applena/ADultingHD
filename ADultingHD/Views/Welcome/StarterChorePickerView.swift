import SwiftUI

/// Progressive, room-scoped onboarding suggestions. Only a small batch is
/// visible at first so setup feels useful without becoming a catalog browser.
struct StarterChorePickerView: View {
    private struct ChoreGroup: Identifiable {
        let room: String
        let tasks: [CatalogTask]

        var id: String { room }
    }

    let tasks: [CatalogTask]
    @Binding var selectedTaskNames: Set<String>
    @Binding var visibleTaskCount: Int

    private let batchSize = 5

    private var visibleTasks: [CatalogTask] { Array(tasks.prefix(visibleTaskCount)) }

    private var groupedTasks: [ChoreGroup] {
        var roomOrder: [String] = []
        var groups: [String: [CatalogTask]] = [:]

        for task in visibleTasks {
            let room = task.suggestedRoom ?? "Around the house"
            if groups[room] == nil { roomOrder.append(room) }
            groups[room, default: []].append(task)
        }

        return roomOrder.map { ChoreGroup(room: $0, tasks: groups[$0] ?? []) }
    }

    private var nextBatchCount: Int {
        min(batchSize, max(tasks.count - visibleTaskCount, 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groupedTasks) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Label(group.room, systemImage: icon(for: group.room))
                        .font(.headline)
                        .foregroundStyle(Theme.cream.opacity(0.78))

                    ForEach(group.tasks) { task in
                        taskRow(task)
                    }
                }
            }

            if nextBatchCount > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        visibleTaskCount = min(visibleTaskCount + batchSize, tasks.count)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                        Text("Show \(nextBatchCount) more \(nextBatchCount == 1 ? "idea" : "ideas")")
                            .frame(maxWidth: .infinity)
                        Image(systemName: "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Theme.adventureBlue.opacity(0.78), in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                            .strokeBorder(Theme.sky.opacity(0.55))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-show-more-chores")
                .accessibilityHint("Adds another batch of room-based chore suggestions")
            }

            Label(
                "\(selectedTaskNames.count) \(selectedTaskNames.count == 1 ? "chore" : "chores") selected",
                systemImage: "checkmark.circle"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selectedTaskNames.isEmpty ? Theme.cream.opacity(0.68) : Theme.sky)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("onboarding-starter-chore-count")
        }
        .padding(12)
        .background(Theme.onboardingTwilightBackground, in: RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius)
                .strokeBorder(Theme.sky.opacity(0.20))
        }
        .shadow(color: Theme.adventureBlue.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }

    private func taskRow(_ task: CatalogTask) -> some View {
        let selected = selectedTaskNames.contains(task.name)
        let color = Theme.categoryColor(task.category)

        return Button {
            if selected {
                selectedTaskNames.remove(task.name)
            } else {
                selectedTaskNames.insert(task.name)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: task.suggestedRoom))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(selected ? Theme.cream : color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.headline)
                        .foregroundStyle(Theme.cream)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(task.suggestedFrequency.rawValue) · \(task.estimatedMinutes) min")
                        .font(.subheadline)
                        .foregroundStyle(Theme.cream.opacity(0.62))
                }

                Spacer(minLength: 8)

                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title)
                    .foregroundStyle(selected ? Theme.sky : Theme.cream.opacity(0.60))
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(
                selected ? Theme.adventureBlue.opacity(0.90) : Color.black.opacity(0.18),
                in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                    .strokeBorder(selected ? Theme.sky : Theme.cream.opacity(0.14), lineWidth: selected ? 2 : 1)
            }
            .shadow(color: selected ? Theme.sky.opacity(0.22) : .clear, radius: 5)
            .contentShape(RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-starter-chore-\(task.name)")
        .accessibilityLabel("\(task.name), \(task.suggestedFrequency.rawValue), \(task.estimatedMinutes) minutes")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(selected ? "Double tap to leave this chore out" : "Double tap to add this chore")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func icon(for room: String?) -> String {
        guard let room,
              let location = HomeLocation.allCases.first(where: { $0.matches(taskRoom: room) }) else {
            return "house"
        }
        return location.icon
    }
}
