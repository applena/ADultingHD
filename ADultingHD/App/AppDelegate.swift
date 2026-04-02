import Foundation

extension Notification.Name {
    static let cloudKitRemoteChange = Notification.Name("ADHDCloudKitRemoteChange")
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
}
#endif
