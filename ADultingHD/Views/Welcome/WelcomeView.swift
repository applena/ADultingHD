import SwiftUI

struct WelcomeView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var currentPage = 0
    @State private var isCompletingStarterTask = false
    @State private var starterXPMessage: String?
    @State private var showProUpgrade = false
    @AppStorage("onboardingHouseholdName") private var householdName: String = "My Household"

    let onComplete: () -> Void

    private struct PageMeta {
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let primaryButtonTitle: String
    }

    private let pages: [PageMeta] = [
        PageMeta(
            icon: "house.fill", color: Theme.coral,
            title: "Welcome to\nADultingHD!",
            subtitle: "We keep day one simple: just a couple daily tasks so you can build momentum, not stress.",
            primaryButtonTitle: "Show Me How"
        ),
        PageMeta(
            icon: "bolt.fill", color: Theme.xpGold,
            title: "How Adulting Works",
            subtitle: "Every chore you finish moves the game forward.",
            primaryButtonTitle: "Next"
        ),
        PageMeta(
            icon: "square.grid.3x3.fill", color: Theme.levelPurple,
            title: "Every Room, Covered",
            subtitle: "Kitchen, laundry, yard work — ADultingHD comes stocked with 50+ tasks across these categories.",
            primaryButtonTitle: "Next"
        ),
        PageMeta(
            icon: "person.3.fill", color: Theme.accent,
            title: "Name Your Household",
            subtitle: "Give it a name. This is where you and your people will track your adulting wins.",
            primaryButtonTitle: "Create Household"
        ),
        PageMeta(
            icon: "crown.fill", color: Theme.xpGold,
            title: "Unlock the Whole House",
            subtitle: "Pro is a one-time unlock — no subscriptions.",
            primaryButtonTitle: "Maybe Later"
        ),
        PageMeta(
            icon: "sparkles", color: Theme.successGreen,
            title: "Start Small",
            subtitle: "Your first quest is quick. Finish it once and instantly see the XP you earned.",
            primaryButtonTitle: "Start My Day"
        ),
    ]

    private var page: PageMeta { pages[currentPage] }

    private var starterTask: HouseholdTask? {
        dataStore.tasks.first { $0.name == "Wipe the counters" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(systemName: page.icon)
                .font(.system(size: 74))
                .foregroundStyle(page.color)
                .contentTransition(.symbolEffect(.replace))
                .padding(.bottom, 24)

            Text(page.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 10)

            Text(page.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            pageContent
                .frame(maxWidth: 360)
                .padding(.top, 18)
                .padding(.horizontal, 24)

            Spacer(minLength: 24)

            Button {
                handlePrimaryAction()
            } label: {
                Text(page.primaryButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 16)
                    .background(page.color, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(primaryButtonDisabled)

            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentPage ? page.color : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                        .scaleEffect(i == currentPage ? 1.2 : 1.0)
                }
            }
            .padding(.top, 18)
            .animation(.spring(response: 0.3), value: currentPage)

            Button {
                if currentPage > 0 {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        currentPage -= 1
                    }
                } else {
                    onComplete()
                }
            } label: {
                Text(currentPage > 0 ? "Back" : "Skip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [page.color.opacity(0.10), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)
        }
        .sheet(isPresented: $showProUpgrade) { ProUpgradeView() }
    }

    // MARK: - Per-page content

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case 1: howItWorksContent
        case 2: categoriesContent
        case 3: householdSetupContent
        case 4: proPitchContent
        case 5: starterTaskContent
        default: EmptyView()
        }
    }

    private var howItWorksContent: some View {
        VStack(spacing: 14) {
            loopRow(icon: "checkmark.circle.fill", color: Theme.successGreen,
                    title: "Complete tasks", subtitle: "Tap done when you finish a chore")
            loopRow(icon: "bolt.fill", color: Theme.xpGold,
                    title: "Earn XP", subtitle: "Harder tasks are worth more points")
            loopRow(icon: "flame.fill", color: Theme.streakOrange,
                    title: "Build streaks", subtitle: "Consistency adds bonus XP")
            loopRow(icon: "star.circle.fill", color: Theme.levelPurple,
                    title: "Level up", subtitle: "Unlock titles, achievements, and avatar gear")
        }
    }

    private func loopRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var categoriesContent: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(TaskCategory.allCases) { category in
                VStack(spacing: 6) {
                    Image(systemName: category.icon)
                        .font(.title2)
                        .foregroundStyle(page.color)
                    Text(category.rawValue)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var householdSetupContent: some View {
        VStack(spacing: 12) {
            TextField("Household name", text: $householdName)
                .textFieldStyle(.roundedBorder)
                .font(.body)
            Text("You can rename this anytime from Settings.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var proPitchContent: some View {
        VStack(spacing: 12) {
            pitchRow(icon: "house.fill", text: "Manage multiple households — home, cabin, rental")
            pitchRow(icon: "person.2.badge.key.fill", text: "Invite iCloud collaborators so the whole family stays in sync")
            pitchRow(icon: "chart.line.uptrend.xyaxis", text: "Advanced stats, full avatar shop, unlimited custom tasks")
            Button {
                showProUpgrade = true
            } label: {
                HStack(spacing: 6) {
                    Text("Learn more about Pro")
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.xpGold)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }

    private func pitchRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.xpGold)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }

    private var starterTaskContent: some View {
        VStack(spacing: 12) {
            Button {
                completeStarterTask()
            } label: {
                HStack {
                    if isCompletingStarterTask {
                        ProgressView()
                    } else {
                        Image(systemName: starterXPMessage == nil ? "sparkles" : "checkmark.circle.fill")
                    }
                    Text(starterXPMessage == nil ? "Complete: Wipe the counters" : "Starter task complete")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isCompletingStarterTask || starterXPMessage != nil)

            if let starterXPMessage {
                Text(starterXPMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.successGreen)
            }
        }
    }

    // MARK: - Navigation logic

    private func handlePrimaryAction() {
        if currentPage == pages.count - 1 {
            onComplete()
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentPage += 1
            }
        }
    }

    private var primaryButtonDisabled: Bool {
        // Last page is the starter task — require it to complete before continuing.
        currentPage == pages.count - 1 && starterXPMessage == nil
    }

    private func completeStarterTask() {
        guard let task = starterTask else {
            starterXPMessage = "Nice! Your starter task is ready on Home."
            return
        }

        let beforeXP = dataStore.profile.totalXP
        isCompletingStarterTask = true

        Task {
            await dataStore.completeTask(task)
            let gained = max(dataStore.profile.totalXP - beforeXP, task.xpReward)
            starterXPMessage = "+\(gained) XP earned for finishing \"\(task.name)\""
            isCompletingStarterTask = false
        }
    }
}
