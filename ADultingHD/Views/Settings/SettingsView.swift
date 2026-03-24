import SwiftUI

struct SettingsView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showResetConfirm = false
    @State private var showExportShare = false
    @State private var showImportPicker = false
    @State private var importMessage: String?

    var body: some View {
        List {
            // App Info
            Section("About") {
                HStack {
                    Image(systemName: "clipboard.fill")
                        .font(.title)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text("ADultingHD")
                            .font(.headline)
                        Text("Gamified household task management")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Task Stats
            Section("Stats") {
                LabeledContent("Total Tasks", value: "\(dataStore.tasks.count)")
                LabeledContent("Active Tasks", value: "\(dataStore.activeTasks.count)")
                LabeledContent("Tasks Completed", value: "\(dataStore.profile.totalTasksCompleted)")
                LabeledContent("Total XP", value: "\(dataStore.profile.totalXP)")
                LabeledContent("Level", value: "\(dataStore.profile.level)")
                if let joinDate = dataStore.profile.joinDate as Date? {
                    LabeledContent("Member Since") {
                        Text(joinDate, style: .date)
                    }
                }
            }

            // Task Management
            Section("Task Management") {
                NavigationLink {
                    ManageTasksView()
                } label: {
                    Label("Manage Active Tasks", systemImage: "checklist")
                }
            }

            // Data
            Section("Data") {
                Button {
                    exportData()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }

                Button {
                    showImportPicker = true
                } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }

                if let msg = importMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("Error") ? .red : .green)
                }
            }

            // Danger Zone
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
    }

    private func exportData() {
        Task {
            guard let data = await dataStore.exportData() else { return }
            let filename = "ADultingHD-backup-\(ISO8601DateFormatter().string(from: Date())).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? data.write(to: tempURL)

            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.allowedContentTypes = [.json]
            if panel.runModal() == .OK, let url = panel.url {
                try? data.write(to: url)
            }
            #else
            // On iOS, use the share sheet via a simple file export approach
            showExportShare = true
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
                                set: { _ in
                                    Task { await dataStore.toggleTask(task) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.name)
                                        .font(.subheadline)
                                    Text("\(task.frequency.rawValue) - \(task.estimatedMinutes)m")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
