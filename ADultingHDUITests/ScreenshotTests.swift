import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
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

        // 4. Stats (Pro analytics)
        navigateTo("Stats")
        sleep(1)
        capture("04_Stats")

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
            (name: "Stats", header: "stats-root-header"),
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
