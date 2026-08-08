import SwiftUI

struct WelcomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var currentPageIndex = 0
    @State private var selectedCategories = onboardingStarterCategories
    @State private var selectedTaskNames: Set<String> = []
    @State private var recommendedTasks: [CatalogTask] = []
    @State private var recommendedTaskGroups: [(category: TaskCategory, tasks: [CatalogTask])] = []
    @State private var selectedAvatarID = "person"
    @State private var isSavingSetup = false
    @AppStorage(PrefKey.onboardingHouseholdName) private var householdName = "My Household"
    @AppStorage(PrefKey.onboardingPlayerName) private var playerName = ""

    /// Keep first-run choices focused; the full task catalog remains available
    /// when people add tasks after onboarding. Every room here has a curated
    /// recommendation set, so picking one never lands on an empty quest list.
    private static let onboardingCategories: [TaskCategory] = [
        .kitchen, .bathroom, .livingRoom, .laundry, .general,
    ]

    let onComplete: () -> Void

    private enum Page: Equatable, CaseIterable {
        case welcome, dailyLoop, setup

        var accessibilityID: String {
            switch self {
            case .welcome: "welcome"
            case .dailyLoop: "daily-loop"
            case .setup: "setup"
            }
        }

        var title: String {
            switch self {
            case .welcome: "Start small. Feel lighter."
            case .dailyLoop: "Pick. Do. Done."
            case .setup: "Make it yours."
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "One next task at a time."
            case .dailyLoop: "Choose one task. Finish it. Feel the win."
            case .setup: "Add your name, pick a companion, keep a few starter quests."
            }
        }

        var primaryButtonTitle: String {
            switch self {
            case .welcome: "Get started"
            case .dailyLoop: "Next"
            case .setup: "Start my list"
            }
        }
    }

    private var pages: [Page] { Page.allCases }
    private var currentPage: Page { pages[currentPageIndex] }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        onboardingHeader
                        pageArtwork(width: geometry.size.width)
                        pageHeading
                        pageContent
                    }
                    .frame(width: contentWidth(for: geometry.size.width))
                    .padding(.horizontal, compactLayout(for: geometry.size.width) ? 16 : 28)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .frame(minHeight: max(0, geometry.size.height - 168), alignment: .center)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("onboarding-page-\(currentPage.accessibilityID)")
                .scrollBounceBehavior(.basedOnSize)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    onboardingActions
                }
            }
        }
        .onAppear(perform: prepareDefaults)
    }

    private func compactLayout(for width: CGFloat) -> Bool { width < 600 }

    private func contentWidth(for width: CGFloat) -> CGFloat {
        let sidePadding: CGFloat = compactLayout(for: width) ? 32 : 56
        return min(max(width - sidePadding, 0), Theme.onboardingContentMaxWidth)
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if currentPageIndex > 0 {
                    Button(action: goBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("onboarding-back-action")
                } else {
                    Label("ADultingHD", systemImage: "house.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                Text("\(currentPageIndex + 1) of \(pages.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Onboarding progress")
            }

            ProgressView(value: Double(currentPageIndex + 1), total: Double(pages.count))
                .tint(Theme.adventureBlue)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("\(currentPageIndex + 1) of \(pages.count)")
        }
    }

    @ViewBuilder
    private func pageArtwork(width: CGFloat) -> some View {
        switch currentPage {
        case .welcome:
            onboardingImage(
                "Onboarding/WelcomeFocusV1",
                label: "A small kitchen task leading to a gold progress star",
                height: compactLayout(for: width) ? 228 : 340
            )
        case .dailyLoop:
            onboardingImage(
                "Onboarding/DailyLoopV1",
                label: "Choosing a household task, doing the chore, and earning a reward",
                height: compactLayout(for: width) ? 206 : 300
            )
        case .setup:
            setupArtwork
        }
    }

    private func onboardingImage(_ name: String, label: String, height: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius)
                    .strokeBorder(Theme.adventureBlue.opacity(0.12))
            }
            .shadow(color: Theme.adventureBlue.opacity(0.12), radius: 16, y: 8)
            .accessibilityLabel(label)
    }

    private var setupArtwork: some View {
        HStack(spacing: 12) {
            setupRoomSymbol("fork.knife", color: Theme.hearthGold)
            Image(systemName: "arrow.right")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.hearthGold)
            setupRoomSymbol("shower", color: Theme.sky)
            Image(systemName: "arrow.right")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.hearthGold)
            setupRoomSymbol("washer", color: Theme.leafGreen)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.parchment.opacity(0.72), in: RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius))
        .accessibilityHidden(true)
    }

    private func setupRoomSymbol(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 68, height: 68)
            .background(color.opacity(0.13), in: Circle())
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currentPage.title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(currentPage.subtitle)
                .font(.title3)
                .foregroundStyle(colorSchemeContrast == .increased ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case .welcome, .dailyLoop:
            EmptyView()
        case .setup:
            setupContent
        }
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 10) {
                setupField("Your name", icon: "person.fill", text: $playerName)
                setupField("Household name", icon: "house.fill", text: $householdName)
            }

            companionPicker

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Rooms", detail: "\(selectedCategories.count) selected")
                roomPicker
            }

            starterQuestPicker
        }
        .padding(.bottom, Theme.controlHeight + 24)
        .onChange(of: selectedCategories) { previous, _ in
            refreshRecommendations(previousCategories: previous)
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
            Text(detail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func setupField(_ label: String, icon: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.adventureBlue)
                .frame(width: 24)
                .accessibilityHidden(true)

            TextField(label, text: text)
                .font(.body)
                .textFieldStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityIdentifier(
                    label == "Your name"
                        ? "onboarding-player-name-field"
                        : "onboarding-household-name-field"
                )
                #if os(iOS)
                .autocorrectionDisabled(true)
                #endif
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.controlHeight)
        .background(.background, in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                .strokeBorder(Theme.adventureBlue.opacity(0.16))
        }
    }

    // MARK: - Companion

    private static let starterAvatarItems: [AvatarItem] = avatarShopItems.filter { $0.cost == 0 }

    /// Each tile renders one item in isolation, so the throwaway states these
    /// need are identical on every pass — build them once.
    private static let starterAvatarPreviews: [String: AvatarState] = Dictionary(
        uniqueKeysWithValues: WelcomeView.starterAvatarItems.map { item in
            var state = AvatarState()
            state.purchase(item)
            state.equip(item)
            return (item.id, state)
        }
    )

    private var companionPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Companion", detail: "Change anytime")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                ForEach(Self.starterAvatarItems) { item in
                    let selected = selectedAvatarID == item.id
                    Button {
                        selectedAvatarID = item.id
                    } label: {
                        VStack(spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                AvatarView(avatarState: Self.starterAvatarPreviews[item.id] ?? AvatarState(), size: 58)
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Theme.successGreen)
                                        .background(.background, in: Circle())
                                }
                            }
                            Text(item.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 86)
                        .padding(.vertical, 6)
                        .background(
                            selected ? Theme.successGreen.opacity(0.12) : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                                .strokeBorder(selected ? Theme.successGreen : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Rooms

    private var roomPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(Self.onboardingCategories) { category in
                let selected = selectedCategories.contains(category)
                Button {
                    if selected {
                        selectedCategories.remove(category)
                    } else {
                        selectedCategories.insert(category)
                    }
                } label: {
                    roomTile(category, selected: selected)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
                .accessibilityLabel(category.rawValue)
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .accessibilityHint(selected ? "Double tap to remove this room" : "Double tap to add this room")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func roomTile(_ category: TaskCategory, selected: Bool) -> some View {
        let color = Theme.categoryColor(category)
        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.title3.weight(.semibold))
                    .accessibilityHidden(true)

                Text(category.rawValue)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.horizontal, 5)

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.semibold))
                .padding(7)
                .accessibilityHidden(true)
        }
        .foregroundStyle(selected ? roomSelectionForeground(for: category) : color)
        .frame(maxWidth: .infinity)
        .background(selected ? color : color.opacity(0.09), in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                .strokeBorder(color.opacity(selected ? 0 : 0.36), lineWidth: 1)
        }
    }

    private func roomSelectionForeground(for category: TaskCategory) -> Color {
        switch category {
        case .bedroom, .livingRoom, .laundry, .outdoor, .garage, .office:
            return .white
        default:
            return Theme.adventureBlue
        }
    }

    // MARK: - Starter quests

    private var selectedRecommendedTasks: [CatalogTask] {
        recommendedTasks.filter { selectedTaskNames.contains($0.name) }
    }

    private var selectedQuestMinutes: Int {
        recommendedTasks.reduce(0) { selectedTaskNames.contains($1.name) ? $0 + $1.estimatedMinutes : $0 }
    }

    private var starterQuestPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                "Starter quests",
                detail: "\(selectedTaskNames.count) selected · \(selectedQuestMinutes) min"
            )

            if recommendedTasks.isEmpty {
                Text("Pick at least one room to see suggested quests.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 16) {
                    Button("Select all") {
                        selectedTaskNames = Set(recommendedTasks.map(\.name))
                    }
                    Button("Clear all") {
                        selectedTaskNames.removeAll()
                    }
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.semibold))
                .frame(minHeight: 44)

                ForEach(recommendedTaskGroups, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(group.category.rawValue, systemImage: group.category.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.categoryColor(group.category))

                        ForEach(group.tasks) { task in
                            questRow(task)
                        }
                    }
                }
            }
        }
    }

    private func questRow(_ task: CatalogTask) -> some View {
        let selected = selectedTaskNames.contains(task.name)
        return Button {
            if selected {
                selectedTaskNames.remove(task.name)
            } else {
                selectedTaskNames.insert(task.name)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TaskMetadataRow(
                        frequency: task.suggestedFrequency,
                        difficulty: task.difficulty,
                        estimatedMinutes: task.estimatedMinutes
                    )
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.successGreen : .secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(
                selected ? Theme.successGreen.opacity(0.10) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                    .strokeBorder(selected ? Theme.successGreen.opacity(0.55) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.name). \(task.description)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Recomputes the cached recommendations for the current rooms and keeps the
    /// quest selection in step with them: rooms added since the last refresh
    /// contribute their top two suggestions, and quests whose room was removed
    /// drop out. Caching here rather than deriving in `body` keeps the catalog
    /// scan off the per-keystroke render path of the name fields.
    private func refreshRecommendations(previousCategories: Set<TaskCategory>) {
        let tasks = onboardingRecommendedCatalogTasks(for: selectedCategories)
        recommendedTasks = tasks
        recommendedTaskGroups = Dictionary(grouping: tasks, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (category: $0.key, tasks: $0.value) }

        let addedCategories = selectedCategories.subtracting(previousCategories)
        selectedTaskNames.formUnion(
            Dictionary(grouping: tasks.filter { addedCategories.contains($0.category) }, by: \.category)
                .values
                .flatMap { $0.prefix(2).map(\.name) }
        )
        selectedTaskNames.formIntersection(Set(tasks.map(\.name)))
    }

    // MARK: - Actions

    private var onboardingActions: some View {
        Button(action: handlePrimaryAction) {
            Group {
                if isSavingSetup {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Saving setup")
                } else {
                    HStack(spacing: 8) {
                        Text(currentPage.primaryButtonTitle)
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                }
            }
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
            .padding(.horizontal, 16)
            .background(Theme.adventureBlue, in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
            .foregroundStyle(.white)
            .contentShape(RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(primaryButtonDisabled)
        .opacity(primaryButtonDisabled ? 0.58 : 1)
        .accessibilityIdentifier("onboarding-primary-action")
        .accessibilityLabel(currentPage.primaryButtonTitle)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var primaryButtonDisabled: Bool {
        guard currentPage == .setup else { return isSavingSetup }
        return isSavingSetup
            || playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedCategories.isEmpty
            || selectedTaskNames.isEmpty
    }

    /// Runs once when onboarding appears — not per page, so returning to the
    /// setup page via Back does not discard choices made there.
    private func prepareDefaults() {
        if playerName.isEmpty {
            let suggested = UserProfile.defaultPlayerName()
            let current = dataStore.profile.name
            playerName = !current.isEmpty && current != "Player 1" ? current : suggested
        }
        selectedAvatarID = dataStore.profile.avatarState.equipped(slot: .character) ?? "person"
        refreshRecommendations(previousCategories: [])
    }

    private func handlePrimaryAction() {
        switch currentPage {
        case .welcome, .dailyLoop:
            updatePageIndex(to: currentPageIndex + 1)
        case .setup:
            saveSetup()
        }
    }

    private func saveSetup() {
        guard !primaryButtonDisabled else { return }

        let enteredHousehold = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredPlayer = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let starterTasks = selectedRecommendedTasks
        let avatarID = selectedAvatarID
        isSavingSetup = true

        Task { @MainActor in
            // Equip first: renameActiveProfile's save snapshots the profile into
            // the household member list, which the leaderboards render.
            await dataStore.selectStarterAvatar(id: avatarID)
            await dataStore.renameActiveProfile(to: enteredPlayer)
            await dataStore.renameHousehold(dataStore.activeHouseholdId, to: enteredHousehold)
            await dataStore.seedOnboardingTasks(recommendedTasks: starterTasks)
            isSavingSetup = false
            onComplete()
        }
    }

    private func goBack() {
        guard currentPageIndex > 0 else { return }
        updatePageIndex(to: currentPageIndex - 1)
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
}
