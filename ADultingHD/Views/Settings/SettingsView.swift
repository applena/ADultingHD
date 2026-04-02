import SwiftUI
#if os(iOS)
import MessageUI
#endif

struct SettingsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(StoreManager.self) private var storeManager
    @State private var showResetConfirm = false
    @State private var showImportPicker = false
    @State private var importMessage: String?
    @State private var showProUpgrade = false
    #if os(iOS)
    @State private var showingMailComposer = false
    #endif

    private static let feedbackEmail = "adultinghd@shadowpuppet.net"
    private static let privacyURL = URL(string: "https://adultinghd.shadowpuppet.net/privacy.html")!
    private static let termsURL = URL(string: "https://adultinghd.shadowpuppet.net/terms.html")!

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
        #if os(macOS)
        macBody
        #else
        iosList
        #endif
    }

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

// MARK: - macOS: Tabbed Two-Column Layout

#if os(macOS)
extension SettingsView {
    private var macBody: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            accountTab
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            dataTab
                .tabItem { Label("Tasks & Data", systemImage: "externaldrive") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(minWidth: 580, minHeight: 320)
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
    }

    private var generalTab: some View {
        HStack(alignment: .top, spacing: 16) {
            Form {
                Section("Notifications") {
                    if notificationManager.isAuthorized {
                        @Bindable var nm = notificationManager
                        Toggle("Daily Reminder", isOn: $nm.dailyReminderEnabled)
                        if notificationManager.dailyReminderEnabled {
                            DatePicker("Reminder Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                        }
                    } else {
                        Button {
                            Task { await notificationManager.requestAuthorization() }
                        } label: {
                            Label("Enable Notifications", systemImage: "bell.badge")
                        }
                        Text("Get daily reminders about due tasks")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)

            Form {
                Section("iCloud Sync") {
                    HStack(spacing: 10) {
                        Image(systemName: ICloudMonitor.shared.isICloud ? "icloud.fill" : "icloud.slash")
                            .foregroundStyle(ICloudMonitor.shared.isICloud ? Color.accentColor : .secondary)
                        Text(ICloudMonitor.shared.isICloud ? "Syncing across devices" : "Sign in to iCloud to sync")
                            .font(.subheadline)
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
                Section("Your Stats") {
                    LabeledContent("Tasks Completed", value: "\(dataStore.profile.totalTasksCompleted)")
                    LabeledContent("Total XP", value: "\(dataStore.profile.totalXP)")
                    LabeledContent("Level", value: "\(dataStore.profile.level) — \(dataStore.profile.levelTitle)")
                    LabeledContent("Active / Total Tasks", value: "\(dataStore.activeTasks.count) / \(dataStore.tasks.count)")
                    if let joinDate = dataStore.profile.joinDate as Date? {
                        LabeledContent("Member Since") { Text(joinDate, style: .date) }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var accountTab: some View {
        HStack(alignment: .top, spacing: 16) {
            Form {
                if storeManager.isPro {
                    Section("Pro Membership") {
                        Label("You're a Pro member!", systemImage: "crown.fill")
                            .foregroundStyle(Theme.xpGold)
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
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)

            Form {
                if storeManager.isPro {
                    Section("Household") {
                        NavigationLink { HouseholdView() } label: {
                            Label("Manage Household", systemImage: "person.3.fill")
                        }
                        LabeledContent("Current Profile", value: dataStore.profile.name)
                    }
                } else {
                    Section("Household") {
                        ProPromptCard(title: "Household Profiles", icon: "person.3.fill")
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var dataTab: some View {
        HStack(alignment: .top, spacing: 16) {
            Form {
                Section("Task Management") {
                    NavigationLink { ManageTasksView() } label: {
                        Label("Manage Active Tasks", systemImage: "checklist")
                    }
                }
                if storeManager.isPro {
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
                        }
                    }
                } else {
                    Section("Backup") {
                        ProPromptCard(title: "Data Export & Import", icon: "square.and.arrow.up")
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)

            Form {
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
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var aboutTab: some View {
        HStack(alignment: .top, spacing: 16) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "clipboard.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ADultingHD")
                                .font(.title3.bold())
                            Text("Gamified household task management")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Version \(appVersion) (\(buildNumber))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)

            Form {
                Section("Support") {
                    if let url = URL(string: "mailto:\(Self.feedbackEmail)?subject=ADultingHD%20Feedback") {
                        Link(destination: url) {
                            Label("Send Feedback", systemImage: "envelope")
                        }
                    }
                }
                Section("Legal") {
                    Link(destination: Self.privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: Self.termsURL) {
                        Label("Terms of Use", systemImage: "doc.text")
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}
#endif

// MARK: - iOS: Scrolling List Layout

#if os(iOS)
extension SettingsView {
    private var iosList: some View {
        List {
            Section("iCloud Sync") {
                HStack(spacing: 12) {
                    Image(systemName: ICloudMonitor.shared.isICloud ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(ICloudMonitor.shared.isICloud ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud")
                            .font(.subheadline).fontWeight(.medium)
                        Text(ICloudMonitor.shared.isICloud ? "Syncing across devices" : "Sign in to iCloud to sync")
                            .font(.caption).foregroundStyle(.secondary)
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

            Section("Notifications") {
                if notificationManager.isAuthorized {
                    @Bindable var nm = notificationManager
                    Toggle("Daily Reminder", isOn: $nm.dailyReminderEnabled)
                    if notificationManager.dailyReminderEnabled {
                        DatePicker("Reminder Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                } else {
                    Button {
                        Task { await notificationManager.requestAuthorization() }
                    } label: {
                        Label("Enable Notifications", systemImage: "bell.badge")
                    }
                    Text("Get daily reminders about due tasks")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !storeManager.isPro {
                Section {
                    Button { showProUpgrade = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.title2).foregroundStyle(Theme.xpGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Upgrade to Pro")
                                    .font(.headline).foregroundStyle(.primary)
                                Text("One-time purchase \u{2014} unlock all features")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Stats") {
                LabeledContent("Total Tasks", value: "\(dataStore.tasks.count)")
                LabeledContent("Active Tasks", value: "\(dataStore.activeTasks.count)")
                LabeledContent("Tasks Completed", value: "\(dataStore.profile.totalTasksCompleted)")
                LabeledContent("Total XP", value: "\(dataStore.profile.totalXP)")
                LabeledContent("Level", value: "\(dataStore.profile.level)")
                if let joinDate = dataStore.profile.joinDate as Date? {
                    LabeledContent("Member Since") { Text(joinDate, style: .date) }
                }
            }

            Section("Task Management") {
                NavigationLink { ManageTasksView() } label: {
                    Label("Manage Active Tasks", systemImage: "checklist")
                }
            }

            if storeManager.isPro {
                Section("Household") {
                    NavigationLink { HouseholdView() } label: {
                        Label("Manage Household", systemImage: "person.3.fill")
                    }
                    LabeledContent("Current Profile", value: dataStore.profile.name)
                }
            } else {
                Section("Household") {
                    ProPromptCard(title: "Household Profiles", icon: "person.3.fill")
                }
            }

            if storeManager.isPro {
                Section("Data") {
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
                    }
                }
            } else {
                Section("Data") {
                    ProPromptCard(title: "Data Export & Import", icon: "square.and.arrow.up")
                }
            }

            Section("Feedback") {
                if MFMailComposeViewController.canSendMail() {
                    Button { showingMailComposer = true } label: {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                } else if let url = URL(string: "mailto:\(Self.feedbackEmail)?subject=ADultingHD%20Feedback") {
                    Link(destination: url) {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                }
            }

            Section {
                Link(destination: Self.privacyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: Self.termsURL) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
            }

            Section {
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.footnote).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
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
        .sheet(isPresented: $showingMailComposer) {
            MailComposer(
                recipient: Self.feedbackEmail,
                subject: "ADultingHD Feedback",
                body: "\n\n---\nApp: ADultingHD v\(appVersion) (\(buildNumber))\nDevice: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)",
                onDismiss: { showingMailComposer = false }
            )
            .ignoresSafeArea()
        }
    }
}
#endif

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
