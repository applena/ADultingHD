import XCTest
@testable import ADultingHD

final class CloudKitLifecycleTests: XCTestCase {

    func testNewLocalHouseholdsUseDistinctCloudKitZones() {
        let firstID = UUID()
        let secondID = UUID()
        let first = Household.newLocal(id: firstID, name: "First", members: [])
        let second = Household.newLocal(id: secondID, name: "Second", members: [])

        XCTAssertEqual(first.zoneName, ZoneName.uniqueHousehold(for: firstID))
        XCTAssertEqual(second.zoneName, ZoneName.uniqueHousehold(for: secondID))
        XCTAssertNotEqual(first.zoneName, second.zoneName)
        XCTAssertNotEqual(first.zoneName, ZoneName.household)
    }

    func testLegacyCloudKitZoneRequiresExplicitMigrationOptIn() {
        let household = Household.newLocal(
            id: UUID(),
            name: "Migrated",
            members: [],
            zoneName: ZoneName.household
        )

        XCTAssertEqual(household.zoneName, ZoneName.household)
    }

    func testShareRecordNamePersistsForCleanup() throws {
        var household = Household.newLocal(name: "Shared", members: [])
        household.shareRecordName = "cloudkit.share.record"

        let encoded = try JSONEncoder().encode(household)
        let decoded = try JSONDecoder().decode(Household.self, from: encoded)

        XCTAssertEqual(decoded.shareRecordName, household.shareRecordName)
        XCTAssertEqual(decoded.zoneName, household.zoneName)
    }
}
