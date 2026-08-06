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
                        UserDefaults.standard.set(false, forKey: PrefKey.hasCompletedOnboarding)
                    }
                    #endif
                    dataStore.configure(notificationManager: notificationManager)
                    await dataStore.load()
                    ICloudMonitor.shared.start()
                    dataStore.startSyncObserver()
                    dataStore.startDayRolloverObserver()
                    await dataStore.drainAcceptedShareInbox()
                    await notificationManager.checkAuthorizationStatus()
                    await storeManager.loadProducts()
                }
                .onContinueUserActivity(ShareAcceptance.activityType) { activity in
                    guard let metadata = ShareAcceptance.metadata(from: activity) else { return }
                    Task { @MainActor in
                        await dataStore.registerJoinedHousehold(from: metadata)
                    }
                }
                // Catches a calendar-day rollover that happened while the
                // app was backgrounded/suspended — the NSCalendarDayChanged
                // observer only fires while running, so resume needs its
                // own check.
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        dataStore.refreshForCurrentDay()
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
