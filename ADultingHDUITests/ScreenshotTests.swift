import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app.launchArguments = ["-demo"]
        app.launch()
    }

    func testTakeAppStoreScreenshots() throws {
        // Wait for demo data to load
        let dashboard = app.staticTexts["Good morning!"]
            .waitForExistence(timeout: 3)
        || app.staticTexts["Good afternoon!"]
            .waitForExistence(timeout: 1)
        || app.staticTexts["Good evening!"]
            .waitForExistence(timeout: 1)
        || app.staticTexts["Night owl mode!"]
            .waitForExistence(timeout: 1)

        // Give charts time to render
        if !dashboard { sleep(2) }
        sleep(1)

        // 1. Dashboard
        capture("01_Dashboard")

        // 2. Tasks
        navigateTo("Tasks")
        sleep(1)
        capture("02_Tasks")

        // 3. Schedule
        navigateTo("Schedule")
        sleep(1)
        capture("03_Schedule")

        // 4. Supplies and shopping-list status
        navigateTo("Supplies")
        sleep(1)
        capture("04_Supplies")

        // 5. Profile (achievements, avatar, leaderboard)
        navigateTo("Profile")
        sleep(1)
        capture("05_Profile")

        // 6. Navigate to Avatar Shop from profile
        let customizeButton = app.buttons["Customize"]
        if customizeButton.waitForExistence(timeout: 2) {
            customizeButton.tap()
            sleep(1)
            capture("06_AvatarShop")
        }
    }

    func testRootTabsUseCompactNavigationChrome() throws {
        let tabs = [
            (name: "Home", header: "home-root-header"),
            (name: "Tasks", header: "tasks-root-header"),
            (name: "Schedule", header: "schedule-root-header"),
            (name: "Supplies", header: "supplies-root-header"),
            (name: "Profile", header: "profile-root-header"),
        ]

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        for tab in tabs {
            navigateTo(tab.name)

            let header = app.descendants(matching: .any)
                .matching(identifier: tab.header)
                .firstMatch
            XCTAssertTrue(header.waitForExistence(timeout: 3), "Missing \(tab.name) landing header")
            capture("Chrome_\(tab.name)")
            XCTAssertLessThan(
                header.frame.minY,
                window.frame.height * 0.22,
                "\(tab.name) reserves an oversized empty navigation region"
            )

            let tabButton = app.tabBars.buttons[tab.name]
            if tabButton.exists {
                XCTAssertTrue(tabButton.isHittable, "\(tab.name) tab should remain tappable")
            }
        }

        let profileScroll = app.scrollViews.firstMatch
        let finalProfileRow = app.descendants(matching: .any)
            .matching(identifier: "profile-final-room-row")
            .firstMatch
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<12 {
            let isClear = finalProfileRow.isHittable
                && (!tabBar.exists || finalProfileRow.frame.maxY < tabBar.frame.minY)
            if isClear { break }
            profileScroll.swipeUp()
        }
        XCTAssertTrue(finalProfileRow.isHittable, "The final Profile row should scroll above the tab bar")

        if tabBar.exists {
            XCTAssertLessThan(
                finalProfileRow.frame.maxY,
                tabBar.frame.minY,
                "The floating tab bar should not cover the final Profile row"
            )
        }
    }

    func testSuppliesNavigationAndShoppingList() throws {
        navigateTo("Supplies")

        let header = app.descendants(matching: .any)
            .matching(identifier: "supplies-root-header")
            .firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Supplies should be reachable from iOS navigation")

        let shoppingListButton = app.buttons["supplies-shopping-list-button"]
        XCTAssertTrue(shoppingListButton.waitForExistence(timeout: 3), "Shopping list should expose low and out-of-stock supplies")
        shoppingListButton.tap()

        XCTAssertTrue(
            app.navigationBars["Shopping List"].waitForExistence(timeout: 3),
            "Shopping list should open from Supplies"
        )
        XCTAssertTrue(app.staticTexts["Toilet cleaner"].exists, "Out-of-stock demo supplies should appear in the shopping list")
    }

    func testDetailedStatsRemainReachableFromProfile() throws {
        navigateTo("Profile")

        let statsLink = app.descendants(matching: .any)
            .matching(identifier: "profile-detailed-stats-link")
            .firstMatch
        let profileScroll = app.scrollViews.firstMatch
        for _ in 0..<6 where !statsLink.isHittable {
            profileScroll.swipeUp()
        }
        XCTAssertTrue(statsLink.isHittable, "Detailed Stats should remain reachable after Supplies takes the fourth tab")
        statsLink.tap()

        let statsHeader = app.descendants(matching: .any)
            .matching(identifier: "stats-root-header")
            .firstMatch
        XCTAssertTrue(statsHeader.waitForExistence(timeout: 3), "Profile should navigate to Detailed Stats")
    }

    func testOnboardingFlowScreenshots() throws {
        app.terminate()
        app.launchArguments = ["-demo", "-onboarding"]
        app.launch()

        let playerPage = app.descendants(matching: .any)
            .matching(identifier: "onboarding-page-player-name")
            .firstMatch
        XCTAssertTrue(playerPage.waitForExistence(timeout: 5), "The player's name should be the first onboarding page")

        let playerName = app.textFields["onboarding-player-name-field"]
        XCTAssertTrue(playerName.waitForExistence(timeout: 3))
        replaceText(in: playerName, with: "Alex")
        capture("Onboarding_01_player_name")
        tapOnboardingPrimaryAction()

        let spacesPage = app.descendants(matching: .any)
            .matching(identifier: "onboarding-page-home-spaces")
            .firstMatch
        XCTAssertTrue(spacesPage.waitForExistence(timeout: 5), "Home spaces should follow the player's name")

        let continueBeforeSelection = app.buttons["onboarding-primary-action"]
        XCTAssertTrue(continueBeforeSelection.waitForExistence(timeout: 3))
        XCTAssertFalse(continueBeforeSelection.isEnabled, "Home spaces should require at least one selection")

        let kitchen = app.buttons["onboarding-location-kitchen"]
        let bedroom = app.buttons["onboarding-location-bedroom"]
        XCTAssertTrue(kitchen.waitForExistence(timeout: 3), "The home map should include a kitchen")
        XCTAssertTrue(bedroom.waitForExistence(timeout: 3), "The home map should include a bedroom")
        XCTAssertTrue(app.buttons["onboarding-more-spaces"].exists, "The home map should offer additional spaces")
        kitchen.tap()
        bedroom.tap()
        XCTAssertTrue(continueBeforeSelection.isEnabled, "Selecting spaces should enable the next action")
        capture("Onboarding_02_home_spaces")
        tapOnboardingPrimaryAction()

        let inviteChoice = app.descendants(matching: .any)
            .matching(identifier: "onboarding-page-invite-choice")
            .firstMatch
        XCTAssertTrue(inviteChoice.waitForExistence(timeout: 5), "Invite choice should follow home space selection")
        capture("Onboarding_03_invite_choice")
        tapOnboardingPrimaryAction()

        let invitePage = app.descendants(matching: .any)
            .matching(identifier: "onboarding-page-invite")
            .firstMatch
        XCTAssertTrue(invitePage.waitForExistence(timeout: 5), "Choosing to invite should lead to the actionable invite page")
        capture("Onboarding_04_invite")
        let skipInvite = app.buttons["onboarding-secondary-action"]
        XCTAssertTrue(skipInvite.waitForExistence(timeout: 3))
        skipInvite.tap()

        for (index, page) in ["suggestions", "rewards"].enumerated() {
            let pageView = app.descendants(matching: .any)
                .matching(identifier: "onboarding-page-\(page)")
                .firstMatch
            XCTAssertTrue(pageView.waitForExistence(timeout: 5), "Missing onboarding page \(page)")
            capture(String(format: "Onboarding_%02d_%@", index + 5, page))
            tapOnboardingPrimaryAction()
        }

        let setupPage = app.descendants(matching: .any)
            .matching(identifier: "onboarding-page-setup")
            .firstMatch
        XCTAssertTrue(setupPage.waitForExistence(timeout: 5), "Optional chore setup should follow the action-first onboarding")

        let taskSearch = app.textFields["onboarding-task-search-field"]
        XCTAssertTrue(taskSearch.waitForExistence(timeout: 3), "Task-first setup should lead with freeform entry and catalog search")
        scrollClearOfActionBar(taskSearch)
        taskSearch.tap()
        taskSearch.typeText("Polish the moon")
        dismissTaskSearchKeyboard()

        let customTaskButton = app.buttons["onboarding-add-custom-task"]
        XCTAssertTrue(customTaskButton.waitForExistence(timeout: 3), "Setup should offer a custom-task action")
        scrollClearOfActionBar(customTaskButton)
        XCTAssertTrue(customTaskButton.isHittable)
        customTaskButton.tap()

        taskSearch.tap()
        taskSearch.typeText("dishes")
        dismissTaskSearchKeyboard()

        let catalogMatch = app.buttons["onboarding-catalog-task-Wash dishes"]
        XCTAssertTrue(catalogMatch.waitForExistence(timeout: 3), "Catalog search should show matching chores")
        scrollClearOfActionBar(catalogMatch)
        XCTAssertTrue(catalogMatch.isHittable)
        catalogMatch.tap()
        XCTAssertEqual(catalogMatch.value as? String, "Selected")

        capture("Onboarding_07_setup")

        let finish = app.buttons["onboarding-primary-action"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.isHittable, "Setup action should be hittable")
        finish.tap()

        let homeHeader = app.descendants(matching: .any)
            .matching(identifier: "home-root-header")
            .firstMatch
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 3)
                || homeHeader.waitForExistence(timeout: 3),
            "Completing onboarding should reach the iPhone tabs or iPad home layout"
        )
    }

    private func tapOnboardingPrimaryAction() {
        let primary = app.buttons["onboarding-primary-action"]
        XCTAssertTrue(primary.waitForExistence(timeout: 3))
        if !primary.isHittable {
            let returnKey = app.keyboards.buttons["Return"]
            if returnKey.exists {
                returnKey.tap()
            }
        }
        XCTAssertTrue(primary.isEnabled, "Primary onboarding action should be enabled")
        if primary.isHittable {
            primary.tap()
        } else {
            primary.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let existingCount = (field.value as? String)?.count ?? 0
        if existingCount > 0 {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingCount))
        }
        field.typeText(text)
    }

    private func dismissTaskSearchKeyboard() {
        let done = app.buttons["onboarding-dismiss-task-keyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), "Setup search should offer a keyboard Done action")
        done.tap()
    }

    /// Navigate to a tab - handles both iPhone (TabBar) and iPad (sidebar) layouts
    private func navigateTo(_ tab: String) {
        // iPhone: standard tab bar
        let tabButton = app.tabBars.buttons[tab]
        if tabButton.exists {
            tabButton.tap()
            return
        }

        // iPad (iPadOS 18+): TabView renders as sidebar with cells
        // Use firstMatch to handle multiple matching elements
        let cell = app.cells[tab].firstMatch
        if cell.exists {
            cell.tap()
            return
        }

        // Fallback: try button with firstMatch
        let button = app.buttons[tab].firstMatch
        if button.exists {
            button.tap()
        }
    }

    /// Scrolls until `element` sits fully above the pinned onboarding action
    /// bar, so taps reach the element rather than the bar overlapping it.
    private func scrollClearOfActionBar(_ element: XCUIElement, maxSwipes: Int = 6) {
        let actionBar = app.buttons["onboarding-primary-action"]
        for _ in 0..<maxSwipes {
            guard element.exists, actionBar.exists else { return }
            if element.frame.maxY < actionBar.frame.minY { return }
            app.swipeUp()
        }
    }

    private func capture(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
