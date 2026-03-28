import SwiftUI

@main
struct ADultingHDApp: App {
    @State private var dataStore = DataStore()
    @State private var notificationManager = NotificationManager()
    @State private var storeManager = StoreManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dataStore)
                .environment(notificationManager)
                .environment(storeManager)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-demo") {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        storeManager.enableDemoMode()
                    }
                    #endif
                    await dataStore.load()
                    await notificationManager.checkAuthorizationStatus()
                    await storeManager.loadProducts()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
