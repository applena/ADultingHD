import Foundation
import os

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "TaskStore")

actor TaskStore {
    /// Sidecar fields that an older app build cannot decode or rewrite. The
    /// snapshots distinguish an old client's deliberate legacy-field edit
    /// from a routine whole-file rewrite that merely dropped additive keys.
    struct TaskPlanningMetadata: Codable, Equatable {
        let id: UUID
        let room: String?
        let scheduleFrequency: TaskFrequency
        let legacyCategorySnapshot: String
        let legacyFrequencySnapshot: String
    }

    struct StoredTaskPlanningFields: Decodable {
        let id: UUID
        let hasRoom: Bool
        let hasScheduleFrequency: Bool
        let category: String?
        let frequency: String?

        private enum CodingKeys: String, CodingKey {
            case id, room, scheduleFrequency, category, frequency
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            hasRoom = container.contains(.room)
            hasScheduleFrequency = container.contains(.scheduleFrequency)
            category = try container.decodeIfPresent(String.self, forKey: .category)
            frequency = try container.decodeIfPresent(String.self, forKey: .frequency)
        }
    }

    private let fileManager = FileManager.default

    private var documentsURL: URL {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return fileManager.temporaryDirectory.appendingPathComponent("ADultingHD", isDirectory: true)
        }
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
            logger.info("No saved tasks found for household \(householdId.uuidString, privacy: .public), starting empty")
            return []
        }
        let sourceFields = (try? decoder.decode([StoredTaskPlanningFields].self, from: data)) ?? []
        let metadataLocal = scopedLocal("task_planning.json", householdId: householdId)
        let metadataCloud = scopedCloud("task_planning.json", householdId: householdId)
        let metadataURL = newerOf(cloud: metadataCloud, local: metadataLocal)
        let metadata = (try? Data(contentsOf: metadataURL))
            .flatMap { try? decoder.decode([TaskPlanningMetadata].self, from: $0) } ?? []
        let restoredTasks = Self.restoringPlanningMetadata(
            tasks,
            sourceFields: sourceFields,
            metadata: metadata
        )
        logger.info("Loaded \(restoredTasks.count) tasks for household \(householdId.uuidString, privacy: .public)")
        return restoredTasks
    }

    func saveTasks(_ tasks: [HouseholdTask], for householdId: UUID) {
        let metadata = tasks.map { task in
            TaskPlanningMetadata(
                id: task.id,
                room: HouseholdTask.normalizedRoom(task.room),
                scheduleFrequency: task.frequency,
                legacyCategorySnapshot: task.category.rawValue,
                legacyFrequencySnapshot: task.frequency == .unscheduled
                    ? TaskFrequency.weekly.rawValue
                    : task.frequency.rawValue
            )
        }
        guard let data = try? encoder.encode(tasks),
              let metadataData = try? encoder.encode(metadata) else { return }
        let local = scopedLocal("tasks.json", householdId: householdId)
        let cloud = scopedCloud("tasks.json", householdId: householdId)
        dualWriteAt(data, local: local, cloud: cloud)
        dualWriteAt(
            metadataData,
            local: scopedLocal("task_planning.json", householdId: householdId),
            cloud: scopedCloud("task_planning.json", householdId: householdId)
        )
        logger.info("Saved \(tasks.count) tasks for household \(householdId.uuidString, privacy: .public)")
    }

    static func restoringPlanningMetadata(
        _ tasks: [HouseholdTask],
        sourceFields: [StoredTaskPlanningFields],
        metadata: [TaskPlanningMetadata]
    ) -> [HouseholdTask] {
        let sourceByID = sourceFields.reduce(into: [UUID: StoredTaskPlanningFields]()) { result, fields in
            if result[fields.id] == nil { result[fields.id] = fields }
        }
        let metadataByID = metadata.reduce(into: [UUID: TaskPlanningMetadata]()) { result, fields in
            if result[fields.id] == nil { result[fields.id] = fields }
        }

        return tasks.map { task in
            guard let source = sourceByID[task.id], let saved = metadataByID[task.id] else {
                return task
            }
            var restored = task
            let legacyCategoryWasEdited = source.category != saved.legacyCategorySnapshot
            if !source.hasRoom && !legacyCategoryWasEdited {
                restored.room = HouseholdTask.normalizedRoom(saved.room)
            }
            let legacyFrequencyWasEdited = source.frequency != saved.legacyFrequencySnapshot
            if !source.hasScheduleFrequency && !legacyFrequencyWasEdited {
                restored.frequency = saved.scheduleFrequency
            }
            return restored
        }
    }

    // MARK: - Profile

    func loadProfile() -> UserProfile {
        let url = newerOf(cloud: cloudURL(for: "profile.json"), local: profileURL)
        guard let data = try? Data(contentsOf: url),
              var profile = try? decoder.decode(UserProfile.self, from: data) else {
            logger.info("No saved profile, creating new")
            var profile = UserProfile()
            profile.name = UserProfile.defaultPlayerName()
            saveProfile(profile)
            return profile
        }
        // Legacy "Player 1" installs: upgrade to the system-suggested name
        // on platforms where one is available (currently macOS only).
        if profile.name == "Player 1" || profile.name.isEmpty {
            let suggested = UserProfile.defaultPlayerName()
            if !suggested.isEmpty && suggested != profile.name {
                profile.name = suggested
                saveProfile(profile)
            }
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
        guard Set(backup.tasks.map(\.id)).count == backup.tasks.count else {
            logger.error("Rejected backup with duplicate task IDs")
            return false
        }
        guard Set(backup.completions.map(\.id)).count == backup.completions.count else {
            logger.error("Rejected backup with duplicate completion IDs")
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
