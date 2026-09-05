import Foundation
import CloudKit
import Combine

extension Notification.Name {
    static let cloudKitRemoteChange = Notification.Name("ADHDCloudKitRemoteChange")
}

enum ShareAcceptance {
    // Compatibility for metadata activities; scene callbacks are the primary path.
    static let activityType = "com.apple.CloudKit.ShareMetadata"
    static let metadataKey = "CKShareMetadata"

    static func metadata(from activity: NSUserActivity) -> CKShare.Metadata? {
        activity.userInfo?[metadataKey] as? CKShare.Metadata
    }

    static func validatedURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              ["icloud.com", "www.icloud.com"].contains(host),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443 else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0] == "share", !parts[1].isEmpty else { return nil }
        components.scheme = "https"
        components.host = "www.icloud.com"
        components.port = nil
        components.fragment = nil
        return components.url
    }
}

/// Buffers early deliveries and deduplicates scene, activity, and URL callbacks.
@MainActor
final class IncomingShareInbox: ObservableObject {
    static let shared = IncomingShareInbox()

    enum Invitation {
        case metadata(CKShare.Metadata)
        case url(URL)

        var id: String {
            switch self {
            case .metadata(let metadata):
                if let url = metadata.share.url.flatMap(ShareAcceptance.validatedURL) {
                    return url.absoluteString
                }
                let recordID = metadata.share.recordID
                return "\(metadata.containerIdentifier)|\(recordID.zoneID.ownerName)|\(recordID.zoneID.zoneName)|\(recordID.recordName)"
            case .url(let url): return url.absoluteString
            }
        }
    }

    @Published private(set) var pending: [Invitation] = []
    private var processing = false
    private var inFlightID: String?

    func enqueue(_ metadata: CKShare.Metadata) { enqueue(.metadata(metadata)) }

    func enqueue(_ url: URL) {
        guard let url = ShareAcceptance.validatedURL(url) else { return }
        enqueue(.url(url))
    }

    func enqueue(_ activity: NSUserActivity) {
        if let metadata = ShareAcceptance.metadata(from: activity) {
            enqueue(metadata)
        } else if activity.activityType == NSUserActivityTypeBrowsingWeb,
                  let url = activity.webpageURL {
            enqueue(url)
        }
    }

    private func enqueue(_ invitation: Invitation) {
        guard invitation.id != inFlightID,
              !pending.contains(where: { $0.id == invitation.id }) else { return }
        pending.append(invitation)
    }

    func beginProcessing() -> Bool {
        guard !processing else { return false }
        processing = true
        return true
    }

    func next() -> Invitation? {
        guard !pending.isEmpty else { return nil }
        let invitation = pending.removeFirst()
        inFlightID = invitation.id
        return invitation
    }

    func endProcessing() {
        inFlightID = nil
        processing = false
    }
}

#if os(iOS)
import UIKit

/// SwiftUI creates this delegate from the app delegate's scene configuration;
/// SwiftUI continues owning the window and its hosting controller.
@MainActor
final class CloudKitShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            IncomingShareInbox.shared.enqueue(metadata)
        }
        for activity in connectionOptions.userActivities {
            IncomingShareInbox.shared.enqueue(activity)
        }
        for context in connectionOptions.urlContexts {
            IncomingShareInbox.shared.enqueue(context.url)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        IncomingShareInbox.shared.enqueue(metadata)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        IncomingShareInbox.shared.enqueue(userActivity)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts { IncomingShareInbox.shared.enqueue(context.url) }
    }
}

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = CloudKitShareSceneDelegate.self
        }
        return configuration
    }

    /// Call after flipping `householdSharingEnabled` to true so CloudKit silent
    /// pushes start flowing without waiting for the next launch.
    static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .cloudKitRemoteChange, object: nil)
        }
        completionHandler(.newData)
    }

    nonisolated func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            IncomingShareInbox.shared.enqueue(metadata)
        }
    }
}

#elseif os(macOS)
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Call after flipping `householdSharingEnabled` to true so CloudKit silent
    /// pushes start flowing without waiting for the next launch.
    static func registerForRemoteNotifications() {
        NSApplication.shared.registerForRemoteNotifications()
    }

    nonisolated func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .cloudKitRemoteChange, object: nil)
        }
    }

    nonisolated func application(
        _ application: NSApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            IncomingShareInbox.shared.enqueue(metadata)
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { IncomingShareInbox.shared.enqueue(url) }
    }

}
#endif
