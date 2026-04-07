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
    private var householdIndexURL: URL { documentsURL.appendingPathComponent("households.json") }

    private func householdDir(_ householdId: UUID) -> URL {
        let dir = documentsURL
            .appendingPathComponent("households", isDirectory: true)
            .appendingPathComponent(householdId.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func scopedLocal(_ filename: String, householdId: UUID) -> URL {
        householdDir(householdId).appendingPathComponent(filename)
    }

    private func scopedCloud(_ filename: String, householdId: UUID) -> URL? {
        guard let iCloudURL else { return nil }
        let dir = iCloudURL
            .appendingPathComponent("households", isDirectory: true)
            .appendingPathComponent(householdId.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

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

    /// Write data atomically to `local` and (if present) `cloud`. Used by every
    /// load/save path so any file goes to both the local Documents directory and
    /// the iCloud ubiquity container in one call.
    private func dualWriteAt(_ data: Data, local: URL, cloud: URL?) {
        try? data.write(to: local, options: .atomic)
        if let cloud {
            try? data.write(to: cloud, options: .atomic)
        }
        Task { @MainActor in ICloudMonitor.shared.markLocalWrite() }
    }

    /// Convenience overload for flat (non-scoped) files.
    private func dualWrite(_ data: Data, local: URL, filename: String) {
        dualWriteAt(data, local: local, cloud: cloudURL(for: filename))
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

    // MARK: - Tasks (legacy flat layout — used only by migration)

    func loadTasksLegacy() -> [HouseholdTask]? {
        let url = newerOf(cloud: cloudURL(for: "tasks.json"), local: tasksURL)
        guard let data = try? Data(contentsOf: url),
              let tasks = try? decoder.decode([HouseholdTask].self, from: data) else {
            return nil
        }
        return tasks
    }

    // MARK: - Tasks (per-household scoped)

    func loadTasks(for householdId: UUID) -> [HouseholdTask] {
        let local = scopedLocal("tasks.json", householdId: householdId)
        let cloud = scopedCloud("tasks.json", householdId: householdId)
        let url = newerOf(cloud: cloud, local: local)
        guard let data = try? Data(contentsOf: url),
              let tasks = try? decoder.decode([HouseholdTask].self, from: data) else {
            logger.info("No saved tasks found for household \(householdId.uuidString, privacy: .public), using defaults")
            let tasks = defaultHouseholdTasks
            saveTasks(tasks, for: householdId)
            return tasks
        }
        logger.info("Loaded \(tasks.count) tasks for household \(householdId.uuidString, privacy: .public)")
        return tasks
    }

    func saveTasks(_ tasks: [HouseholdTask], for householdId: UUID) {
        guard let data = try? encoder.encode(tasks) else { return }
        let local = scopedLocal("tasks.json", householdId: householdId)
        let cloud = scopedCloud("tasks.json", householdId: householdId)
        dualWriteAt(data, local: local, cloud: cloud)
        logger.info("Saved \(tasks.count) tasks for household \(householdId.uuidString, privacy: .public)")
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

    // MARK: - Supply Stock (legacy flat — migration only)

    func loadSupplyStockLegacy() -> [String: SupplyStock]? {
        let url = newerOf(cloud: cloudURL(for: "supply_stock.json"), local: supplyStockURL)
        guard let data = try? Data(contentsOf: url),
              let stock = try? decoder.decode([String: SupplyStock].self, from: data) else {
            return nil
        }
        return stock
    }

    // MARK: - Supply Stock (per-household scoped)

    func loadSupplyStock(for householdId: UUID) -> [String: SupplyStock] {
        let local = scopedLocal("supply_stock.json", householdId: householdId)
        let cloud = scopedCloud("supply_stock.json", householdId: householdId)
        let url = newerOf(cloud: cloud, local: local)
        guard let data = try? Data(contentsOf: url),
              let stock = try? decoder.decode([String: SupplyStock].self, from: data) else {
            return [:]
        }
        return stock
    }

    func saveSupplyStock(_ stock: [String: SupplyStock], for householdId: UUID) {
        guard let data = try? encoder.encode(stock) else { return }
        let local = scopedLocal("supply_stock.json", householdId: householdId)
        let cloud = scopedCloud("supply_stock.json", householdId: householdId)
        dualWriteAt(data, local: local, cloud: cloud)
    }

    // MARK: - Household Index

    func loadHouseholdIndex() -> HouseholdIndex? {
        let url = newerOf(cloud: cloudURL(for: "households.json"), local: householdIndexURL)
        guard let data = try? Data(contentsOf: url),
              let index = try? decoder.decode(HouseholdIndex.self, from: data) else {
            return nil
        }
        return index
    }

    func saveHouseholdIndex(_ index: HouseholdIndex) {
        guard let data = try? encoder.encode(index) else { return }
        dualWrite(data, local: householdIndexURL, filename: "households.json")
    }

    func deleteHouseholdDirectory(_ householdId: UUID) {
        let localDir = documentsURL
            .appendingPathComponent("households", isDirectory: true)
            .appendingPathComponent(householdId.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: localDir)
        if let iCloudURL {
            let cloudDir = iCloudURL
                .appendingPathComponent("households", isDirectory: true)
                .appendingPathComponent(householdId.uuidString, isDirectory: true)
            try? fileManager.removeItem(at: cloudDir)
        }
        logger.info("Deleted household directory \(householdId.uuidString, privacy: .public)")
    }

    // MARK: - Legacy household profiles file (migration only)

    func loadLegacyHouseholdProfiles() -> [UserProfile]? {
        let url = newerOf(cloud: cloudURL(for: "household.json"), local: householdURL)
        guard let data = try? Data(contentsOf: url),
              let profiles = try? decoder.decode([UserProfile].self, from: data) else {
            return nil
        }
        return profiles
    }

    // MARK: - Export/Import

    struct AppBackup: Codable {
        let version: Int
        let exported: String
        let tasks: [HouseholdTask]
        let profile: UserProfile
        let completions: [TaskCompletion]
    }

    func exportBackup(householdId: UUID) -> Data? {
        let backup = AppBackup(
            version: 1,
            exported: ISO8601DateFormatter().string(from: Date()),
            tasks: loadTasks(for: householdId),
            profile: loadProfile(),
            completions: loadCompletions()
        )
        return try? encoder.encode(backup)
    }

    func importBackup(from data: Data, householdId: UUID) -> Bool {
        guard let backup = try? decoder.decode(AppBackup.self, from: data) else {
            logger.error("Failed to decode backup")
            return false
        }
        saveTasks(backup.tasks, for: householdId)
        saveProfile(backup.profile)
        saveCompletions(backup.completions)
        logger.info("Imported backup with \(backup.tasks.count) tasks into household \(householdId.uuidString, privacy: .public)")
        return true
    }

    // MARK: - Reset

    func resetAllData() {
        // Remove legacy flat files
        try? fileManager.removeItem(at: tasksURL)
        try? fileManager.removeItem(at: supplyStockURL)
        try? fileManager.removeItem(at: householdURL)
        // Remove global files
        try? fileManager.removeItem(at: profileURL)
        try? fileManager.removeItem(at: completionsURL)
        // Remove household directories (both local and iCloud)
        let localHouseholds = documentsURL.appendingPathComponent("households", isDirectory: true)
        try? fileManager.removeItem(at: localHouseholds)
        if let cloud = iCloudURL {
            try? fileManager.removeItem(at: cloud.appendingPathComponent("households", isDirectory: true))
        }
        try? fileManager.removeItem(at: householdIndexURL)
        if let cloudIndex = cloudURL(for: "households.json") {
            try? fileManager.removeItem(at: cloudIndex)
        }
        logger.info("All data reset")
    }
}
