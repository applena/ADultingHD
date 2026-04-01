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

    private var iCloudURL: URL? {
        guard let base = fileManager.url(forUbiquityContainerIdentifier: CloudConfig.containerID) else { return nil }
        let dir = base.appendingPathComponent("Documents/ADultingHD", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var tasksURL: URL { documentsURL.appendingPathComponent("tasks.json") }
    private var profileURL: URL { documentsURL.appendingPathComponent("profile.json") }
    private var completionsURL: URL { documentsURL.appendingPathComponent("completions.json") }
    private var supplyStockURL: URL { documentsURL.appendingPathComponent("supply_stock.json") }
    private var householdURL: URL { documentsURL.appendingPathComponent("household.json") }

    // Returns the newer of cloud or local file.
    private func newerOf(cloud: URL?, local: URL) -> URL {
        guard let cloud, fileManager.fileExists(atPath: cloud.path) else { return local }
        let cloudDate = (try? fileManager.attributesOfItem(atPath: cloud.path)[.modificationDate] as? Date) ?? .distantPast
        let localDate = (try? fileManager.attributesOfItem(atPath: local.path)[.modificationDate] as? Date) ?? .distantPast
        return cloudDate >= localDate ? cloud : local
    }

    private func cloudURL(for filename: String) -> URL? {
        iCloudURL?.appendingPathComponent(filename)
    }

    private func dualWrite(_ data: Data, local: URL, filename: String) {
        try? data.write(to: local, options: .atomic)
        if let cloud = cloudURL(for: filename) {
            try? data.write(to: cloud, options: .atomic)
        }
        Task { @MainActor in ICloudMonitor.shared.markLocalWrite() }
    }

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
        let url = newerOf(cloud: cloudURL(for: "tasks.json"), local: tasksURL)
        guard let data = try? Data(contentsOf: url),
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
        dualWrite(data, local: tasksURL, filename: "tasks.json")
        logger.info("Saved \(tasks.count) tasks")
    }

    // MARK: - Profile

    func loadProfile() -> UserProfile {
        let url = newerOf(cloud: cloudURL(for: "profile.json"), local: profileURL)
        guard let data = try? Data(contentsOf: url),
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
        dualWrite(data, local: profileURL, filename: "profile.json")
    }

    // MARK: - Completions

    func loadCompletions() -> [TaskCompletion] {
        let url = newerOf(cloud: cloudURL(for: "completions.json"), local: completionsURL)
        guard let data = try? Data(contentsOf: url),
              let completions = try? decoder.decode([TaskCompletion].self, from: data) else {
            return []
        }
        logger.info("Loaded \(completions.count) completions")
        return completions
    }

    func saveCompletions(_ completions: [TaskCompletion]) {
        guard let data = try? encoder.encode(completions) else { return }
        dualWrite(data, local: completionsURL, filename: "completions.json")
    }

    // MARK: - Household Profiles

    func loadHouseholdProfiles() -> [UserProfile] {
        let url = newerOf(cloud: cloudURL(for: "household.json"), local: householdURL)
        guard let data = try? Data(contentsOf: url),
              let profiles = try? decoder.decode([UserProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    func saveHouseholdProfiles(_ profiles: [UserProfile]) {
        guard let data = try? encoder.encode(profiles) else { return }
        dualWrite(data, local: householdURL, filename: "household.json")
    }

    // MARK: - Supply Stock

    func loadSupplyStock() -> [String: SupplyStock] {
        let url = newerOf(cloud: cloudURL(for: "supply_stock.json"), local: supplyStockURL)
        guard let data = try? Data(contentsOf: url),
              let stock = try? decoder.decode([String: SupplyStock].self, from: data) else {
            return [:]
        }
        return stock
    }

    func saveSupplyStock(_ stock: [String: SupplyStock]) {
        guard let data = try? encoder.encode(stock) else { return }
        dualWrite(data, local: supplyStockURL, filename: "supply_stock.json")
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
