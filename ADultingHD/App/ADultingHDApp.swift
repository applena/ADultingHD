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
                    for metadata in IncomingShareInbox.shared.drain() {
                        await handleIncomingHouseholdShare(metadata)
                    }
                    await notificationManager.checkAuthorizationStatus()
                    await storeManager.loadProducts()
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
    private func handleIncomingHouseholdShare(_ metadata: CKShare.Metadata) async {
        if UserDefaults.standard.bool(forKey: PrefKey.hasCompletedOnboarding) {
            try? await dataStore.registerJoinedHousehold(from: metadata)
        } else {
            dataStore.stagePendingOnboardingShare(metadata)
        }
    }
}
