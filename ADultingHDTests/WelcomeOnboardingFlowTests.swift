import XCTest
@testable import ADultingHD

final class WelcomeOnboardingFlowTests: XCTestCase {
    func testCreatingRouteUsesFivePageOnboarding() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)

        XCTAssertEqual(flow.current, .playerName)
        XCTAssertEqual(flow.progressSteps, [.playerName, .homeSpaces, .suggestions, .invite, .homeTour])
        flow.advance()
        XCTAssertEqual(flow.current, .homeSpaces)
        flow.advance()
        XCTAssertEqual(flow.current, .suggestions)
        flow.advance()
        XCTAssertEqual(flow.current, .invite)
        flow.advance()
        XCTAssertEqual(flow.current, .homeTour)

        flow.back()
        XCTAssertEqual(flow.current, .invite)
        flow.back()
        XCTAssertEqual(flow.current, .suggestions)
    }

    func testSendingInviteAdvancesToHomeTourOnlyOnce() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)
        flow.advance()
        flow.advance()
        flow.advance()

        XCTAssertEqual(flow.current, .invite)
        flow.markInviteSent()
        XCTAssertEqual(flow.current, .homeTour)

        flow.markInviteSent()
        XCTAssertEqual(flow.current, .homeTour)
    }

    func testClosingCompletedInvitePresentationAdvancesToHomeTour() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)
        flow.advance()
        flow.advance()
        flow.advance()

        flow.finishInvitePresentation(wasInvalidated: false)

        XCTAssertEqual(flow.current, .homeTour)
    }

    func testInvalidatedInvitePresentationStaysOnInvitePage() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)
        flow.advance()
        flow.advance()
        flow.advance()

        flow.finishInvitePresentation(wasInvalidated: true)

        XCTAssertEqual(flow.current, .invite)
    }

    func testPendingInviteStartsWithJoinAndNameStep() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.pendingInvite(id: "invite-1", householdName: "Maple House", inviterName: "Alex"))

        XCTAssertEqual(flow.current, .playerName)
        XCTAssertEqual(flow.progressSteps, [.playerName, .joinHousehold, .homeTour])
        XCTAssertEqual(flow.route.householdName, "Maple House")
        XCTAssertEqual(flow.route.inviterName, "Alex")

        flow.advance()
        XCTAssertEqual(flow.current, .joinHousehold)
        flow.advance()
        XCTAssertEqual(flow.current, .homeTour)
    }
}
