import Foundation
import CloudKit

extension Notification.Name {
    static let cloudKitRemoteChange = Notification.Name("ADHDCloudKitRemoteChange")
    /// Posted when the user accepts a CKShare invite for a household. The
    /// `object` is the `CKShare.Metadata`. Observed by `DataStore` to trigger
    /// acceptance + pull + local household registration.
    static let cloudKitShareAccepted = Notification.Name("ADHDCloudKitShareAccepted")
}

#if os(iOS)
import UIKit

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
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
            NotificationCenter.default.post(name: .cloudKitShareAccepted, object: metadata)
        }
    }
}

#elseif os(macOS)
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
            NotificationCenter.default.post(name: .cloudKitShareAccepted, object: metadata)
        }
    }
}
#endif
