import XCTest
@testable import ADultingHD

final class WelcomeOnboardingFlowTests: XCTestCase {
    func testCreatingRouteAsksForPlayerNameAndHomeSpaces() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)

        XCTAssertEqual(flow.current, .playerName)
        flow.advance()
        XCTAssertEqual(flow.current, .homeSpaces)
        flow.advance()
        XCTAssertEqual(flow.current, .suggestions)
        flow.advance()
        XCTAssertEqual(flow.current, .inviteChoice)

        flow.answerInvitation(true)
        XCTAssertEqual(flow.current, .invite)
        XCTAssertEqual(flow.progressSteps, [
            .playerName, .homeSpaces, .suggestions, .inviteChoice, .invite, .rewards,
        ])
    }

    func testCreatingWithoutInviteGoesFromSuggestionsToRewards() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)
        flow.advance()
        flow.advance()
        XCTAssertEqual(flow.current, .suggestions)
        flow.advance()
        flow.answerInvitation(false)

        XCTAssertEqual(flow.current, .rewards)
        XCTAssertEqual(flow.progressSteps, [.playerName, .homeSpaces, .suggestions, .inviteChoice, .rewards])

        flow.back()
        XCTAssertEqual(flow.current, .inviteChoice)
        flow.back()
        XCTAssertEqual(flow.current, .suggestions)
        flow.back()
        XCTAssertEqual(flow.current, .homeSpaces)
        flow.back()
        XCTAssertEqual(flow.current, .playerName)
    }

    func testSendingInviteAdvancesToRewardsOnlyOnce() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)
        flow.advance()
        flow.advance()
        flow.advance()
        flow.answerInvitation(true)

        XCTAssertEqual(flow.current, .invite)
        flow.markInviteSent()
        XCTAssertEqual(flow.current, .rewards)

        flow.markInviteSent()
        XCTAssertEqual(flow.current, .rewards)
    }

    func testPendingInviteStartsWithJoinAndNameStep() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.pendingInvite(id: "invite-1", householdName: "Maple House", inviterName: "Alex"))

        XCTAssertEqual(flow.current, .joinHousehold)
        XCTAssertEqual(flow.progressSteps, [.joinHousehold, .suggestions, .rewards])
        XCTAssertEqual(flow.route.householdName, "Maple House")
        XCTAssertEqual(flow.route.inviterName, "Alex")

        flow.advance()
        XCTAssertEqual(flow.current, .suggestions)
    }
}
