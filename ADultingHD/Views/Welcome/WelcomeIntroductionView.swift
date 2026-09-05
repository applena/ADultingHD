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
        case playerName
        case invite
        case suggestions
        case homeTour

        var accessibilityID: String {
            switch self {
            case .joinHousehold: "join-household"
            case .homeSpaces: "home-spaces"
            case .playerName: "player-name"
            case .invite: "invite"
            case .suggestions: "suggestions"
            case .homeTour: "home-tour"
            }
        }
    }

    private(set) var route: Route = .creating
    private(set) var current: Step = .playerName
    private(set) var history: [Step] = []
    var canGoBack: Bool { !history.isEmpty }

    var progressSteps: [Step] {
        if route.isJoining {
            return [.playerName, .joinHousehold, .homeTour]
        }
        return [.playerName, .homeSpaces, .suggestions, .invite, .homeTour]
    }

    var progressPosition: Int {
        (progressSteps.firstIndex(of: current) ?? 0) + 1
    }

    mutating func start(_ route: Route) {
        self.route = route
        current = .playerName
        history = []
    }

    mutating func markInviteSent() {
        guard current == .invite else { return }
        advance()
    }

    mutating func finishInvitePresentation(wasInvalidated: Bool) {
        guard !wasInvalidated else { return }
        markInviteSent()
    }

    mutating func markInviteAccepted(_ household: Household) {
        route = .joined(
            householdID: household.id,
            householdName: household.name,
            inviterName: household.inviterName
        )
    }

    /// Walks the same list the progress bar shows, so a reordered route cannot
    /// leave navigation and progress disagreeing.
    mutating func advance() {
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
    @State private var mergeSourceID: UUID?
    @State private var hasSentInvite = false
    @State private var invitePresentationWasInvalidated = false
    @State private var sharePresentation = HouseholdSharePresentation()
    @State private var selectedStarterTaskNames: Set<String> = []
    @State private var visibleStarterTaskCount = 5
    @State private var starterLocationSnapshot: Set<HomeLocation> = []
    @AppStorage(PrefKey.onboardingPlayerName) private var playerName = ""

    let width: CGFloat
    let height: CGFloat
    let isActive: Bool
    @Binding var selectedLocations: Set<HomeLocation>
    let onComplete: () -> Void

    var body: some View {
        Group {
            if flow.current == .homeTour {
                HomeOnboardingTourView(
                    playerName: playerName,
                    tasks: dataStore.activeTasks,
                    onboardingPosition: flow.progressPosition,
                    onboardingTotal: flow.progressSteps.count,
                    onComplete: onComplete
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if flow.current == .homeSpaces || flow.current == .invite {
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
            }
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
            mergeSourceID = nil
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
                onShareSaved: handleInviteSent,
                onShareInvalidated: handleInviteInvalidated,
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
                title: "Join \(joiningHouseholdName).",
                subtitle: "\(inviterDisplayName) invited you to share chores, assignments, and progress in one household.",
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
        case .playerName:
            OnboardingPagePresentation(
                title: "Welcome! What is your name?",
                subtitle: "This name shows up on your progress, and on assignments and the leaderboard if you share a household.",
                imageName: "Onboarding/WelcomeHeroV1",
                imageLabel: "A warmly lit cutaway home with a glowing path running through every room."
            )
        case .invite:
            OnboardingPagePresentation(
                title: "Share the load.",
                subtitle: "Invite someone you live with to share chores, assignments, and progress. You can always invite more people later.",
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
        case .homeTour:
            OnboardingPagePresentation(
                title: "Meet your home screen.",
                subtitle: "A quick tour will show you the controls you’ll use most.",
                imageName: nil,
                imageLabel: nil
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
        case .playerName:
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
            }
        case .joinHousehold:
            if flow.route.pendingInviteID != nil {
                HouseholdChoreSourcePicker(
                    sources: dataStore.onboardingMergeSources, selection: $mergeSourceID
                )
                .disabled(isBusy)
            }
            if let joinError {
                Label(joinError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(
                    "Your name will appear as \(playerName.trimmingCharacters(in: .whitespacesAndNewlines)).",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
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
        case .homeTour:
            EmptyView()
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
            VStack(alignment: .leading, spacing: 8) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorCode = sharePresentation.errorCode {
                    Text("Error code: \(errorCode)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button {
                        sharePresentation.copyErrorDetails()
                    } label: {
                        Label("Copy error details", systemImage: "doc.on.doc")
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("onboarding-copy-invite-error")
                }
            }
        } else if hasSentInvite {
            Label("Invite sent", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.successGreen)
        } else {
            Label("Invites use Apple’s private iCloud sharing.", systemImage: "lock.shield.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch flow.current {
        case .joinHousehold:
            WelcomeActionBar(
                title: mergeSourceID == nil ? "Join \(joiningHouseholdName)" : "Join and merge chores",
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
                secondaryTitle: "Skip for now",
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
        case .homeTour:
            EmptyView()
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
        case .homeTour: "Start using ADultingHD"
        case .joinHousehold: "Join \(joiningHouseholdName)"
        case .invite: inviteButtonTitle
        }
    }

    private var inviteButtonTitle: String {
        if sharePresentation.isPreparing { return "Preparing..." }
        if hasSentInvite { return "Invite someone else" }
        return "Invite someone"
    }

    private var primaryButtonDisabled: Bool {
        if isBusy { return true }
        return switch flow.current {
        case .homeSpaces:
            selectedLocations.isEmpty
        case .joinHousehold:
            false
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

    private func handleSharePresentationDismissed() {
        let wasInvalidated = invitePresentationWasInvalidated
        hasSentInvite = false
        invitePresentationWasInvalidated = false
        sharePresentation.dismiss()
        updateFlow { $0.finishInvitePresentation(wasInvalidated: wasInvalidated) }
    }

    private func handleInviteSent() {
        guard flow.current == .invite else { return }
        hasSentInvite = true
        updateFlow { $0.markInviteSent() }
    }

    private func handleInviteInvalidated() {
        invitePresentationWasInvalidated = true
        hasSentInvite = false
    }

    private func handlePrimaryAction() {
        switch flow.current {
        case .homeSpaces:
            advance()
        case .playerName:
            persistPlayerNameAndAdvance()
        case .joinHousehold:
            acceptInvitedHousehold()
        case .invite:
            invitePresentationWasInvalidated = false
            Task { await sharePresentation.prepare(using: dataStore) }
        case .suggestions:
            advance()
        case .homeTour:
            onComplete()
        }
    }

    private func persistPlayerNameAndAdvance() {
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isSaving else { return }
        if flow.route.isJoining {
            advance()
            return
        }
        let activeHouseholdID = dataStore.activeHouseholdId
        isSaving = true
        joinError = nil
        Task { @MainActor in
            await dataStore.renameActiveProfile(to: name)
            // The owner's display name is also the home name used in later
            // invites. The selected spaces remain temporary task filters.
            await dataStore.renameHousehold(activeHouseholdID, to: name)
            isSaving = false
            advance()
        }
    }

    private func acceptInvitedHousehold() {
        guard flow.route.isJoining, !isSaving else { return }
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingInviteID = flow.route.pendingInviteID
        let sourceID = mergeSourceID
        isSaving = true
        joinError = nil
        Task { @MainActor in
            do {
                if let pendingInviteID {
                    try await dataStore.acceptPendingOnboardingShare(
                        id: pendingInviteID, displayName: name, mergeFrom: sourceID
                    )
                    guard flow.route.pendingInviteID == pendingInviteID else {
                        isSaving = false
                        return
                    }
                    flow.markInviteAccepted(dataStore.activeHousehold)
                } else {
                    await dataStore.renameActiveProfile(to: name)
                }
                isSaving = false
                advance()
            } catch {
                isSaving = false
                if flow.route.pendingInviteID == pendingInviteID {
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
