import XCTest
import CloudKit
@testable import ADultingHD

final class IncomingHouseholdLifecycleTests: XCTestCase {
    func testShareURLAcceptsICloudAndCanonicalizesDisplayFragment() throws {
        let url = try XCTUnwrap(URL(string: "https://icloud.com:443/share/invitation#Maple%20House"))
        XCTAssertEqual(ShareAcceptance.validatedURL(url)?.absoluteString, "https://www.icloud.com/share/invitation")
    }

    func testShareURLRejectsOtherHostsCredentialsAndNonSharePaths() {
        for value in [
            "http://www.icloud.com/share/invite",
            "https://www.icloud.com.example.com/share/invite",
            "https://example.com/share/invite",
            "https://user@www.icloud.com/share/invite",
            "https://www.icloud.com:8443/share/invite",
            "https://www.icloud.com/share",
            "https://www.icloud.com/photos/invite",
            "https://www.icloud.com/share/invite/extra"
        ] {
            XCTAssertNil(ShareAcceptance.validatedURL(URL(string: value)!), value)
        }
    }

    @MainActor
    func testInboxDeduplicatesColdAndWarmDeliveriesButAllowsLaterReopen() throws {
        let inbox = IncomingShareInbox()
        let url = try XCTUnwrap(URL(string: "https://www.icloud.com/share/invite"))
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        inbox.enqueue(url)
        inbox.enqueue(activity)
        XCTAssertEqual(inbox.pending.count, 1)
        XCTAssertTrue(inbox.beginProcessing())
        XCTAssertFalse(inbox.beginProcessing())
        guard case .url(let deliveredURL) = inbox.next() else {
            return XCTFail("Expected the buffered invitation")
        }
        XCTAssertEqual(deliveredURL, url)
        inbox.enqueue(activity)
        XCTAssertTrue(inbox.pending.isEmpty)
        XCTAssertNil(inbox.next())
        inbox.endProcessing()
        inbox.enqueue(url)
        XCTAssertEqual(inbox.pending.count, 1)
    }

    @MainActor
    func testInboxKeepsDistinctInvitationsAndIgnoresUnrelatedActivities() throws {
        let inbox = IncomingShareInbox()
        let first = try XCTUnwrap(URL(string: "https://www.icloud.com/share/first"))
        let second = try XCTUnwrap(URL(string: "https://www.icloud.com/share/second"))
        inbox.enqueue(first)
        inbox.enqueue(second)
        let activity = NSUserActivity(activityType: "unrelated")
        activity.webpageURL = first
        inbox.enqueue(activity)
        inbox.enqueue(URL(string: "https://example.com/share/third")!)
        XCTAssertEqual(inbox.pending.map(\.id), [first.absoluteString, second.absoluteString])
    }

    func testSigningGuardRequiresExplicitSignedBuild() {
        XCTAssertTrue(CloudKitSync.signingExpected("YES"))
        XCTAssertTrue(CloudKitSync.signingExpected(true))
        XCTAssertFalse(CloudKitSync.signingExpected("NO"))
        XCTAssertFalse(CloudKitSync.signingExpected(false))
        XCTAssertFalse(CloudKitSync.signingExpected(nil))
        XCTAssertFalse(CloudKitSync.signingExpected("$(CODE_SIGNING_ALLOWED)"))
    }

    func testEntitlementPolicyRequiresBothCloudKitServiceAndThisContainer() {
        let container = CloudKitSync.containerIdentifier
        XCTAssertTrue(CloudKitSync.permitsCloudKit(services: ["CloudDocuments", "CloudKit"], containers: [container]))
        XCTAssertFalse(CloudKitSync.permitsCloudKit(services: ["CloudDocuments"], containers: [container]))
        XCTAssertFalse(CloudKitSync.permitsCloudKit(services: ["CloudKit"], containers: ["iCloud.another.app"]))
        XCTAssertFalse(CloudKitSync.permitsCloudKit(services: nil, containers: nil))
    }

    func testMetadataContainerValidationRejectsOtherApps() {
        XCTAssertNoThrow(try CloudKitSync.validateContainerIdentifier(CloudKitSync.containerIdentifier))
        XCTAssertThrowsError(try CloudKitSync.validateContainerIdentifier("iCloud.another.app")) { error in
            guard case CloudKitSyncError.invalidShareContainer = error else {
                return XCTFail("Expected an invalid-container error, received \(error)")
            }
        }
    }

    func testSubscriptionsSeparatePrivateZonesAndCoverAllSharedOwners() {
        let owned = Household.newLocal(name: "Mine", members: [], zoneName: ZoneName.household)
        let first = Household.newJoined(name: "First", members: [], zoneName: ZoneName.household, ownerUserRecordName: "first")
        let second = Household.newJoined(name: "Second", members: [], zoneName: ZoneName.household, ownerUserRecordName: "second")
        XCTAssertEqual(CloudKitSync.subscriptionID(for: owned), "household-private-zone-HouseholdZone")
        XCTAssertEqual(CloudKitSync.subscriptionID(for: first), "household-shared-database-changes")
        XCTAssertEqual(CloudKitSync.subscriptionID(for: first), CloudKitSync.subscriptionID(for: second))
        XCTAssertNotEqual(CloudKitSync.subscriptionID(for: owned), CloudKitSync.subscriptionID(for: first))
    }

    @MainActor
    func testOrdinaryTestsCannotInitializeCloudKitEvenWithSavedSharingPreference() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CLOUDKIT_INTEGRATION_TESTS"] == "1", "Explicit signed integration run")
        XCTAssertFalse(CloudKitSync.runtimeSupportsCloudKit)
        await CloudKitSync.shared.setup()
        XCTAssertFalse(CloudKitSync.shared.isAvailable)
        XCTAssertEqual(CloudKitSync.shared.syncError, "This installation is not signed for household sharing.")
    }
}
