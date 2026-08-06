import SwiftUI
import StoreKit
#if os(iOS)
import MessageUI
#endif

struct SettingsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(StoreManager.self) private var storeManager

    @AppStorage(PrefKey.showSeasonalSection) private var showSeasonalSection = false
    @SceneStorage("settingsTab") private var selectedTab: SettingsTab = .general
    @State private var showResetConfirm = false
    @State private var showImportPicker = false
    @State private var importMessage: String?
    @State private var showProUpgrade = false
    @State private var showWelcomeTour = false
    @State private var showRedeemCode = false
    @State private var editingPlayerName: String = ""
    #if os(iOS)
    @State private var showingMailComposer = false
    #endif

    private static let feedbackEmail = "adultinghd@shadowpuppet.net"
    private static let privacyURL = URL(string: "https://adultinghd.shadowpuppet.net/privacy.html")!
    private static let termsURL = URL(string: "https://adultinghd.shadowpuppet.net/terms.html")!

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, household, pro, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: "General"
            case .household: "Household"
            case .pro: "Pro"
            case .about: "About"
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = notificationManager.reminderHour
                components.minute = notificationManager.reminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                notificationManager.reminderHour = comps.hour ?? 9
                notificationManager.reminderMinute = comps.minute ?? 0
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings Tab", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Group {
                switch selectedTab {
                case .general: generalTab
                case .household: householdTab
                case .pro: proTab
                case .about: aboutTab
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Reset All Data?", isPresented: $showResetConfirm) {
            Button("Reset Everything", role: .destructive) {
                Task { await dataStore.resetAll() }
            }
        } message: {
            Text("This will delete all your tasks, completions, XP, and achievements. This cannot be undone.")
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showProUpgrade) { ProUpgradeView() }
        #if os(iOS)
        .offerCodeRedemption(isPresented: $showRedeemCode) { result in
            Task { await storeManager.restorePurchases() }
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showWelcomeTour) {
            WelcomeView(onComplete: { showWelcomeTour = false })
        }
        .sheet(isPresented: $showingMailComposer) {
            MailComposer(
                recipient: Self.feedbackEmail,
                subject: "ADultingHD Feedback",
                body: "\n\n---\nApp: ADultingHD v\(appVersion) (\(buildNumber))\nDevice: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)",
                onDismiss: { showingMailComposer = false }
            )
            .ignoresSafeArea()
        }
        #else
        .sheet(isPresented: $showWelcomeTour) {
            WelcomeView(onComplete: { showWelcomeTour = false })
                .frame(minWidth: 520, minHeight: 640)
        }
        #endif
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Notifications") {
                if notificationManager.isAuthorized {
                    @Bindable var nm = notificationManager
                    Toggle("Daily Reminder", isOn: $nm.dailyReminderEnabled)
                    if notificationManager.dailyReminderEnabled {
                        DatePicker("Reminder Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Household Activity", isOn: $nm.householdActivityEnabled)
                    Text("Get notified when household members complete tasks or move up the leaderboard")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button {
                        Task { await notificationManager.requestAuthorization() }
                    } label: {
                        Label("Enable Notifications", systemImage: "bell.badge")
                    }
                    Text("Get daily reminders about due tasks")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("iCloud Sync") {
                HStack(spacing: 10) {
                    Image(systemName: ICloudMonitor.shared.isICloud ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(ICloudMonitor.shared.isICloud ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ICloudMonitor.shared.isICloud ? "Syncing across devices" : "Sign in to iCloud to sync")
                            .font(.subheadline)
                    }
                    Spacer()
                    if ICloudMonitor.shared.isICloud {
                        Button {
                            Task { await ICloudMonitor.shared.syncNow() }
                        } label: {
                            if ICloudMonitor.shared.isSyncing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                            }
                        }
                        .disabled(ICloudMonitor.shared.isSyncing)
                    }
                }
            }

            Section("Stats") {
                LabeledContent("Tasks Completed", value: "\(dataStore.profile.totalTasksCompleted)")
                LabeledContent("Total XP", value: "\(dataStore.profile.totalXP)")
                LabeledContent("Level", value: "\(dataStore.profile.level) — \(dataStore.profile.levelTitle)")
                LabeledContent("Active / Total Tasks", value: "\(dataStore.activeTasks.count) / \(dataStore.tasks.count)")
                if let joinDate = dataStore.profile.joinDate as Date? {
                    LabeledContent("Member Since") { Text(joinDate, style: .date) }
                }
            }

            Section("Task Management") {
                NavigationLink { ManageTasksView() } label: {
                    Label("Manage Active Tasks", systemImage: "checklist")
                }
                if storeManager.isPro {
                    Toggle("Seasonal Task Suggestions", isOn: $showSeasonalSection)
                    Text("Show a dashboard card suggesting tasks for the current season.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Household Tab

    private var householdTab: some View {
        Form {
            Section("You") {
                playerNameField
            }

            Section("Current") {
                LabeledContent("Active Household", value: dataStore.activeHousehold.name)
            }

            Section("Members") {
                NavigationLink {
                    HouseholdView()
                } label: {
                    Label("Members & Leaderboard", systemImage: "person.3.fill")
                }
            }

            if storeManager.isPro {
                Section("Your Households") {
                    NavigationLink {
                        HouseholdListView()
                    } label: {
                        Label {
                            HStack {
                                Text("Manage Households")
                                Spacer()
                                Text("\(dataStore.listHouseholds().count)")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "house.lodge.fill")
                        }
                    }
                }
            } else {
                Section("Multiple Households") {
                    ProPromptCard(title: "Manage Multiple Households", icon: "house.lodge.fill")
                    Button { showProUpgrade = true } label: {
                        Label("Unlock with Pro", systemImage: "crown.fill")
                            .foregroundStyle(Theme.xpGold)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Pro Tab

    private var proTab: some View {
        Form {
            if storeManager.isPro {
                Section("Pro Membership") {
                    Label("You're a Pro member!", systemImage: "crown.fill")
                        .foregroundStyle(Theme.xpGold)
                }

                Section("Backup") {
                    Button { exportData() } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }
                    Button { showImportPicker = true } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                    if let msg = importMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.contains("Error") ? .red : .green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Section {
                    Button { showProUpgrade = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.xpGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Upgrade to Pro")
                                    .font(.headline)
                                Text("One-time purchase \u{2014} unlock all features")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    redeemCodeRow

                    Button {
                        Task { await storeManager.restorePurchases() }
                    } label: {
                        Label("Restore Purchase", systemImage: "arrow.clockwise")
                    }
                }

                Section("Backup") {
                    ProPromptCard(title: "Data Export & Import", icon: "square.and.arrow.up")
                }
            }

            Section("Tour") {
                Button { showWelcomeTour = true } label: {
                    Label("Show Welcome Tour", systemImage: "sparkles")
                }
                Text("Replay the introduction to see how ADultingHD works.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var playerNameField: some View {
        HStack {
            Text("Your Name")
            Spacer()
            TextField("Your name", text: $editingPlayerName)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .textContentType(.givenName)
                .autocorrectionDisabled(true)
                #endif
                .onAppear {
                    if editingPlayerName.isEmpty {
                        editingPlayerName = dataStore.profile.name
                    }
                }
                .onSubmit { commitPlayerName() }
        }
        .onDisappear { commitPlayerName() }
    }

    private func commitPlayerName() {
        let trimmed = editingPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != dataStore.profile.name else { return }
        Task { await dataStore.renameActiveProfile(to: trimmed) }
    }

    @ViewBuilder
    private var redeemCodeRow: some View {
        #if os(iOS)
        Button {
            showRedeemCode = true
        } label: {
            Label("Redeem Promo Code", systemImage: "ticket")
        }
        #else
        Link(destination: URL(string: "macappstore://apps.apple.com/redeem")!) {
            Label("Redeem Promo Code…", systemImage: "ticket")
        }
        #endif
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "clipboard.fill")
                        .font(.system(size: 36))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ADultingHD")
                            .font(.title3.bold())
                        Text("Gamified household task management")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Feedback") {
                #if os(iOS)
                if MFMailComposeViewController.canSendMail() {
                    Button { showingMailComposer = true } label: {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                } else if let url = URL(string: "mailto:\(Self.feedbackEmail)?subject=ADultingHD%20Feedback") {
                    Link(destination: url) {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                }
                #else
                if let url = URL(string: "mailto:\(Self.feedbackEmail)?subject=ADultingHD%20Feedback") {
                    Link(destination: url) {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                }
                #endif
            }

            Section("Legal") {
                Link(destination: Self.privacyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: Self.termsURL) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
            }

            Section("Danger Zone") {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset All Data", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func exportData() {
        Task {
            guard let data = await dataStore.exportData() else { return }
            let filename = "ADultingHD-backup-\(ISO8601DateFormatter().string(from: Date())).json"
            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.allowedContentTypes = [.json]
            if panel.runModal() == .OK, let url = panel.url {
                try? data.write(to: url)
            }
            #else
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? data.write(to: tempURL)
            #endif
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = "Error: Could not access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                importMessage = "Error: Could not read file"
                return
            }
            Task {
                let success = await dataStore.importData(data)
                importMessage = success ? "Import successful!" : "Error: Invalid backup file"
            }
        case .failure(let error):
            importMessage = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Manage Tasks View

struct ManageTasksView: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        List {
            ForEach(TaskCategory.allCases) { category in
                let tasks = dataStore.tasksByCategory[category] ?? []
                if !tasks.isEmpty {
                    Section {
                        ForEach(tasks) { task in
                            Toggle(isOn: Binding(
                                get: { task.isActive },
                                set: { _ in Task { await dataStore.toggleTask(task) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.name).font(.subheadline)
                                    Text("\(task.frequency.rawValue) - \(task.estimatedMinutes)m")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.icon)
                    }
                }
            }
        }
        .navigationTitle("Manage Tasks")
    }
}
