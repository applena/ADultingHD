import SwiftUI
import CloudKit

struct WelcomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    @State private var currentPageIndex = 0
    @State private var showProUpgrade = false
    @State private var selectedCategories: Set<TaskCategory> = Set(TaskCategory.allCases)
    @State private var inviteError: String?
    @State private var isGeneratingInvite = false
    @State private var shareSheetPayload: ShareSheetPayload?
    @State private var hasSentInvite = false
    @AppStorage(PrefKey.onboardingHouseholdName) private var householdName: String = "My Household"
    @AppStorage(PrefKey.onboardingPlayerName) private var playerName: String = ""

    private struct ShareSheetPayload: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
        let householdName: String
    }

    let onComplete: () -> Void

    // MARK: - Pages

    private enum Page {
        case welcome, howItWorks, categories, nameHousehold,
             pickRooms, proPitch, invite
    }

    private var pages: [Page] {
        var result: [Page] = [
            .welcome, .howItWorks, .categories, .nameHousehold,
            .pickRooms, .proPitch,
        ]
        if Features.cloudKitSharing { result.append(.invite) }
        return result
    }

    private var currentPage: Page { pages[currentPageIndex] }

    private func meta(for page: Page) -> PageMeta {
        switch page {
        case .welcome:
            return PageMeta(
                icon: "house.fill", color: Theme.coral,
                title: "Welcome to ADultingHD!",
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
                title: "Who's Adulting?",
                subtitle: "Your name shows up on the leaderboard. The household name is where you track your wins together.",
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
                primaryButtonTitle: inviteButtonTitle
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

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    Image(systemName: page.icon)
                        .font(.system(size: 74, weight: .regular))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundStyle(page.color)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.bottom, 24)

                    Text(page.title)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 10)

                    Text(page.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
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
                                Text(page.primaryButtonTitle)
                                    .font(.headline)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: 280)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
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
                .frame(minHeight: geo.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
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
        .sheet(item: $shareSheetPayload) { payload in
            CloudShareSheet(
                share: payload.share,
                container: payload.container,
                householdName: payload.householdName,
                onDismiss: {
                    hasSentInvite = true
                    shareSheetPayload = nil
                }
            )
        }
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
                .frame(minWidth: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            TextField("Your name", text: $playerName)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                #if os(iOS)
                .textContentType(.givenName)
                .autocorrectionDisabled(true)
                #endif
                .onAppear {
                    if playerName.isEmpty {
                        let suggested = UserProfile.defaultPlayerName()
                        let current = dataStore.profile.name
                        playerName = !current.isEmpty && current != "Player 1" ? current : suggested
                    }
                }
            TextField("Household name", text: $householdName)
                .textFieldStyle(.roundedBorder)
                .font(.body)
            Text("You can change either of these anytime from Settings.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var roomPickerContent: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TaskCategory.allCases) { category in
                let selected = selectedCategories.contains(category)
                let color = Theme.categoryColor(category)
                Button {
                    if selected { selectedCategories.remove(category) }
                    else { selectedCategories.insert(category) }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.title3)
                                .foregroundStyle(selected ? .white : .secondary)
                            Text(category.rawValue)
                                .font(.caption2.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(selected ? .white : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selected ? color : Color.secondary.opacity(0.08))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    selected ? Color.clear : Color.secondary.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [4, 3])
                                )
                        }
                        .opacity(selected ? 1.0 : 0.55)

                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white, color)
                                .padding(4)
                        }
                    }
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
                .frame(minWidth: 26)
            Text(text)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    @ViewBuilder
    private var inviteContent: some View {
        if let inviteError {
            Text(inviteError)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else if hasSentInvite {
            Label("Invite sent", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.successGreen)
        }
    }

    private var inviteButtonTitle: String {
        if isGeneratingInvite { return "Preparing…" }
        if hasSentInvite { return "Send another invite" }
        return "Pick someone to invite"
    }

    // MARK: - Navigation logic

    private func handlePrimaryAction() {
        switch currentPage {
        case .nameHousehold:
            let enteredHousehold = householdName
            let enteredPlayer = playerName
            Task {
                await dataStore.renameActiveProfile(to: enteredPlayer)
                await dataStore.renameHousehold(dataStore.activeHouseholdId, to: enteredHousehold)
                advanceOrComplete()
            }
        case .pickRooms:
            Task {
                await dataStore.filterTasks(toCategories: selectedCategories)
                advanceOrComplete()
            }
        case .proPitch:
            if storeManager.isPro {
                advanceOrComplete()
            } else {
                Task {
                    await storeManager.purchase()
                    if storeManager.isPro { advanceOrComplete() }
                }
            }
        case .invite:
            Task { await presentShareSheet() }
        default:
            advanceOrComplete()
        }
    }

    private func advanceOrComplete() {
        if currentPageIndex >= pages.count - 1 {
            onComplete()
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentPageIndex += 1
            }
        }
    }

    private func handleSecondaryAction() {
        if currentPage == .invite {
            advanceOrComplete()
            return
        }
        if currentPageIndex > 0 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentPageIndex -= 1
            }
        } else {
            onComplete()
        }
    }

    private var secondaryLabel: String {
        if currentPage == .invite { return hasSentInvite ? "Done, Next" : "Skip for now" }
        return currentPageIndex > 0 ? "Back" : "Skip"
    }

    private var primaryButtonDisabled: Bool {
        switch currentPage {
        case .nameHousehold:
            return playerName.trimmingCharacters(in: .whitespaces).isEmpty
                || householdName.trimmingCharacters(in: .whitespaces).isEmpty
        case .pickRooms: return selectedCategories.isEmpty
        case .proPitch:
            // Disable only while a purchase is actively in flight. When the
            // product hasn't loaded (e.g. offline) the primary still routes
            // through to purchase() which will surface its own error.
            return storeManager.isPurchasing
        case .invite: return isGeneratingInvite
        default: return false
        }
    }

    private func presentShareSheet() async {
        inviteError = nil
        isGeneratingInvite = true
        defer { isGeneratingInvite = false }
        do {
            let (share, container) = try await dataStore.prepareHouseholdShare()
            shareSheetPayload = ShareSheetPayload(
                share: share,
                container: container,
                householdName: dataStore.activeHousehold.name
            )
        } catch {
            inviteError = error.localizedDescription
        }
    }

}
