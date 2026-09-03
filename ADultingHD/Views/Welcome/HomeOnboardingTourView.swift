import SwiftUI

/// A safe, read-only replica of Home used to teach the four everyday task
/// controls before onboarding hands the user to the live dashboard.
struct HomeOnboardingTourView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = TourStep.add

    let playerName: String
    let tasks: [HouseholdTask]
    let onboardingPosition: Int
    let onboardingTotal: Int
    let onComplete: () -> Void

    private enum TourStep: Int, CaseIterable {
        case add
        case edit
        case delete
        case filter

        var title: String {
            switch self {
            case .add: "Add a new task"
            case .edit: "Edit a task"
            case .delete: "Delete a task"
            case .filter: "Filter your tasks"
            }
        }

        var body: String {
            switch self {
            case .add:
                "Tap the + button whenever you want to add a chore. A task name is all you need—you can add details later."
            case .edit:
                "Tap the ••• menu beside any task, then choose Edit. You can change its schedule, room, difficulty, supplies, or instructions anytime."
            case .delete:
                "Open the same ••• menu and choose Delete when a task no longer belongs in your routine."
            case .filter:
                "Use the room filters to focus on one part of your home, or choose All to see everything again."
            }
        }

        var accessibilityID: String {
            switch self {
            case .add: "add"
            case .edit: "edit"
            case .delete: "delete"
            case .filter: "filter"
            }
        }
    }

    private var displayName: String {
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Your Home" : "\(name)’s Home"
    }

    var body: some View {
        ZStack {
            Theme.onboardingTwilightBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                tourHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        homeHeader
                        progressCard
                        filterRow
                        taskList
                        addButtonRow
                        coachCard
                    }
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
                tourNavigation
            }
        }
        .foregroundStyle(Theme.cream)
        .accessibilityIdentifier("onboarding-page-home-tour")
    }

    private var tourHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Skip tour", action: onComplete)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.sky)
                    .accessibilityIdentifier("onboarding-tour-skip")

                Spacer()

                Text("\(onboardingPosition) of \(onboardingTotal)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.cream.opacity(0.65))
            }

            ProgressView(value: Double(onboardingPosition), total: Double(onboardingTotal))
                .tint(Theme.sky)
                .accessibilityLabel("Onboarding progress")
                .accessibilityValue("\(onboardingPosition) of \(onboardingTotal)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.hearthGold)
            Text("Good morning!")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("You’ve got \(tourTasks.count) tasks to tackle. You got this!")
                .font(.subheadline)
                .foregroundStyle(Theme.cream.opacity(0.68))
        }
        .opacity(step == .add ? 0.56 : 0.34)
    }

    private var progressCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.hearthGold.opacity(0.18))
                Image(systemName: "flame.fill")
                    .foregroundStyle(Theme.hearthGold)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Today’s progress")
                    .font(.headline)
                ProgressView(value: 0, total: Double(max(tourTasks.count, 1)))
                    .tint(Theme.hearthGold)
            }
            Spacer()
            Text("0 / \(tourTasks.count)")
                .font(.subheadline.weight(.bold))
        }
        .padding(14)
        .background(Theme.adventureBlue.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .opacity(0.38)
        .accessibilityHidden(true)
    }

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today’s quests")
                .font(.title3.weight(.bold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All", icon: "square.grid.2x2.fill", selected: true)
                    filterChip("Kitchen", icon: "fork.knife", selected: false)
                    filterChip("Living room", icon: "sofa.fill", selected: false)
                    filterChip("Laundry", icon: "washer.fill", selected: false)
                }
            }
        }
        .padding(10)
        .background(
            step == .filter ? Theme.adventureBlue.opacity(0.78) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .opacity(step == .filter ? 1 : 0.42)
        .accessibilityIdentifier("onboarding-tour-target-filter")
    }

    private func filterChip(_ title: String, icon: String, selected: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Theme.adventureBlue : Theme.cream.opacity(0.86))
            .background(selected ? Theme.cream : Theme.adventureBlue.opacity(0.72), in: Capsule())
    }

    private var taskList: some View {
        VStack(spacing: 9) {
            ForEach(Array(tourTasks.prefix(5).enumerated()), id: \.element.id) { index, task in
                taskRow(
                    task.name,
                    room: task.room ?? "Whole home",
                    icon: task.category.icon,
                    color: Theme.roomColor(task.room),
                    showsMenu: index == 0 && (step == .edit || step == .delete)
                )
            }
        }
        .opacity(step == .add || step == .filter ? 0.42 : 1)
    }

    private var tourTasks: [HouseholdTask] {
        if !tasks.isEmpty { return tasks }
        return [
            previewTask("Load the dishwasher", room: "Kitchen"),
            previewTask("Reset the living room", room: "Living room"),
            previewTask("Start a load of laundry", room: "Laundry"),
        ]
    }

    private func previewTask(_ name: String, room: String) -> HouseholdTask {
        var task = HouseholdTask(
            id: UUID(),
            name: name,
            description: "",
            category: .general,
            frequency: .daily,
            estimatedMinutes: 10,
            difficulty: .easy,
            supplies: [],
            isActive: true
        )
        task.room = room
        return task
    }

    private func taskRow(_ title: String, room: String, icon: String, color: Color, showsMenu: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(room).font(.caption).foregroundStyle(Theme.cream.opacity(0.58))
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(
                        (step == .edit || step == .delete) ? Theme.sky.opacity(0.22) : Color.clear,
                        in: Circle()
                    )
            }
            .padding(12)

            if showsMenu {
                Divider().overlay(Theme.cream.opacity(0.12))
                HStack(spacing: 8) {
                    menuChoice("Edit task", icon: "pencil", isActive: step == .edit, color: Theme.sky)
                    menuChoice("Delete task", icon: "trash", isActive: step == .delete, color: Theme.coral)
                }
                .padding(9)
            }
        }
        .background(Theme.adventureBlue.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(showsMenu ? Theme.sky.opacity(0.9) : Theme.cream.opacity(0.08), lineWidth: showsMenu ? 2 : 1)
        }
        .accessibilityIdentifier(showsMenu ? "onboarding-tour-target-\(step.accessibilityID)" : "")
    }

    private func menuChoice(_ title: String, icon: String, isActive: Bool, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 36)
            .foregroundStyle(isActive ? Theme.adventureBlue : Theme.cream.opacity(0.48))
            .background(isActive ? color : Theme.adventureBlue.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }

    private var addButtonRow: some View {
        HStack {
            Spacer()
            Label("Add task", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 17)
                .frame(minHeight: 48)
                .foregroundStyle(Theme.adventureBlue)
                .background(Theme.hearthGold, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.cream.opacity(step == .add ? 0.9 : 0), lineWidth: 3)
                }
                .shadow(color: Theme.hearthGold.opacity(step == .add ? 0.55 : 0), radius: 14)
                .opacity(step == .add ? 1 : 0.38)
                .accessibilityIdentifier("onboarding-tour-target-add")
        }
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(step.rawValue + 1) OF \(TourStep.allCases.count)")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(Theme.hearthGold)
            Text(step.title)
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(Theme.cream.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.sky.opacity(0.38))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding-tour-coach-\(step.accessibilityID)")
    }

    private var tourNavigation: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                ForEach(TourStep.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == step ? Theme.hearthGold : Theme.cream.opacity(0.22))
                        .frame(width: item == step ? 20 : 7, height: 7)
                }
            }

            Spacer()

            Button(action: advance) {
                HStack(spacing: 8) {
                    Text(step == .filter ? "Start using ADultingHD" : "Next")
                    Image(systemName: step == .filter ? "checkmark" : "arrow.right")
                }
                .font(.headline)
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .foregroundStyle(Theme.adventureBlue)
                .background(Theme.cream, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding-tour-next")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func advance() {
        guard let next = TourStep(rawValue: step.rawValue + 1) else {
            onComplete()
            return
        }
        if reduceMotion {
            step = next
        } else {
            withAnimation(.easeInOut(duration: 0.24)) { step = next }
        }
    }
}
