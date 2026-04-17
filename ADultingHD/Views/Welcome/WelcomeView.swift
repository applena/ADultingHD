import SwiftUI

struct WelcomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    @State private var currentPageIndex = 0
    @State private var isCompletingStarterTask = false
    @State private var starterXPMessage: String?
    @State private var showProUpgrade = false
    @State private var selectedCategories: Set<TaskCategory> = Set(TaskCategory.allCases)
    @State private var inviteURL: URL?
    @State private var inviteError: String?
    @State private var isGeneratingInvite = false
    @AppStorage(PrefKey.onboardingHouseholdName) private var householdName: String = "My Household"

    let onComplete: () -> Void

    // MARK: - Pages

    private enum Page {
        case welcome, howItWorks, categories, nameHousehold,
             pickRooms, proPitch, invite, starterTask
    }

    private var pages: [Page] {
        var result: [Page] = [
            .welcome, .howItWorks, .categories, .nameHousehold,
            .pickRooms, .proPitch,
        ]
        if Features.cloudKitSharing { result.append(.invite) }
        result.append(.starterTask)
        return result
    }

    private var currentPage: Page { pages[currentPageIndex] }

    private func meta(for page: Page) -> PageMeta {
        switch page {
        case .welcome:
            return PageMeta(
                icon: "house.fill", color: Theme.coral,
                title: "Welcome to\nADultingHD!",
                subtitle: "We keep day one simple: just a couple daily tasks so you can build momentum, not stress.",
                primaryButtonTitle: "Show Me How"
            )
        case .howItWorks:
            return PageMeta(
                icon: "bolt.fill", color: Theme.xpGold,
                title: "How Adulting Works",
                subtitle: "Every chore you finish moves the game forward.",
                primaryButtonTitle: "Next"
            )
        case .categories:
            return PageMeta(
                icon: "square.grid.3x3.fill", color: Theme.levelPurple,
                title: "Every Room, Covered",
                subtitle: "Kitchen, laundry, yard work — ADultingHD comes stocked with 50+ tasks across these categories.",
                primaryButtonTitle: "Next"
            )
        case .nameHousehold:
            return PageMeta(
                icon: "person.3.fill", color: Theme.accent,
                title: "Name Your Household",
                subtitle: "Give it a name. This is where you'll track your adulting wins.",
                primaryButtonTitle: "Create Household"
            )
        case .pickRooms:
            return PageMeta(
                icon: "checkmark.square.fill", color: Theme.sky,
                title: "Pick Your Rooms",
                subtitle: "Tap a room to toggle it. We'll only set up tasks for the rooms you actually have.",
                primaryButtonTitle: "Next"
            )
        case .proPitch:
            let priceLabel = storeManager.proProduct?.displayPrice ?? "$9.99"
            return PageMeta(
                icon: "crown.fill", color: Theme.xpGold,
                title: "Unlock the Whole House",
                subtitle: "Pro is a one-time unlock — no subscriptions.",
                primaryButtonTitle: storeManager.isPro ? "You're Pro — Next" : "Upgrade — \(priceLabel)"
            )
        case .invite:
            return PageMeta(
                icon: "person.crop.circle.badge.plus", color: Theme.accent,
                title: "Invite Your Household",
                subtitle: "Share a link so the people you live with can join on their own device. They'll see the same tasks and compete on the leaderboard.",
                primaryButtonTitle: "Next"
            )
        case .starterTask:
            return PageMeta(
                icon: "sparkles", color: Theme.successGreen,
                title: "Start Small",
                subtitle: "Your first quest is quick. Finish it once and instantly see the XP you earned.",
                primaryButtonTitle: "Start My Day"
            )
        }
    }

    private struct PageMeta {
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let primaryButtonTitle: String
    }

    private var page: PageMeta { meta(for: currentPage) }

    private var starterTask: HouseholdTask? {
        dataStore.tasks.first { $0.name == "Wipe the counters" }
            ?? dataStore.activeTasks.first
    }

    // MARK: - Body

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
                Group {
                    if currentPage == .proPitch && storeManager.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(page.primaryButtonTitle).font(.headline)
                    }
                }
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
                        .fill(i == currentPageIndex ? page.color : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                        .scaleEffect(i == currentPageIndex ? 1.2 : 1.0)
                }
            }
            .padding(.top, 18)
            .animation(.spring(response: 0.3), value: currentPageIndex)

            Button {
                handleSecondaryAction()
            } label: {
                Text(secondaryLabel)
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
            .animation(.easeInOut(duration: 0.5), value: currentPageIndex)
        }
        .sheet(isPresented: $showProUpgrade) { ProUpgradeView() }
    }

    // MARK: - Per-page content

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case .howItWorks: howItWorksContent
        case .categories: categoriesContent
        case .nameHousehold: householdSetupContent
        case .pickRooms: roomPickerContent
        case .proPitch: proPitchContent
        case .invite: inviteContent
        case .starterTask: starterTaskContent
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

    private var roomPickerContent: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TaskCategory.allCases) { category in
                let selected = selectedCategories.contains(category)
                Button {
                    if selected { selectedCategories.remove(category) }
                    else { selectedCategories.insert(category) }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: category.icon)
                            .font(.title3)
                            .foregroundStyle(selected ? .white : Theme.categoryColor(category))
                        Text(category.rawValue)
                            .font(.caption2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selected ? Theme.categoryColor(category) : Color.secondary.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var proPitchContent: some View {
        VStack(spacing: 12) {
            pitchRow(icon: "house.fill", text: "Manage multiple households — home, cabin, rental")
            pitchRow(icon: "person.2.badge.key.fill", text: "Invite iCloud collaborators so the whole family stays in sync")
            pitchRow(icon: "chart.line.uptrend.xyaxis", text: "Advanced stats, full avatar shop, unlimited custom tasks")
            if let message = storeManager.failureMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                showProUpgrade = true
            } label: {
                HStack(spacing: 6) {
                    Text("See everything in Pro")
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

    @ViewBuilder
    private var inviteContent: some View {
        VStack(spacing: 12) {
            if let url = inviteURL {
                ShareLink(
                    item: url,
                    subject: Text("Join my household in ADultingHD"),
                    message: Text("Tap this link to join my household. We'll share chores, XP, and the leaderboard.")
                ) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await generateInvite() }
                } label: {
                    HStack {
                        if isGeneratingInvite {
                            ProgressView()
                        } else {
                            Image(systemName: "link.badge.plus")
                        }
                        Text("Generate invite link").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingInvite)
            }
            if let inviteError {
                Text(inviteError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
                    Text(starterXPMessage == nil ? starterButtonTitle : "Starter task complete")
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

    private var starterButtonTitle: String {
        if let task = starterTask {
            return "Complete: \(task.name)"
        }
        return "Mark starter done"
    }

    // MARK: - Navigation logic

    private func handlePrimaryAction() {
        switch currentPage {
        case .nameHousehold:
            // The household was created with a default name at first launch,
            // before the user saw this screen. Push the entered name onto it
            // so the header and Settings reflect their choice.
            let entered = householdName
            Task {
                await dataStore.renameHousehold(dataStore.activeHouseholdId, to: entered)
                advance()
            }
        case .pickRooms:
            // Await the filter so the starter-task step sees the final
            // task list — otherwise a fast tapper could hit the starter
            // button before the save completes.
            Task {
                await dataStore.filterTasks(toCategories: selectedCategories)
                advance()
            }
        case .proPitch:
            if storeManager.isPro {
                advance()
            } else {
                Task {
                    await storeManager.purchase()
                    if storeManager.isPro { advance() }
                }
            }
        case .starterTask:
            onComplete()
        default:
            if currentPageIndex == pages.count - 1 { onComplete() }
            else { advance() }
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentPageIndex += 1
        }
    }

    private func handleSecondaryAction() {
        if currentPageIndex > 0 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentPageIndex -= 1
            }
        } else {
            onComplete()
        }
    }

    private var secondaryLabel: String {
        // Allow skipping the invite step entirely — cross-device invites are
        // optional and the user can do it later from Households.
        if currentPage == .invite { return inviteURL == nil ? "Skip for now" : "Done, Next" }
        return currentPageIndex > 0 ? "Back" : "Skip"
    }

    private var primaryButtonDisabled: Bool {
        switch currentPage {
        case .pickRooms: return selectedCategories.isEmpty
        case .proPitch:
            // Disable only while a purchase is actively in flight. When the
            // product hasn't loaded (e.g. offline) the primary still routes
            // through to purchase() which will surface its own error.
            return storeManager.isPurchasing
        case .starterTask: return starterXPMessage == nil
        default: return false
        }
    }

    private func generateInvite() async {
        inviteError = nil
        isGeneratingInvite = true
        defer { isGeneratingInvite = false }
        let result = await dataStore.generateHouseholdInvite()
        inviteURL = result.url
        inviteError = result.errorMessage
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
