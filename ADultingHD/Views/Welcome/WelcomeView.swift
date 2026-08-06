import SwiftUI
import CloudKit

struct WelcomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var currentPageIndex = 0
    @State private var showProUpgrade = false
    @State private var selectedCategories: Set<TaskCategory> = Set(TaskCategory.allCases)
    @State private var inviteError: String?
    @State private var isGeneratingInvite = false
    @State private var shareSheetPayload: ShareSheetPayload?
    @State private var hasSentInvite = false
    @AppStorage(PrefKey.onboardingHouseholdName) private var householdName = "My Household"
    @AppStorage(PrefKey.onboardingPlayerName) private var playerName = ""

    private struct ShareSheetPayload: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
        let householdName: String
    }

    let onComplete: () -> Void

    private enum Page: Equatable {
        case welcome, howItWorks, categories, nameHousehold
        case pickRooms, proPitch, invite

        var accessibilityID: String {
            switch self {
            case .welcome: "welcome"
            case .howItWorks: "how-it-works"
            case .categories: "categories"
            case .nameHousehold: "name-household"
            case .pickRooms: "pick-rooms"
            case .proPitch: "pro-pitch"
            case .invite: "invite"
            }
        }
    }

    private struct PageMeta {
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let primaryButtonTitle: String
    }

    private var pages: [Page] {
        var result: [Page] = [
            .welcome, .howItWorks, .categories, .nameHousehold,
            .pickRooms, .proPitch,
        ]
        if Features.cloudKitSharing && storeManager.isPro { result.append(.invite) }
        return result
    }

    private var currentPage: Page { pages[currentPageIndex] }
    private var page: PageMeta { meta(for: currentPage) }

    private func meta(for page: Page) -> PageMeta {
        switch page {
        case .welcome:
            return PageMeta(
                icon: "house.fill", color: Theme.hearthGold,
                title: "Make home feel lighter",
                subtitle: "Turn the rooms you use into a short, shared quest—with clear next steps and visible progress.",
                primaryButtonTitle: "Set up my home"
            )
        case .howItWorks:
            return PageMeta(
                icon: "sparkles", color: Theme.hearthGold,
                title: "A simple daily loop",
                subtitle: "Pick a useful task, finish it, and watch your household momentum grow.",
                primaryButtonTitle: "Show me the rooms"
            )
        case .categories:
            return PageMeta(
                icon: "square.grid.3x3.fill", color: Theme.levelPurple,
                title: "Every room has a quest",
                subtitle: "Start with a practical whole-home catalog. You can trim it to fit your space in the next step.",
                primaryButtonTitle: "Personalize my setup"
            )
        case .nameHousehold:
            return PageMeta(
                icon: "person.3.fill", color: Theme.leafGreen,
                title: "Name your home base",
                subtitle: "These names make completions, leaderboards, and shared household progress feel like yours.",
                primaryButtonTitle: "Create household"
            )
        case .pickRooms:
            return PageMeta(
                icon: "checkmark.square.fill", color: Theme.sky,
                title: "Choose your rooms",
                subtitle: "Keep this first quest log focused. You can add or remove tasks whenever you like.",
                primaryButtonTitle: "Build my quest log"
            )
        case .proPitch:
            let priceLabel = storeManager.proProduct?.displayPrice ?? "$9.99"
            return PageMeta(
                icon: "crown.fill", color: Theme.hearthGold,
                title: "Make it a household adventure",
                subtitle: "One-time \(priceLabel). Share tasks, manage more homes, and unlock the full experience—never a subscription.",
                primaryButtonTitle: storeManager.isPro ? "You're Pro — continue" : "Unlock Pro — \(priceLabel)"
            )
        case .invite:
            return PageMeta(
                icon: "person.crop.circle.badge.plus", color: Theme.leafGreen,
                title: "Bring in your party",
                subtitle: "Share an iCloud invite so everyone sees the same tasks, completions, and leaderboard.",
                primaryButtonTitle: inviteButtonTitle
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScreenBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        onboardingProgress
                            .padding(.horizontal, 4)

                        artwork(width: geometry.size.width)

                        VStack(alignment: .leading, spacing: 20) {
                            pageHeading
                            pageContent
                        }
                        .padding(compactLayout(for: geometry.size.width) ? 18 : 26)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(page.color.opacity(0.18))
                        }

                        onboardingActions
                    }
                    .frame(width: contentWidth(for: geometry.size.width))
                    .padding(.horizontal, compactLayout(for: geometry.size.width) ? 16 : 28)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .id(currentPageIndex)
            }
        }
        .accessibilityIdentifier("onboarding-page-\(currentPage.accessibilityID)")
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

    private func compactLayout(for width: CGFloat) -> Bool { width < 600 }

    private func contentWidth(for width: CGFloat) -> CGFloat {
        let sidePadding: CGFloat = compactLayout(for: width) ? 32 : 56
        return min(max(width - sidePadding, 0), Theme.onboardingContentMaxWidth)
    }

    private var stepLabel: String { "Step \(currentPageIndex + 1) of \(pages.count)" }

    private var onboardingProgress: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("ADultingHD", systemImage: "house.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(stepLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(currentPageIndex + 1), total: Double(pages.count))
                .tint(page.color)
                .accessibilityLabel("Setup progress")
                .accessibilityValue(stepLabel)
        }
    }

    @ViewBuilder
    private func artwork(width: CGFloat) -> some View {
        switch currentPage {
        case .welcome:
            onboardingImage(
                "Onboarding/WelcomeHeroV1",
                label: "A warmly lit home at night with a glowing path connecting each room",
                height: compactLayout(for: width) ? 275 : 390,
                alignment: .center
            )
        case .howItWorks:
            onboardingImage(
                "Onboarding/DailyLoopV1",
                label: "A chore card leading to a completed task and a gold reward",
                height: compactLayout(for: width) ? 210 : 310,
                alignment: .center
            )
        default:
            decorativeBanner
        }
    }

    private func onboardingImage(
        _ name: String,
        label: String,
        height: CGFloat,
        alignment: Alignment
    ) -> some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: alignment)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, Theme.adventureBlue.opacity(0.15)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius)
                    .strokeBorder(.white.opacity(0.18))
            }
            .shadow(color: Theme.adventureBlue.opacity(0.16), radius: 18, y: 8)
            .accessibilityLabel(label)
    }

    private var decorativeBanner: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius)
                .fill(
                    LinearGradient(
                        colors: [page.color.opacity(0.24), Theme.parchment.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(page.color.opacity(0.18))
                .offset(x: -110, y: -18)
                .accessibilityHidden(true)

            ZStack {
                Circle()
                    .fill(.background.opacity(0.82))
                    .frame(width: 104, height: 104)
                Image(systemName: page.icon)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(page.color)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            Image(systemName: "sparkle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.hearthGold.opacity(0.42))
                .offset(x: 118, y: 30)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 154)
        .accessibilityHidden(true)
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(stepEyebrow.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(colorSchemeContrast == .increased ? Color.primary : page.color)
            Text(page.title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(page.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepEyebrow: String {
        switch currentPage {
        case .welcome: "Welcome home"
        case .howItWorks: "Your daily rhythm"
        case .categories: "The quest map"
        case .nameHousehold: "Your home base"
        case .pickRooms: "Choose your scope"
        case .proPitch: "Optional upgrade"
        case .invite: "Share the load"
        }
    }

    private var onboardingActions: some View {
        VStack(spacing: 10) {
            Button(action: handlePrimaryAction) {
                Group {
                    if currentPage == .proPitch && storeManager.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Text(page.primaryButtonTitle)
                            Image(systemName: "arrow.right")
                                .accessibilityHidden(true)
                        }
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 16)
                .background(Theme.adventureBlue, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(primaryButtonDisabled)
            .opacity(primaryButtonDisabled ? 0.58 : 1)
            .accessibilityIdentifier("onboarding-primary-action")

            Button(action: handleSecondaryAction) {
                Text(secondaryLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding-secondary-action")
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case .welcome: welcomeContent
        case .howItWorks: howItWorksContent
        case .categories: categoriesContent
        case .nameHousehold: householdSetupContent
        case .pickRooms: roomPickerContent
        case .proPitch: proPitchContent
        case .invite: inviteContent
        }
    }

    private var welcomeContent: some View {
        HStack(spacing: 8) {
            featurePill("Short lists", icon: "list.bullet.clipboard", color: Theme.coral)
            featurePill("Shared wins", icon: "person.2.fill", color: Theme.leafGreen)
            featurePill("Real progress", icon: "sparkles", color: Theme.hearthGold)
        }
        .accessibilityElement(children: .contain)
    }

    private func featurePill(_ title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(.horizontal, 6)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private var howItWorksContent: some View {
        VStack(spacing: 10) {
            loopRow(number: "1", icon: "rectangle.stack.fill", color: Theme.coral,
                    title: "Pick a quest", subtitle: "Choose the next useful task")
            loopRow(number: "2", icon: "checkmark.circle.fill", color: Theme.successGreen,
                    title: "Make progress", subtitle: "Tap done when the task is finished")
            loopRow(number: "3", icon: "star.circle.fill", color: Theme.hearthGold,
                    title: "Earn momentum", subtitle: "Build XP, streaks, and shared wins")
        }
    }

    private func loopRow(
        number: String, icon: String, color: Color, title: String, subtitle: String
    ) -> some View {
        HStack(spacing: 13) {
            Text(number)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.adventureBlue, in: Circle())
                .accessibilityHidden(true)
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var categoriesContent: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
            ForEach(TaskCategory.allCases) { category in
                VStack(spacing: 7) {
                    Image(systemName: category.icon)
                        .font(.title2)
                        .foregroundStyle(Theme.categoryColor(category))
                        .accessibilityHidden(true)
                    Text(category.rawValue)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(.horizontal, 5)
                .background(
                    Theme.categoryColor(category).opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
        }
    }

    private var householdSetupContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            labeledField("Your name", icon: "person.fill") {
                TextField("Your name", text: $playerName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding-player-name-field")
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
            }
            labeledField("Household name", icon: "house.fill") {
                TextField("Household name", text: $householdName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding-household-name-field")
            }
            Label("Change either name anytime in Settings.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func labeledField<Content: View>(
        _ label: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            content()
                .font(.body)
        }
    }

    private var roomPickerContent: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(TaskCategory.allCases) { category in
                let selected = selectedCategories.contains(category)
                let color = Theme.categoryColor(category)
                let selectedForeground = roomSelectionForeground(for: category)
                Button {
                    if selected { selectedCategories.remove(category) }
                    else { selectedCategories.insert(category) }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 7) {
                            Image(systemName: category.icon)
                                .font(.title3)
                                .accessibilityHidden(true)
                            Text(category.rawValue)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(selected ? selectedForeground : color)
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .padding(.horizontal, 5)
                        .background(
                            selected ? color : color.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(color.opacity(selected ? 0 : 0.34), lineWidth: 1)
                        }

                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(7)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.rawValue)
                .accessibilityValue(selected ? "Included" : "Not included")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func roomSelectionForeground(for category: TaskCategory) -> Color {
        switch category {
        case .bedroom, .garage, .office:
            return .white
        default:
            return Theme.adventureBlue
        }
    }

    private var proPitchContent: some View {
        VStack(spacing: 10) {
            pitchRow(icon: "house.fill", text: "Manage multiple homes")
            pitchRow(icon: "person.2.badge.key.fill", text: "Share tasks with iCloud collaborators")
            pitchRow(icon: "chart.line.uptrend.xyaxis", text: "Unlock advanced stats, avatar gear, and custom tasks")
            if let message = storeManager.failureMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                showProUpgrade = true
            } label: {
                Label("See everything in Pro", systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private func pitchRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.hearthGold)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.hearthGold.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var inviteContent: some View {
        if let inviteError {
            Label(inviteError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else if hasSentInvite {
            Label("Invite sent", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.successGreen)
        } else {
            Label("Invites use Apple's private iCloud sharing.", systemImage: "lock.shield.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var inviteButtonTitle: String {
        if isGeneratingInvite { return "Preparing…" }
        if hasSentInvite { return "Send another invite" }
        return "Pick someone to invite"
    }

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
                await dataStore.seedOnboardingTasks(categories: selectedCategories)
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
            updatePageIndex(to: currentPageIndex + 1)
        }
    }

    private func handleSecondaryAction() {
        if currentPage == .invite || currentPage == .proPitch {
            advanceOrComplete()
        } else if currentPageIndex > 0 {
            updatePageIndex(to: currentPageIndex - 1)
        } else {
            onComplete()
        }
    }

    private func updatePageIndex(to index: Int) {
        if reduceMotion {
            currentPageIndex = index
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                currentPageIndex = index
            }
        }
    }

    private var secondaryLabel: String {
        if currentPage == .invite { return hasSentInvite ? "Done" : "Skip for now" }
        if currentPage == .proPitch { return "Continue without Pro" }
        return currentPageIndex > 0 ? "Back" : "Skip setup"
    }

    private var primaryButtonDisabled: Bool {
        switch currentPage {
        case .nameHousehold:
            playerName.trimmingCharacters(in: .whitespaces).isEmpty
                || householdName.trimmingCharacters(in: .whitespaces).isEmpty
        case .pickRooms:
            selectedCategories.isEmpty
        case .proPitch:
            storeManager.isPurchasing
        case .invite:
            isGeneratingInvite
        default:
            false
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
