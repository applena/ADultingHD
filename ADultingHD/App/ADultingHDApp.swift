import SwiftUI

@main
struct ADultingHDApp: App {
    @State private var dataStore = DataStore()
    @State private var notificationManager = NotificationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dataStore)
                .environment(notificationManager)
                .task {
                    await dataStore.load()
                    await notificationManager.checkAuthorizationStatus()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
