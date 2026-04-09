import Foundation

/// Compile-time feature flags for features that cannot be enabled until
/// external configuration (Apple Developer portal, CloudKit Console, etc.)
/// is in place. Flipping a flag without completing the prerequisites may
/// crash the app because some system APIs (e.g. `CKContainer(identifier:)`)
/// trap on missing entitlements rather than throwing a catchable error.
enum Features {
    /// Gates household sharing / invite flow. When `false`, the Invite
    /// Collaborators UI is hidden and no CloudKit container is ever touched.
    ///
    /// Prerequisites before flipping to `true`:
    ///   1. Apple Developer portal — App ID `net.shadowpuppet.ADultingHD`
    ///      has CloudKit capability enabled and the container
    ///      `iCloud.net.shadowpuppet.ADultingHD` registered.
    ///   2. Provisioning profile regenerated to include the CloudKit
    ///      entitlement (automatic signing handles this on next archive).
    ///   3. CloudKit Console — schema deployed to Production (TestFlight
    ///      and App Store both use the Production environment).
    ///   4. `CloudKitSync.createOrFetchShare` verified end-to-end in a
    ///      signed build on a device signed into iCloud.
    static let cloudKitSharing: Bool = false
}
