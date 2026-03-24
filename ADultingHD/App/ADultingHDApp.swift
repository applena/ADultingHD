import SwiftUI

@main
struct ADultingHDApp: App {
    @State private var dataStore = DataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dataStore)
                .task {
                    await dataStore.load()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
