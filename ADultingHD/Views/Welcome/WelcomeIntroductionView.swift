import SwiftUI

struct WelcomeOnboardingFlow {
    enum Route: Equatable {
        case creating
        case pendingInvite(id: String, householdName: String, inviterName: String?)
        case joined(householdID: UUID, householdName: String, inviterName: String?)

        var isJoining: Bool {
            if case .creating = self { return false }
            return true
        }

        var householdName: String? {
            switch self {
            case .creating: nil
            case .pendingInvite(_, let householdName, _), .joined(_, let householdName, _): householdName
            }
        }

        var inviterName: String? {
            switch self {
            case .creating: nil
            case .pendingInvite(_, _, let inviterName), .joined(_, _, let inviterName): inviterName
            }
        }

        var pendingInviteID: String? {
            guard case .pendingInvite(let id, _, _) = self else { return nil }
            return id
        }
    }

    enum Step: Equatable {
        case joinHousehold
        case homeSpaces
        case inviteChoice
        case playerName
        case invite
        case suggestions
        case rewards

        var accessibilityID: String {
            switch self {
            case .joinHousehold: "join-household"
            case .homeSpaces: "home-spaces"
            case .inviteChoice: "invite-choice"
            case .playerName: "player-name"
            case .invite: "invite"
            case .suggestions: "suggestions"
            case .rewards: "rewards"
            }
        }
    }

    private(set) var route: Route = .creating
    private(set) var current: Step = .playerName
    private(set) var history: [Step] = []
    private(set) var wantsToInvite: Bool?

    var canGoBack: Bool { !history.isEmpty }

    var progressSteps: [Step] {
        if route.isJoining {
            return [.joinHousehold, .suggestions, .rewards]
        }
        var result: [Step] = [.playerName, .homeSpaces, .suggestions, .inviteChoice]
        if wantsToInvite == true {
            result.append(.invite)
        }
        result.append(.rewards)
        return result
    }

    var progressPosition: Int {
        (progressSteps.firstIndex(of: current) ?? 0) + 1
    }

    mutating func start(_ route: Route) {
        self.route = route
        current = route.isJoining ? .joinHousehold : .playerName
        history = []
        wantsToInvite = nil
    }

    mutating func answerInvitation(_ shouldInvite: Bool) {
        guard current == .inviteChoice else { return }
        wantsToInvite = shouldInvite
        move(to: shouldInvite ? .invite : .rewards)
    }

    mutating func markInviteSent() {
        guard current == .invite else { return }
        advance()
    }

    mutating func markInviteAccepted(_ household: Household) {
        route = .joined(
            householdID: household.id,
            householdName: household.name,
            inviterName: household.inviterName
        )
    }

    /// Walks the same list the progress bar shows, so a reordered route cannot
    /// leave navigation and progress disagreeing. `inviteChoice` is the only
    /// branch point and moves on through `answerInvitation` instead.
    mutating func advance() {
        guard current != .inviteChoice else { return }
        let steps = progressSteps
        guard let index = steps.firstIndex(of: current), index + 1 < steps.count else { return }
        move(to: steps[index + 1])
    }

    mutating func back() {
        guard let previous = history.popLast() else { return }
        current = previous
    }

    private mutating func move(to step: Step) {
        history.append(current)
        current = step
    }
}

private struct OnboardingPagePresentation {
    let title: String
    let subtitle: String
    let imageName: String?
    let imageLabel: String?
}

/// The short, action-first portion of onboarding. Navigation lives in the
/// explicit flow value above, so invite/create routes and back history are not
/// inferred from an index into a changing page array.
struct WelcomeIntroductionView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var flow = WelcomeOnboardingFlow()
    @State private var didConfigureFlow = false
    @State private var isSaving = false
    @State private var joinError: String?
    @State private var hasSentInvite = false
    @State private var sharePresentation = HouseholdSharePresentation()
    @State private var selectedStarterTaskNames: Set<String> = []
    @State private var visibleStarterTaskCount = 5
    @State private var starterLocationSnapshot: Set<HomeLocation> = []
    @AppStorage(PrefKey.onboardingPlayerName) private var playerName = ""

    let width: CGFloat
    let height: CGFloat
    let isActive: Bool
    @Binding var selectedLocations: Set<HomeLocation>
    let onRequestSetup: () -> Void
    let onComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if flow.current == .homeSpaces {
                    heading
                    artwork
                        .id(flow.current)
                        .transition(.opacity)
                } else {
                    artwork
                        .id(flow.current)
                        .transition(.opacity)
                    heading
                }
                pageContent
            }
            .frame(width: contentWidth)
            .padding(.horizontal, compactLayout ? 16 : 28)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(minHeight: max(0, height - 168), alignment: .center)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("onboarding-page-\(flow.current.accessibilityID)")
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
                .allowsHitTesting(isActive)
                .accessibilityHidden(!isActive)
        }
        .onAppear(perform: prepareDefaults)
        .onChange(of: dataStore.pendingOnboardingShare?.id) { _, shareID in
            if shareID != nil {
                updateFlow { $0.start(routeFromStore) }
            }
        }
        .onChange(of: flow.current) { _, step in
            if step == .suggestions && !flow.route.isJoining {
                prepareStarterChores()
            }
        }
        .sheet(item: sharePresentation.payloadBinding, onDismiss: handleSharePresentationDismissed) { payload in
            CloudShareSheet(
                share: payload.share,
                container: payload.container,
                householdName: payload.householdName,
                onShareSaved: { hasSentInvite = true },
                onShareInvalidated: { hasSentInvite = false },
                onDismiss: sharePresentation.dismiss
            )
        }
        .onDisappear(perform: sharePresentation.dismiss)
    }

    private var compactLayout: Bool { width < 600 }

    private var contentWidth: CGFloat {
        let sidePadding: CGFloat = compactLayout ? 32 : 56
        return min(max(width - sidePadding, 0), Theme.onboardingContentMaxWidth)
    }

    private var routeFromStore: WelcomeOnboardingFlow.Route {
        if let pending = dataStore.pendingOnboardingShare {
            return .pendingInvite(
                id: pending.id,
                householdName: pending.householdName,
                inviterName: pending.inviterName
            )
        }
        let household = dataStore.activeHousehold
        if !household.ownerIsCurrentUser {
            return .joined(
                householdID: household.id,
                householdName: household.name,
                inviterName: household.inviterName
            )
        }
        return .creating
    }

    private var joiningHouseholdName: String {
        flow.route.householdName ?? "Shared Home"
    }

    private var homeDisplayName: String {
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Your home" : "\(name)'s home"
    }

    private var inviterDisplayName: String {
        guard let inviterName = flow.route.inviterName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !inviterName.isEmpty else {
            return "the home owner"
        }
        return inviterName
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if flow.canGoBack {
                    Button {
                        updateFlow { $0.back() }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(isBusy)
                    .accessibilityIdentifier("onboarding-back-action")
                } else {
                    Label("ADultingHD", systemImage: "house.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                Text("\(flow.progressPosition) of \(flow.progressSteps.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Onboarding progress")
            }

            ProgressView(
                value: Double(flow.progressPosition),
                total: Double(flow.progressSteps.count)
            )
            .tint(Theme.adventureBlue)
            .accessibilityLabel("Onboarding progress")
            .accessibilityValue("\(flow.progressPosition) of \(flow.progressSteps.count)")
        }
    }

    private var presentation: OnboardingPagePresentation {
        switch flow.current {
        case .joinHousehold:
            OnboardingPagePresentation(
                title: "You are joining \(joiningHouseholdName), with \(inviterDisplayName).",
                subtitle: "What's your name? Add the name you want everyone in this household to see.",
                imageName: "Onboarding/SharedHouseholdV1",
                imageLabel: "Household members sharing dishes, laundry, and recycling from one cozy home."
            )
        case .homeSpaces:
            OnboardingPagePresentation(
                title: "Make \(homeDisplayName) work for you.",
                subtitle: "Choose the spaces that matter to you. We’ll suggest helpful tasks for each one.",
                imageName: nil,
                imageLabel: nil
            )
        case .inviteChoice:
            OnboardingPagePresentation(
                title: "Do you want to invite other people?",
                subtitle: "You can share tasks and progress with the people you live with, or start on your own.",
                imageName: "Onboarding/SharedHouseholdV1",
                imageLabel: "Household members sharing dishes, laundry, and recycling from one cozy home."
            )
        case .playerName:
            OnboardingPagePresentation(
                title: "Welcome! What is your name?",
                subtitle: "This name shows up on your progress, and on assignments and the leaderboard if you share a household.",
                imageName: "Onboarding/WelcomeHeroV1",
                imageLabel: "A warmly lit cutaway home with a glowing path running through every room."
            )
        case .invite:
            OnboardingPagePresentation(
                title: "Invite your household",
                subtitle: "Send a private iCloud invite now, or skip and invite people later from Household settings.",
                imageName: "Onboarding/SharedHouseholdV1",
                imageLabel: "Household members sharing dishes, laundry, and recycling from one cozy home."
            )
        case .suggestions:
            OnboardingPagePresentation(
                title: flow.route.isJoining ? "You’re ready to join in." : "Start with a few easy wins.",
                subtitle: flow.route.isJoining
                    ? "Your shared household’s tasks will be waiting for you."
                    : "Based on the spaces you chose, here are a few helpful chores to get you started. Pick any you want—you can always add more tasks later.",
                imageName: flow.route.isJoining ? "Onboarding/ManageableSuggestionsV1" : nil,
                imageLabel: flow.route.isJoining ? "A cozy kitchen with a few doable household suggestions." : nil
            )
        case .rewards:
            OnboardingPagePresentation(
                title: "Turn chores into XP.",
                subtitle: "Finish tasks, build streaks, level up, and make keeping up with home feel a little more like a game.",
                imageName: "Onboarding/XPStreaksV1",
                imageLabel: "A completed chore creates a reward, fills progress, and keeps a streak going."
            )
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if flow.current == .homeSpaces {
            HomeFloorPlanView(selectedLocations: $selectedLocations)
        } else if let imageName = presentation.imageName {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: compactLayout ? 220 : 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius)
                        .strokeBorder(Theme.adventureBlue.opacity(0.12))
                }
                .shadow(color: Theme.adventureBlue.opacity(0.12), radius: 16, y: 8)
                .accessibilityLabel(presentation.imageLabel ?? "Onboarding illustration")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(presentation.subtitle)
                .font(.title3)
                .foregroundStyle(colorSchemeContrast == .increased ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch flow.current {
        case .homeSpaces:
            Label(
                selectedLocations.isEmpty
                    ? "Select at least one space to continue"
                    : "\(selectedLocations.count) \(selectedLocations.count == 1 ? "space" : "spaces") selected",
                systemImage: selectedLocations.isEmpty ? "hand.tap.fill" : "checkmark.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selectedLocations.isEmpty ? .secondary : Theme.successGreen)
        case .joinHousehold, .playerName:
            VStack(alignment: .leading, spacing: 8) {
                inputField(
                    "What's your name?",
                    icon: "person.fill",
                    text: $playerName,
                    accessibilityID: "onboarding-player-name-field"
                )
                .onSubmit {
                    guard !primaryButtonDisabled else { return }
                    handlePrimaryAction()
                }
                if flow.current == .joinHousehold && isPlayerNameTaken {
                    Label("Someone in this household already uses that name.", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if flow.current == .joinHousehold, let joinError {
                    Label(joinError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .inviteChoice:
            Label("You can change this later in Household settings.", systemImage: "gearshape.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .invite:
            inviteStatus
        case .suggestions:
            if flow.route.isJoining {
                EmptyView()
            } else {
                StarterChorePickerView(
                    tasks: starterSuggestions,
                    selectedTaskNames: $selectedStarterTaskNames,
                    visibleTaskCount: $visibleStarterTaskCount
                )
            }
        case .rewards:
            rewardPreview
        }
    }

    private func inputField(
        _ label: String,
        icon: String,
        text: Binding<String>,
        accessibilityID: String
    ) -> some View {
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
                .accessibilityIdentifier(accessibilityID)
                #if os(iOS)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
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

    @ViewBuilder
    private var inviteStatus: some View {
        if let errorMessage = sharePresentation.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
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

    private var rewardPreview: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            rewardBadge("+25 XP", icon: "sparkles", color: Theme.hearthGold)
            rewardBadge("Level 6", icon: "chart.bar.fill", color: Theme.adventureBlue)
            rewardBadge("7 day streak", icon: "flame.fill", color: Theme.coral)
        }
        .accessibilityElement(children: .contain)
    }

    private func rewardBadge(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.horizontal, 10)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                    .strokeBorder(color.opacity(0.20))
            }
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private var actions: some View {
        switch flow.current {
        case .inviteChoice:
            WelcomeActionBar(
                title: "Yes, invite people",
                action: { answerInvitation(true) },
                isDisabled: isBusy,
                showsProgress: false,
                secondaryTitle: "No, I'll start on my own",
                secondaryAction: { answerInvitation(false) },
                isAccessibilityHidden: !isActive
            )
        case .joinHousehold:
            WelcomeActionBar(
                title: "Join \(joiningHouseholdName)",
                action: handlePrimaryAction,
                isDisabled: primaryButtonDisabled,
                showsProgress: isSaving,
                secondaryTitle: "Create my own household instead",
                secondaryAction: leaveInvitedHousehold,
                secondaryIsDisabled: isBusy,
                isAccessibilityHidden: !isActive
            )
        case .invite:
            WelcomeActionBar(
                title: inviteButtonTitle,
                action: handlePrimaryAction,
                isDisabled: primaryButtonDisabled,
                showsProgress: sharePresentation.isPreparing,
                secondaryTitle: hasSentInvite ? "Done" : "Skip for now",
                secondaryAction: advance,
                secondaryIsDisabled: isBusy,
                isAccessibilityHidden: !isActive
            )
        case .suggestions where !flow.route.isJoining:
            WelcomeActionBar(
                title: starterChoreActionTitle,
                action: saveStarterChoresAndAdvance,
                isDisabled: selectedStarterTaskNames.isEmpty || isBusy,
                showsProgress: isSaving,
                secondaryTitle: "Skip for now",
                secondaryAction: skipStarterChores,
                secondaryIsDisabled: isBusy,
                isAccessibilityHidden: !isActive
            )
        default:
            WelcomeActionBar(
                title: primaryButtonTitle,
                action: handlePrimaryAction,
                isDisabled: primaryButtonDisabled,
                showsProgress: isSaving,
                isAccessibilityHidden: !isActive
            )
        }
    }

    private var isBusy: Bool { isSaving || sharePresentation.isPreparing }

    private var isPlayerNameTaken: Bool {
        dataStore.isProfileNameTakenInActiveHousehold(playerName)
    }

    private var primaryButtonTitle: String {
        switch flow.current {
        case .homeSpaces: "Continue to task suggestions"
        case .playerName: "Continue"
        case .suggestions: flow.route.isJoining ? "Next" : starterChoreActionTitle
        case .rewards: flow.route.isJoining ? "Enter \(joiningHouseholdName)" : "Choose my first chores"
        case .joinHousehold: "Join \(joiningHouseholdName)"
        case .invite: inviteButtonTitle
        case .inviteChoice: "Continue"
        }
    }

    private var inviteButtonTitle: String {
        if sharePresentation.isPreparing { return "Preparing..." }
        if hasSentInvite { return "Invite someone else" }
        return "Pick someone to invite"
    }

    private var primaryButtonDisabled: Bool {
        if isBusy { return true }
        return switch flow.current {
        case .homeSpaces:
            selectedLocations.isEmpty
        case .joinHousehold:
            playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPlayerNameTaken
        case .playerName:
            playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            false
        }
    }

    private func prepareDefaults() {
        if playerName.isEmpty {
            let suggested = UserProfile.defaultPlayerName()
            let current = dataStore.profile.name
            playerName = !current.isEmpty && current != "Player 1" ? current : suggested
        }
        guard !didConfigureFlow else { return }
        didConfigureFlow = true
        flow.start(routeFromStore)
    }

    private var starterSuggestions: [CatalogTask] {
        onboardingRecommendedCatalogTasks(for: selectedLocations)
    }

    private var selectedStarterTasks: [CatalogTask] {
        starterSuggestions.filter { selectedStarterTaskNames.contains($0.name) }
    }

    private var starterChoreActionTitle: String {
        "Add \(selectedStarterTaskNames.count) \(selectedStarterTaskNames.count == 1 ? "chore" : "chores")"
    }

    private func prepareStarterChores() {
        guard starterLocationSnapshot != selectedLocations else { return }
        starterLocationSnapshot = selectedLocations
        visibleStarterTaskCount = 5
        selectedStarterTaskNames = Set(
            starterSuggestions.prefix(5).enumerated().compactMap { index, task in
                index.isMultiple(of: 2) ? task.name : nil
            }
        )
    }

    private func saveStarterChoresAndAdvance() {
        guard !selectedStarterTaskNames.isEmpty, !isSaving else { return }
        let tasks = selectedStarterTasks
        isSaving = true
        Task { @MainActor in
            await dataStore.seedOnboardingTasks(recommendedTasks: tasks)
            isSaving = false
            advance()
        }
    }

    private func skipStarterChores() {
        guard !isBusy else { return }
        selectedStarterTaskNames.removeAll()
        advance()
    }

    private func answerInvitation(_ shouldInvite: Bool) {
        updateFlow { $0.answerInvitation(shouldInvite) }
    }

    private func handleSharePresentationDismissed() {
        let shouldAdvance = hasSentInvite && flow.current == .invite
        hasSentInvite = false
        sharePresentation.dismiss()
        if shouldAdvance {
            updateFlow { $0.markInviteSent() }
        }
    }

    private func handlePrimaryAction() {
        switch flow.current {
        case .homeSpaces:
            advance()
        case .joinHousehold, .playerName:
            persistPlayerNameAndAdvance()
        case .invite:
            Task { await sharePresentation.prepare(using: dataStore) }
        case .suggestions:
            advance()
        case .rewards:
            if flow.route.isJoining {
                onComplete()
            } else {
                onRequestSetup()
            }
        case .inviteChoice:
            break
        }
    }

    private func persistPlayerNameAndAdvance() {
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isPlayerNameTaken, !isSaving else { return }
        let pendingInviteID = flow.route.pendingInviteID
        let activeHouseholdID = dataStore.activeHouseholdId
        isSaving = true
        joinError = nil
        Task { @MainActor in
            do {
                if let pendingInviteID {
                    try await dataStore.acceptPendingOnboardingShare(
                        id: pendingInviteID,
                        displayName: name
                    )
                    guard flow.route.pendingInviteID == pendingInviteID else {
                        isSaving = false
                        return
                    }
                    flow.markInviteAccepted(dataStore.activeHousehold)
                } else {
                    await dataStore.renameActiveProfile(to: name)
                    // The owner's display name is also the home name used in
                    // later invites. The selected spaces remain temporary
                    // filters; they never become a task hierarchy.
                    await dataStore.renameHousehold(activeHouseholdID, to: name)
                }
                isSaving = false
                if !isPlayerNameTaken {
                    advance()
                }
            } catch {
                isSaving = false
                if pendingInviteID == nil || flow.route.pendingInviteID == pendingInviteID {
                    joinError = error.localizedDescription
                }
            }
        }
    }

    private func leaveInvitedHousehold() {
        guard !isSaving else { return }
        joinError = nil
        switch flow.route {
        case .pendingInvite:
            dataStore.declinePendingOnboardingShare()
            resetToCreatingFlow()
        case .joined:
            isSaving = true
            Task { @MainActor in
                await dataStore.leaveJoinedHouseholdForOnboarding()
                isSaving = false
                resetToCreatingFlow()
            }
        case .creating:
            break
        }
    }

    private func resetToCreatingFlow() {
        selectedLocations.removeAll()
        updateFlow { $0.start(.creating) }
    }

    private func advance() {
        updateFlow { $0.advance() }
    }

    private func updateFlow(_ update: (inout WelcomeOnboardingFlow) -> Void) {
        let wasOnInviteStep = flow.current == .invite
        if reduceMotion {
            update(&flow)
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                update(&flow)
            }
        }
        if wasOnInviteStep && flow.current != .invite {
            sharePresentation.dismiss()
        }
    }
}
