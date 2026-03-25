import SwiftUI

struct ContentView: View {
    @Environment(DataStore.self) private var dataStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if !dataStore.isLoaded {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading your adventure...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !hasCompletedOnboarding {
                WelcomeView {
                    withAnimation(.spring(response: 0.5)) {
                        hasCompletedOnboarding = true
                    }
                }
            } else {
                #if os(macOS)
                MacContentView()
                    .celebrationOverlay(type: dataStore.celebrationType, isShowing: Binding(
                        get: { dataStore.showCelebration },
                        set: { dataStore.showCelebration = $0 }
                    ))
                #else
                IOSContentView()
                    .celebrationOverlay(type: dataStore.celebrationType, isShowing: Binding(
                        get: { dataStore.showCelebration },
                        set: { dataStore.showCelebration = $0 }
                    ))
                #endif
            }
        }
    }
}

// MARK: - macOS Layout

#if os(macOS)
struct MacContentView: View {
    @State private var selectedTab: SidebarTab = .home

    enum SidebarTab: String, CaseIterable, Identifiable {
        case home = "Home"
        case tasks = "Tasks"
        case schedule = "Schedule"
        case supplies = "Supplies"
        case stats = "Stats"
        case profile = "Profile"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home: "house.fill"
            case .tasks: "checklist"
            case .schedule: "calendar"
            case .supplies: "bag.fill"
            case .stats: "chart.bar.fill"
            case .profile: "person.crop.circle.fill"
            case .settings: "gear"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("ADultingHD")
        } detail: {
            switch selectedTab {
            case .home: DashboardView()
            case .tasks: TaskListView()
            case .schedule: ScheduleView()
            case .supplies: SuppliesView()
            case .stats: StatsView()
            case .profile: ProfileView()
            case .settings: SettingsView()
            }
        }
    }
}
#endif

// MARK: - iOS Layout

#if os(iOS)
struct IOSContentView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { TaskListView() }
                .tabItem { Label("Tasks", systemImage: "checklist") }

            NavigationStack { ScheduleView() }
                .tabItem { Label("Schedule", systemImage: "calendar") }

            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }

            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
    }
}
#endif
