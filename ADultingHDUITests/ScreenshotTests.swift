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
            .matching(identifier: "profile-category-General")
            .firstMatch
        for _ in 0..<12 where !finalProfileRow.isHittable {
            profileScroll.swipeUp()
        }
        XCTAssertTrue(finalProfileRow.isHittable, "The final Profile row should scroll above the tab bar")

        let tabBar = app.tabBars.firstMatch
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

        let pages = [
            "welcome", "how-it-works", "categories", "name-household",
            "pick-rooms", "pro-pitch",
        ]

        for (index, page) in pages.enumerated() {
            let pageView = app.descendants(matching: .any)
                .matching(identifier: "onboarding-page-\(page)")
                .firstMatch
            XCTAssertTrue(pageView.waitForExistence(timeout: 5), "Missing onboarding page \(page)")

            if page == "name-household" {
                let playerName = app.textFields["onboarding-player-name-field"]
                XCTAssertTrue(playerName.waitForExistence(timeout: 3))
                playerName.tap()
                playerName.typeText("Taylor")
                let returnKey = app.keyboards.buttons["return"]
                if returnKey.exists { returnKey.tap() }
            }
            capture(String(format: "Onboarding_%02d_%@", index + 1, page))

            if page == "pro-pitch" {
                app.buttons["onboarding-secondary-action"].tap()
            } else {
                let primary = app.buttons["onboarding-primary-action"]
                XCTAssertTrue(primary.waitForExistence(timeout: 3))
                primary.tap()
            }
        }

        let invitePage = app.descendants(matching: .any)
            .matching(identifier: "onboarding-page-invite")
            .firstMatch
        if invitePage.waitForExistence(timeout: 2) {
            capture("Onboarding_07_invite")
            app.buttons["onboarding-secondary-action"].tap()
        }

        let homeHeader = app.descendants(matching: .any)
            .matching(identifier: "home-root-header")
            .firstMatch
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 3)
                || homeHeader.waitForExistence(timeout: 3),
            "Completing onboarding should reach the iPhone tabs or iPad home layout"
        )
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

    private func capture(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
