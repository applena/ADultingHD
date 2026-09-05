import SwiftUI
import CloudKit

@main
struct ADultingHDApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    #if DEBUG
    @State private var dataStore = HouseholdInvitationPreview.makeDataStore()
    #else
    @State private var dataStore = DataStore()
    #endif
    @State private var notificationManager = NotificationManager()
    @State private var storeManager = StoreManager()
    @StateObject private var incomingShareInbox = IncomingShareInbox.shared
    @Environment(\.scenePhase) private var scenePhase

    private var runsInvitationPreview: Bool {
        #if DEBUG
        HouseholdInvitationPreview.isEnabled
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG
                .modifier(HouseholdInvitationPreviewAppearance())
                #endif
                .environment(dataStore)
                .environment(notificationManager)
                .environment(storeManager)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-demo") {
                        UserDefaults.standard.set(true, forKey: PrefKey.hasCompletedOnboarding)
                        storeManager.enableDemoMode()
                    }
                    if ProcessInfo.processInfo.arguments.contains("-onboarding") {
                        let defaults = UserDefaults.standard
                        defaults.set(false, forKey: PrefKey.hasCompletedOnboarding)
                        defaults.removeObject(forKey: PrefKey.onboardingHouseholdName)
                        defaults.removeObject(forKey: PrefKey.onboardingPlayerName)
                    }
                    #endif
                    dataStore.configure(notificationManager: notificationManager)
                    await dataStore.load()
                    #if DEBUG
                    HouseholdInvitationPreview.stageIfRequested(in: dataStore)
                    #endif
                    if !runsInvitationPreview {
                        ICloudMonitor.shared.start()
                        dataStore.startSyncObserver()
                        await processIncomingHouseholdShares()
                        await dataStore.resumeHouseholdSharing()
                    }
                    dataStore.startDayRolloverObserver()
                    await notificationManager.checkAuthorizationStatus()
                    await storeManager.loadProducts()
                }
                // CloudKit can call the AppDelegate after the startup task has
                // already drained the inbox. Observe later deliveries as well
                // so a cold-launch invite cannot fall through to the normal
                // create-a-household onboarding route.
                .onChange(of: incomingShareInbox.pending.count) { _, _ in
                    Task { @MainActor in
                        await processIncomingHouseholdShares()
                    }
                }
                .onContinueUserActivity(ShareAcceptance.activityType) { activity in
                    incomingShareInbox.enqueue(activity)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    incomingShareInbox.enqueue(activity)
                }
                .onOpenURL { url in
                    incomingShareInbox.enqueue(url)
                }
                // Catches a calendar-day rollover that happened while the
                // app was backgrounded/suspended — the NSCalendarDayChanged
                // observer only fires while running, so resume needs its
                // own check.
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await dataStore.refreshForCurrentDay() }
                        Task {
                            guard dataStore.isLoaded, !runsInvitationPreview else { return }
                            await dataStore.resumeHouseholdSharing()
                        }
                        // Notification permission may have been granted or
                        // revoked in system Settings while backgrounded;
                        // an actual flip re-plans reminders via the
                        // isAuthorized didSet.
                        Task { await notificationManager.checkAuthorizationStatus() }
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }

    @MainActor
    private func processIncomingHouseholdShares() async {
        // A delivery that arrives while DataStore.load() is running stays in
        // the inbox. The startup task drains it once loading completes.
        guard !runsInvitationPreview, dataStore.isLoaded, incomingShareInbox.beginProcessing() else { return }
        defer { incomingShareInbox.endProcessing() }
        while let invitation = incomingShareInbox.next() {
            switch invitation {
            case .metadata(let metadata):
                dataStore.stageIncomingHouseholdShare(metadata)
            case .url(let url):
                await dataStore.stageIncomingHouseholdShare(url: url)
            }
        }
    }
}
