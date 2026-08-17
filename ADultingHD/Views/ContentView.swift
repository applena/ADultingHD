import SwiftUI

struct ContentView: View {
    @Environment(DataStore.self) private var dataStore
    @AppStorage(PrefKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        @Bindable var bindable = dataStore
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
                Group {
                    #if os(macOS)
                    MacContentView()
                    #else
                    IOSContentView()
                    #endif
                }
                .celebrationOverlay(type: dataStore.celebrationType, onDismiss: {
                    dataStore.celebrationType = nil
                })
            }
        }
        .sheet(item: Binding(
            get: { hasCompletedOnboarding ? bindable.pendingNameClash : nil },
            set: { bindable.pendingNameClash = $0 }
        )) { clash in
            NameClashSheet(clash: clash)
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
            .safeAreaInset(edge: .top, spacing: 0) {
                HouseholdSwitcher()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        } detail: {
            NavigationStack {
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
            .id(selectedTab)
        }
    }
}
#endif

// MARK: - iOS Layout

#if os(iOS)
struct IOSContentView: View {
    @Environment(DataStore.self) private var dataStore

    private var supplyAccessibilityValue: String {
        "\(dataStore.lowSupplyCount) low, \(dataStore.outOfStockSupplyCount) out of stock"
    }

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { TaskListView() }
                .tabItem { Label("Tasks", systemImage: "checklist") }

            NavigationStack { ScheduleView() }
                .tabItem { Label("Schedule", systemImage: "calendar") }

            NavigationStack { SuppliesView() }
                .tabItem {
                    Label("Supplies", systemImage: "basket.fill")
                        .accessibilityLabel("Supplies")
                        .accessibilityValue(Text(supplyAccessibilityValue))
                }
                .badge(dataStore.supplyAttentionCount)

            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
        .tint(Theme.hearthGold)
        .toolbarBackground(Theme.adventureBlue, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}
#endif
