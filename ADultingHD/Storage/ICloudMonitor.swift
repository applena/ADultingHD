import Foundation

extension Notification.Name {
    static let dataDidSync = Notification.Name("dataDidSync")
}

enum CloudConfig {
    static let containerID = "iCloud.net.shadowpuppet.ADultingHD"
}

/// Watches for iCloud file changes and triggers a reload when the remote files update.
@MainActor @Observable
final class ICloudMonitor {
    static let shared = ICloudMonitor()

    private var query: NSMetadataQuery?
    private var debounceTask: Task<Void, Never>?
    private var lastWriteDate = Date.distantPast

    private let debounceInterval: TimeInterval = 2.0
    private let writeSuppressionWindow: TimeInterval = 5.0

    private(set) var isSyncing = false
    private(set) var isICloud = false

    private init() {}

    func start() {
        guard query == nil else { return }

        isICloud = FileManager.default.url(forUbiquityContainerIdentifier: CloudConfig.containerID) != nil

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering, object: q
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate, object: q
        )

        q.start()
        query = q
        print("☁️ iCloud monitor started, isICloud=\(isICloud)")
    }

    func stop() {
        query?.stop()
        query = nil
        debounceTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func syncNow() async {
        print("☁️ manual sync triggered")
        isSyncing = true
        NotificationCenter.default.post(name: .dataDidSync, object: nil)
        isSyncing = false
    }

    func markLocalWrite() {
        lastWriteDate = Date()
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        query?.enableUpdates()
        print("☁️ initial iCloud gather complete")
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        print("☁️ iCloud files changed, scheduling reload")
        scheduleReload()
    }

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(debounceInterval))
            guard !Task.isCancelled else { return }

            let sinceLastWrite = Date().timeIntervalSince(lastWriteDate)
            guard sinceLastWrite > writeSuppressionWindow else {
                print("☁️ skipping reload, local write was \(String(format: "%.1f", sinceLastWrite))s ago")
                return
            }

            isSyncing = true
            NotificationCenter.default.post(name: .dataDidSync, object: nil)
            isSyncing = false
            print("☁️ remote sync: triggered data reload")
        }
    }
}
