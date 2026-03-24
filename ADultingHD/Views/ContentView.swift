import SwiftUI

struct ContentView: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        Group {
            if !dataStore.isLoaded {
                ProgressView("Loading...")
            } else {
                #if os(macOS)
                MacContentView()
                #else
                IOSContentView()
                #endif
            }
        }
    }
}

// MARK: - macOS Layout

#if os(macOS)
struct MacContentView: View {
    @State private var selectedTab: SidebarTab = .dashboard

    enum SidebarTab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case tasks = "Tasks"
        case schedule = "Schedule"
        case supplies = "Supplies"
        case profile = "Profile"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: "gauge.with.dots.needle.33percent"
            case .tasks: "checklist"
            case .schedule: "calendar"
            case .supplies: "cart"
            case .profile: "person.crop.circle"
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
            case .dashboard: DashboardView()
            case .tasks: TaskListView()
            case .schedule: ScheduleView()
            case .supplies: SuppliesView()
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
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }

            NavigationStack { TaskListView() }
                .tabItem { Label("Tasks", systemImage: "checklist") }

            NavigationStack { ScheduleView() }
                .tabItem { Label("Schedule", systemImage: "calendar") }

            NavigationStack { SuppliesView() }
                .tabItem { Label("Supplies", systemImage: "cart") }

            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
#endif
