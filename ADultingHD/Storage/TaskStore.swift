import Foundation
import os

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "TaskStore")

actor TaskStore {
    private let fileManager = FileManager.default

    private var documentsURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appDir = docs.appendingPathComponent("ADultingHD", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }

    private var tasksURL: URL { documentsURL.appendingPathComponent("tasks.json") }
    private var profileURL: URL { documentsURL.appendingPathComponent("profile.json") }
    private var completionsURL: URL { documentsURL.appendingPathComponent("completions.json") }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Tasks

    func loadTasks() -> [HouseholdTask] {
        guard let data = try? Data(contentsOf: tasksURL),
              let tasks = try? decoder.decode([HouseholdTask].self, from: data) else {
            logger.info("No saved tasks found, using defaults")
            let tasks = defaultHouseholdTasks
            saveTasks(tasks)
            return tasks
        }
        logger.info("Loaded \(tasks.count) tasks")
        return tasks
    }

    func saveTasks(_ tasks: [HouseholdTask]) {
        guard let data = try? encoder.encode(tasks) else { return }
        try? data.write(to: tasksURL, options: .atomic)
        logger.info("Saved \(tasks.count) tasks")
    }

    // MARK: - Profile

    func loadProfile() -> UserProfile {
        guard let data = try? Data(contentsOf: profileURL),
              let profile = try? decoder.decode(UserProfile.self, from: data) else {
            logger.info("No saved profile, creating new")
            let profile = UserProfile()
            saveProfile(profile)
            return profile
        }
        return profile
    }

    func saveProfile(_ profile: UserProfile) {
        guard let data = try? encoder.encode(profile) else { return }
        try? data.write(to: profileURL, options: .atomic)
    }

    // MARK: - Completions

    func loadCompletions() -> [TaskCompletion] {
        guard let data = try? Data(contentsOf: completionsURL),
              let completions = try? decoder.decode([TaskCompletion].self, from: data) else {
            return []
        }
        logger.info("Loaded \(completions.count) completions")
        return completions
    }

    func saveCompletions(_ completions: [TaskCompletion]) {
        guard let data = try? encoder.encode(completions) else { return }
        try? data.write(to: completionsURL, options: .atomic)
    }

    // MARK: - Export/Import

    struct AppBackup: Codable {
        let version: Int
        let exported: String
        let tasks: [HouseholdTask]
        let profile: UserProfile
        let completions: [TaskCompletion]
    }

    func exportBackup() -> Data? {
        let backup = AppBackup(
            version: 1,
            exported: ISO8601DateFormatter().string(from: Date()),
            tasks: loadTasks(),
            profile: loadProfile(),
            completions: loadCompletions()
        )
        return try? encoder.encode(backup)
    }

    func importBackup(from data: Data) -> Bool {
        guard let backup = try? decoder.decode(AppBackup.self, from: data) else {
            logger.error("Failed to decode backup")
            return false
        }
        saveTasks(backup.tasks)
        saveProfile(backup.profile)
        saveCompletions(backup.completions)
        logger.info("Imported backup with \(backup.tasks.count) tasks")
        return true
    }

    // MARK: - Reset

    func resetAllData() {
        try? fileManager.removeItem(at: tasksURL)
        try? fileManager.removeItem(at: profileURL)
        try? fileManager.removeItem(at: completionsURL)
        logger.info("All data reset")
    }
}
