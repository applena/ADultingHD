import XCTest
import CloudKit
@testable import ADultingHD

// CloudKit integration tests — verify the invite flow against the Development
// CloudKit environment end-to-end, from share creation through the metadata
// fetch that iOS performs when a recipient taps an icloud.com/share/... link.
//
// Requirements to run:
//   1. Signed build — these tests call CKContainer(identifier:) which traps
//      on unsigned (CODE_SIGNING_ALLOWED=NO) builds; they are skipped in CI.
//   2. Simulator or device signed into iCloud under the ADultingHD dev account.
//   3. CLOUDKIT_INTEGRATION_TESTS=1 in the test scheme's environment variables.
//
// Enabling in Xcode:
//   Edit Scheme → Test → Arguments tab → Environment Variables
//   Add:  CLOUDKIT_INTEGRATION_TESTS = 1
//
// What these tests catch:
//   - CKShare not saved atomically (share URL nil)
//   - cloudkit.share record type missing from Development (metadata fetch fails)
//   - per-household zone not created (zone setup never runs)
//   - createOrFetchShare() not idempotent (second invite creates duplicate root)
@MainActor
final class CloudKitIntegrationTests: XCTestCase {

    private var sync: CloudKitSync!
    private var testHousehold: Household!

    override func setUp() async throws {
        try await super.setUp()
        // Guard before touching CloudKitSync — calling .setup() constructs
        // the lazy CKContainer, which traps on unsigned simulator builds
        // (CODE_SIGNING_ALLOWED=NO strips the icloud-services entitlement).
        // XCTest runs async setUp() *before* setUpWithError(), so the
        // skip check must live here, not in the sync variant.
        guard ProcessInfo.processInfo.environment["CLOUDKIT_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip(
                "CloudKit integration tests disabled. " +
                "Add CLOUDKIT_INTEGRATION_TESTS=1 to the scheme's environment variables to enable."
            )
        }
        guard Features.cloudKitSharing else {
            throw XCTSkip("Features.cloudKitSharing is false — flip the flag and rebuild first")
        }
        let s = CloudKitSync.shared
        await s.setup()
        guard s.isAvailable else {
            throw XCTSkip("iCloud unavailable on this machine — sign into iCloud in Simulator Settings")
        }
        sync = s
        // Use the legacy default household so multiple test runs against the
        // same iCloud account reuse one zone instead of polluting the dev
        // container with disposable zones every run.
        testHousehold = Household.newLocal(
            name: "Integration Test Household",
            members: []
        )
    }

    // MARK: - Setup

    func testSetup_marksAvailableWhenSignedIn() {
        XCTAssertTrue(sync.isAvailable)
        XCTAssertNil(sync.syncError)
    }

    // MARK: - Share creation

    // Verifies the household zone exists and CKShare + HouseholdRoot save
    // atomically. A nil share.url indicates the cloudkit.share system type
    // is missing from the Development schema (deploy Dev→Production was
    // never run, or the schema was reset).
    func testCreateOrFetchShare_returnsURLAndCorrectPermissions() async throws {
        let share = try await sync.createOrFetchShare(for: testHousehold)
        XCTAssertNotNil(share.url,
            "share.url is nil — cloudkit.share type may be missing from the Development schema. " +
            "Open CloudKit Console → Schema → Deploy Schema Changes…")
        XCTAssertEqual(share.publicPermission, .none,
            "Household share must be invite-only (publicPermission = .none)")
    }

    // A second call must return the same share URL, not create a duplicate
    // root record. Idempotency is required so the Invite button is safe to
    // tap multiple times.
    func testCreateOrFetchShare_isIdempotent() async throws {
        let url1 = try await sync.createOrFetchShare(for: testHousehold).url
        let url2 = try await sync.createOrFetchShare(for: testHousehold).url
        XCTAssertEqual(url1, url2,
            "Repeated calls returned different URLs — root record is being recreated on each invite")
    }

    // MARK: - Metadata fetch (recipient-side simulation)

    // Simulates what Apple's system does when a recipient taps the share link:
    // CKFetchShareMetadataOperation decodes the URL and asks CloudKit for the
    // share's container identifier, owner name, and title.
    //
    // Failure here means the recipient's device would show "Get the latest
    // app from the App Store" even with the app installed. Root causes:
    //   - cloudkit.share type not deployed to Production (or missing in Dev)
    //   - Share root record was saved without the share in the same operation
    func testShareURL_metadataFetchable() async throws {
        let share = try await sync.createOrFetchShare(for: testHousehold)
        guard let url = share.url else {
            XCTFail("No share URL — cannot test recipient-side metadata fetch")
            return
        }

        let metadata = try await fetchShareMetadata(url: url)
        XCTAssertEqual(
            metadata.containerIdentifier,
            "iCloud.net.shadowpuppet.ADultingHD",
            "Metadata container identifier does not match — wrong container being used?"
        )
    }

    // MARK: - Helper

    // perShareMetadataResultBlock fires exactly once per URL in the batch
    // (success or failure), always before the operation's completion block,
    // so a single continuation resume is guaranteed with no race.
    private func fetchShareMetadata(url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { cont in
            let op = CKFetchShareMetadataOperation(shareURLs: [url])
            op.shouldFetchRootRecord = false
            op.perShareMetadataResultBlock = { _, result in
                cont.resume(with: result)
            }
            sync.cloudContainer.add(op)
        }
    }
}
