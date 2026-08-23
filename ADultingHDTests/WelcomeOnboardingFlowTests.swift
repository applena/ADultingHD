import XCTest
@testable import ADultingHD

final class WelcomeOnboardingFlowTests: XCTestCase {
    func testCreatingRouteBranchesThroughNameBeforeInvite() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)

        XCTAssertEqual(flow.current, .houseName)
        flow.advance()
        XCTAssertEqual(flow.current, .inviteChoice)

        flow.answerInvitation(true)
        XCTAssertEqual(flow.current, .playerName)
        XCTAssertEqual(flow.progressSteps, [
            .houseName, .inviteChoice, .playerName, .invite, .suggestions, .rewards,
        ])

        flow.advance()
        XCTAssertEqual(flow.current, .invite)
    }

    func testCreatingWithoutInviteGoesStraightToSuggestions() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)
        flow.advance()
        flow.answerInvitation(false)

        XCTAssertEqual(flow.current, .suggestions)
        XCTAssertEqual(flow.progressSteps, [.houseName, .inviteChoice, .suggestions, .rewards])

        flow.back()
        XCTAssertEqual(flow.current, .inviteChoice)
    }

    func testSendingInviteAdvancesToSuggestionsOnlyOnce() {
        var flow = WelcomeOnboardingFlow()
        flow.start(.creating)
        flow.advance()
        flow.answerInvitation(true)
        flow.advance()

        XCTAssertEqual(flow.current, .invite)
        flow.markInviteSent()
        XCTAssertEqual(flow.current, .suggestions)

        flow.markInviteSent()
        XCTAssertEqual(flow.current, .suggestions)
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
