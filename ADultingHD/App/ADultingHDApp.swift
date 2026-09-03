import SwiftUI
import CloudKit

@main
struct ADultingHDApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    @State private var dataStore = DataStore()
    @State private var notificationManager = NotificationManager()
    @State private var storeManager = StoreManager()
    @StateObject private var incomingShareInbox = IncomingShareInbox.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
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
                    ICloudMonitor.shared.start()
                    dataStore.startSyncObserver()
                    dataStore.startDayRolloverObserver()
                    await processIncomingHouseholdShares()
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
                    guard let metadata = ShareAcceptance.metadata(from: activity) else { return }
                    Task { @MainActor in
                        await handleIncomingHouseholdShare(metadata)
                    }
                }
                // Catches a calendar-day rollover that happened while the
                // app was backgrounded/suspended — the NSCalendarDayChanged
                // observer only fires while running, so resume needs its
                // own check.
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await dataStore.refreshForCurrentDay() }
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
        guard dataStore.isLoaded else { return }
        for metadata in incomingShareInbox.drain() {
            await handleIncomingHouseholdShare(metadata)
        }
    }

    @MainActor
    private func handleIncomingHouseholdShare(_ metadata: CKShare.Metadata) async {
        if UserDefaults.standard.bool(forKey: PrefKey.hasCompletedOnboarding) {
            try? await dataStore.registerJoinedHousehold(from: metadata)
        } else {
            dataStore.stagePendingOnboardingShare(metadata)
        }
    }
}
