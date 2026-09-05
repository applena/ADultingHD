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
    private let directory: URL
    private let cloudDirectory: URL?
    private let usesSystemICloud: Bool
    private var unreadableFiles: Set<URL> = []

    /// Unit tests, including DataStore's internal TaskStore, must never reach
    /// application Documents or iCloud. Explicit roots also make recovery tests
    /// independent of the host's account and filesystem state.
    init(directory: URL? = nil, cloudDirectory: URL? = nil) {
        let environment = ProcessInfo.processInfo.environment
        let isTesting = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
        if let directory {
            self.directory = directory
        } else if isTesting {
            self.directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ADultingHDTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        } else {
            self.directory = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("ADultingHD", isDirectory: true)
        }
        self.cloudDirectory = cloudDirectory
        usesSystemICloud = directory == nil && cloudDirectory == nil && !isTesting
    }

    private var documentsURL: URL { directory }

    private var iCloudURL: URL? {
        if let cloudDirectory { return cloudDirectory }
        guard usesSystemICloud,
              let base = fileManager.url(forUbiquityContainerIdentifier: CloudConfig.containerID) else { return nil }
        return base.appendingPathComponent("Documents/ADultingHD", isDirectory: true)
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
        return dir.appendingPathComponent(filename)
    }

    /// A newer iCloud placeholder or corrupt JSON file must not hide a usable
    /// local copy. Reads do not rewrite either candidate during recovery.
    private func loadValid<Value: Decodable>(
        _ type: Value.Type,
        local: URL,
        cloud: URL?,
        validate: (Value) -> Bool = { _ in true }
    ) -> (value: Value, data: Data, recovered: Bool)? {
        let candidates = ([local] + (cloud.map { [$0] } ?? []))
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted { modificationDate(of: $0) > modificationDate(of: $1) }
        var recovered = false
        for url in candidates {
            do {
                let data = try Data(contentsOf: url)
                let value = try decoder.decode(type, from: data)
                guard validate(value) else { throw StorageError.invalidData }
                unreadableFiles.remove(url)
                return (value, data, recovered)
            } catch {
                recovered = true
                unreadableFiles.insert(url)
                logger.error("Could not load \(url.lastPathComponent, privacy: .public): \(error.localizedDescription)")
            }
        }
        return nil
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private enum StorageError: LocalizedError {
        case invalidData
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .invalidData: "Saved data contains invalid or duplicate identifiers."
            case .verificationFailed: "The household could not be saved. Please try again."
            }
        }
    }

    private func cloudURL(for filename: String) -> URL? {
        iCloudURL?.appendingPathComponent(filename)
    }

    /// Preserve unreadable bytes before a later explicit save replaces them.
    /// If preservation fails, fail the write instead of destroying recovery data.
    private func writeLocal(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if unreadableFiles.contains(url), fileManager.fileExists(atPath: url.path) {
            let recoveryURL = url.appendingPathExtension("recovery-\(UUID().uuidString)")
            try fileManager.copyItem(at: url, to: recoveryURL)
            unreadableFiles.remove(url)
        }
        try data.write(to: url, options: .atomic)
        guard try Data(contentsOf: url) == data else { throw StorageError.verificationFailed }
    }

    private func mirrorToCloud(_ data: Data, at cloud: URL?) {
        guard let cloud else { return }
        do {
            try writeLocal(data, to: cloud)
            if usesSystemICloud {
                Task { @MainActor in ICloudMonitor.shared.markLocalWrite() }
            }
        } catch {
            logger.error("Could not mirror \(cloud.lastPathComponent, privacy: .public) to iCloud: \(error.localizedDescription)")
        }
    }

    private func dualWriteAt(_ data: Data, local: URL, cloud: URL?) {
        do {
            try writeLocal(data, to: local)
            mirrorToCloud(data, at: cloud)
        } catch {
            logger.error("Could not save \(local.lastPathComponent, privacy: .public): \(error.localizedDescription)")
        }
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
        loadValid([HouseholdTask].self, local: tasksURL, cloud: cloudURL(for: "tasks.json"),
                  validate: { Set($0.map(\.id)).count == $0.count })?.value
    }

    // MARK: - Tasks (per-household scoped)

    func loadTasks(for householdId: UUID) -> [HouseholdTask] {
        let local = scopedLocal("tasks.json", householdId: householdId)
        let cloud = scopedCloud("tasks.json", householdId: householdId)
        guard let loaded = loadValid([HouseholdTask].self, local: local, cloud: cloud,
                                     validate: { Set($0.map(\.id)).count == $0.count }) else {
            return []
        }
        let sourceFields = (try? decoder.decode([StoredTaskPlanningFields].self, from: loaded.data)) ?? []
        let metadata = loadValid(
            [TaskPlanningMetadata].self,
            local: scopedLocal("task_planning.json", householdId: householdId),
            cloud: scopedCloud("task_planning.json", householdId: householdId)
        )?.value ?? []
        let restoredTasks = Self.restoringPlanningMetadata(
            loaded.value,
            sourceFields: sourceFields,
            metadata: metadata
        )
        logger.info("Loaded \(restoredTasks.count) tasks for household \(householdId.uuidString, privacy: .public)")
        return restoredTasks
    }

    private func encodedTaskFiles(_ tasks: [HouseholdTask]) throws -> (tasks: Data, planning: Data) {
        guard Set(tasks.map(\.id)).count == tasks.count else { throw StorageError.invalidData }
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
        return (try encoder.encode(tasks), try encoder.encode(metadata))
    }

    func saveTasks(_ tasks: [HouseholdTask], for householdId: UUID) {
        guard let files = try? encodedTaskFiles(tasks) else { return }
        let local = scopedLocal("tasks.json", householdId: householdId)
        let cloud = scopedCloud("tasks.json", householdId: householdId)
        dualWriteAt(files.tasks, local: local, cloud: cloud)
        dualWriteAt(
            files.planning,
            local: scopedLocal("task_planning.json", householdId: householdId),
            cloud: scopedCloud("task_planning.json", householdId: householdId)
        )
        logger.info("Saved \(tasks.count) tasks for household \(householdId.uuidString, privacy: .public)")
    }

    /// Joining/merging may only retire a source after every destination file
    /// is safely on disk. Cloud availability never determines local durability.
    func saveWorkspaceReliably(
        tasks: [HouseholdTask],
        supplyStock: [String: SupplyStock],
        for householdId: UUID
    ) throws {
        let taskFiles = try encodedTaskFiles(tasks)
        let files = [
            ("tasks.json", taskFiles.tasks),
            ("task_planning.json", taskFiles.planning),
            ("supply_stock.json", try encoder.encode(supplyStock))
        ]
        for (name, data) in files {
            try writeLocal(data, to: scopedLocal(name, householdId: householdId))
        }
        for (name, data) in files {
            mirrorToCloud(data, at: scopedCloud(name, householdId: householdId))
        }
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
        let cloud = cloudURL(for: "profile.json")
        guard let loaded = loadValid(UserProfile.self, local: profileURL, cloud: cloud) else {
            var profile = UserProfile()
            profile.name = UserProfile.defaultPlayerName()
            // Missing data is a fresh install; unreadable data needs recovery.
            // Do not replace the latter with a newly generated identity.
            if !fileManager.fileExists(atPath: profileURL.path),
               cloud.map({ !fileManager.fileExists(atPath: $0.path) }) ?? true {
                saveProfile(profile)
            }
            return profile
        }
        var profile = loaded.value
        if profile.name == "Player 1" || profile.name.isEmpty {
            let suggested = UserProfile.defaultPlayerName()
            if !suggested.isEmpty && suggested != profile.name {
                profile.name = suggested
                if !loaded.recovered { saveProfile(profile) }
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
        loadValid([TaskCompletion].self, local: completionsURL, cloud: cloudURL(for: "completions.json"),
                  validate: { Set($0.map(\.id)).count == $0.count })?.value ?? []
    }

    func saveCompletions(_ completions: [TaskCompletion]) {
        guard let data = try? encoder.encode(completions) else { return }
        dualWrite(data, local: completionsURL, filename: "completions.json")
    }

    // MARK: - Supply Stock (legacy flat — migration only)

    func loadSupplyStockLegacy() -> [String: SupplyStock]? {
        loadValid([String: SupplyStock].self, local: supplyStockURL, cloud: cloudURL(for: "supply_stock.json"))?.value
    }

    // MARK: - Supply Stock (per-household scoped)

    func loadSupplyStock(for householdId: UUID) -> [String: SupplyStock] {
        loadValid([String: SupplyStock].self,
                  local: scopedLocal("supply_stock.json", householdId: householdId),
                  cloud: scopedCloud("supply_stock.json", householdId: householdId))?.value ?? [:]
    }

    func saveSupplyStock(_ stock: [String: SupplyStock], for householdId: UUID) {
        guard let data = try? encoder.encode(stock) else { return }
        let local = scopedLocal("supply_stock.json", householdId: householdId)
        let cloud = scopedCloud("supply_stock.json", householdId: householdId)
        dualWriteAt(data, local: local, cloud: cloud)
    }

    // MARK: - Household Index

    func loadHouseholdIndex() -> HouseholdIndex? {
        loadValid(HouseholdIndex.self, local: householdIndexURL, cloud: cloudURL(for: "households.json")) { index in
            index.activeHousehold != nil
                && Set(index.households.map(\.id)).count == index.households.count
                && index.households.allSatisfy { Set($0.members.map(\.id)).count == $0.members.count }
        }?.value
    }

    func saveHouseholdIndex(_ index: HouseholdIndex) {
        guard let data = try? encoder.encode(index) else { return }
        dualWrite(data, local: householdIndexURL, filename: "households.json")
    }

    /// Invitation registration must persist its index before publishing a new
    /// active home; otherwise a relaunch can lose an apparently successful join.
    func saveHouseholdIndexReliably(_ index: HouseholdIndex) throws {
        let data = try encoder.encode(index)
        try writeLocal(data, to: householdIndexURL)
        mirrorToCloud(data, at: cloudURL(for: "households.json"))
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
        loadValid([UserProfile].self, local: householdURL, cloud: cloudURL(for: "household.json"))?.value
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
