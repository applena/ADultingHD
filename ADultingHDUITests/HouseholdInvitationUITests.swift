import XCTest

@MainActor
final class HouseholdInvitationUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app.terminate()
        try await super.tearDown()
    }

    func testExistingUserCanChooseAndDeclineInvitation() {
        launch()
        XCTAssertEqual(app.staticTexts["household-invitation-name"].label, "Maple Home")
        XCTAssertTrue(app.staticTexts["Alex invited you to share this household."].exists)
        let add = app.buttons["household-invitation-add"]
        let merge = app.buttons["household-invitation-merge"]
        XCTAssertEqual(add.value as? String, "Selected")
        capture("Invitation_Light_Overview")
        reveal(merge)
        merge.tap()
        XCTAssertEqual(merge.value as? String, "Selected")
        XCTAssertTrue(app.descendants(matching: .any)["household-invitation-merge-source"].exists)
        reveal(add)
        add.tap()
        XCTAssertEqual(add.value as? String, "Selected")
        XCTAssertFalse(app.descendants(matching: .any)["household-invitation-merge-source"].exists)
        let decline = app.buttons["household-invitation-decline"]
        reveal(decline)
        decline.tap()
        assertActiveHousehold("Demo House")
        XCTAssertFalse(invitationPage.exists)
    }

    func testAddAndMergeJoinInvitedHouseholdAndKeepOriginal() {
        for mergeChores in [false, true] {
            launch()
            if mergeChores {
                let merge = app.buttons["household-invitation-merge"]
                reveal(merge)
                merge.tap()
                XCTAssertEqual(merge.value as? String, "Selected")
                let source = app.descendants(matching: .any)
                    .matching(identifier: "household-invitation-merge-source").firstMatch
                reveal(source)
                capture("Invitation_Light_Merge")
            }
            accept()
            assertActiveHousehold("Maple Home")
            assertOriginalHouseholdRemains()
            app.terminate()
        }
    }

    func testFailedJoinKeepsInvitationAndCanRetry() {
        launch(extraArguments: ["-household-invitation-fail-once"])
        accept()
        let error = app.descendants(matching: .any).matching(identifier: "household-invitation-error").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(invitationPage.exists)
        XCTAssertTrue(app.staticTexts["household-invitation-name"].exists)
        reveal(error)
        capture("Invitation_Retry")
        let retry = app.buttons["household-invitation-accept"]
        reveal(retry)
        XCTAssertEqual(retry.label, "Try again")
        retry.tap()
        assertActiveHousehold("Maple Home")
    }

    func testDarkAccessibilityMergeRemainsReachableAndJoins() {
        launch(extraArguments: ["-household-invitation-dark", "-household-invitation-accessibility"])
        capture("Invitation_Dark_Accessibility_Overview")

        let merge = app.buttons["household-invitation-merge"]
        reveal(merge)
        merge.tap()
        XCTAssertEqual(merge.value as? String, "Selected")
        let source = app.descendants(matching: .any)
            .matching(identifier: "household-invitation-merge-source").firstMatch
        reveal(source)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(source.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(source.frame.maxX, window.maxX)

        let join = app.buttons["household-invitation-accept"]
        reveal(join)
        XCTAssertTrue(join.isEnabled)
        XCTAssertEqual(join.label, "Join and merge chores")
        XCTAssertGreaterThanOrEqual(join.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(join.frame.maxX, window.maxX)
        capture("Invitation_Dark_Accessibility_Merge")
        join.tap()
        assertActiveHousehold("Maple Home")
    }

    private var invitationPage: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "household-invitation-page").firstMatch
    }

    private func launch(extraArguments: [String] = []) {
        app.launchArguments = ["-demo", "-household-invitation-preview"] + extraArguments
        app.launch()
        XCTAssertTrue(invitationPage.waitForExistence(timeout: 10), "An existing user must see the incoming invitation before their home")
    }

    private func accept() {
        let button = app.buttons["household-invitation-accept"]
        reveal(button)
        XCTAssertTrue(button.isEnabled)
        button.tap()
    }

    private func assertActiveHousehold(_ name: String) {
        let switcher = app.buttons["household-switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 8))
        let nameMatches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", name), object: switcher
        )
        XCTAssertEqual(XCTWaiter.wait(for: [nameMatches], timeout: 5), .completed)
    }

    private func assertOriginalHouseholdRemains() {
        app.buttons["household-switcher"].tap()
        XCTAssertTrue(app.buttons["Demo House"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Maple Home"].exists)
    }

    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<12 where !element.isHittable {
            if element.frame.minY < app.windows.firstMatch.frame.minY + 80 {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, "\(element.identifier) must remain reachable by scrolling")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
