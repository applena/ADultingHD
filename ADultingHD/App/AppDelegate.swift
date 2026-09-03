import Foundation
import CloudKit

extension Notification.Name {
    static let cloudKitRemoteChange = Notification.Name("ADHDCloudKitRemoteChange")
}

/// Magic strings for handling CKShare invites delivered via NSUserActivity
/// (the SwiftUI `onContinueUserActivity` path). These are NOT exposed by
/// Apple's SDK headers — `CKShare.Metadata.activityType` referenced by older
/// sample code does not exist as a public symbol. Hardcoded.
enum ShareAcceptance {
    static let activityType = "com.apple.CloudKit.ShareMetadata"
    static let metadataKey = "CKShareMetadata"

    static func metadata(from activity: NSUserActivity) -> CKShare.Metadata? {
        activity.userInfo?[metadataKey] as? CKShare.Metadata
    }
}

/// Buffers CKShare metadata that arrived via the AppDelegate before the
/// SwiftUI scene is ready to handle it. SwiftUI's `.task` drains it on the
/// first frame so cold-launch invites aren't lost.
///
/// On a warm-launch the `.onContinueUserActivity` modifier handles delivery
/// directly without going through this buffer.
@MainActor
final class IncomingShareInbox: ObservableObject {
    static let shared = IncomingShareInbox()

    @Published private(set) var pending: [CKShare.Metadata] = []

    private init() {}

    func enqueue(_ metadata: CKShare.Metadata) {
        pending.append(metadata)
    }

    func drain() -> [CKShare.Metadata] {
        let snapshot = pending
        pending.removeAll()
        return snapshot
    }
}

#if os(iOS)
import UIKit
import SwiftUI

/// SwiftUI owns the app's UIWindowSceneDelegate, so CloudKit share acceptance
/// is delivered there instead of to UIApplicationDelegate. This forwarding
/// proxy captures that callback and leaves SwiftUI's other scene behavior intact.
final class CloudKitShareSceneDelegateProxy: NSObject, UIWindowSceneDelegate {
    static let shared = CloudKitShareSceneDelegateProxy()

    private var originalDelegate: UISceneDelegate?

    @MainActor
    static func install(on scene: UIWindowScene) {
        let proxy = CloudKitShareSceneDelegateProxy.shared
        guard (scene.delegate as AnyObject?) !== proxy else { return }
        proxy.originalDelegate = scene.delegate
        scene.delegate = proxy
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            IncomingShareInbox.shared.enqueue(metadata)
        }
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true {
            return originalDelegate
        }
        return super.forwardingTarget(for: selector)
    }
}

/// Finds SwiftUI's hosting window as soon as it attaches to a UIWindowScene.
struct CloudKitShareSceneBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> SceneBridgeView { SceneBridgeView() }
    func updateUIView(_ uiView: SceneBridgeView, context: Context) {}

    final class SceneBridgeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let windowScene = window?.windowScene else { return }
            CloudKitShareSceneDelegateProxy.install(on: windowScene)
        }
    }
}

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if UserDefaults.standard.bool(forKey: PrefKey.householdSharingEnabled) {
            application.registerForRemoteNotifications()
        }
        return true
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: PrefKey.householdSharingEnabled) {
            NSApplication.shared.registerForRemoteNotifications()
        }
    }

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
}
#endif
