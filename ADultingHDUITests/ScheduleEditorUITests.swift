import XCTest

@MainActor
final class ScheduleEditorUITests: XCTestCase {
    func testNewTwiceWeeklyTaskCannotSaveWithOneDay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        let addTask = app.buttons["Add task"]
        XCTAssertTrue(addTask.waitForExistence(timeout: 10))
        for _ in 0..<6 where !addTask.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(addTask.isHittable)
        addTask.tap()

        let name = app.textFields["task-form-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Schedule validation")
        let schedule = app.buttons["task-form-schedule"]
        XCTAssertTrue(schedule.exists)
        schedule.tap()
        app.buttons["Twice Weekly"].tap()

        let monday = app.buttons["schedule-weekday-2"]
        for _ in 0..<8 where !monday.isHittable { app.swipeUp() }
        XCTAssertTrue(monday.isHittable)
        let save = app.buttons["task-form-save"]
        XCTAssertTrue(save.isEnabled, "Both default days should form a valid schedule")
        monday.tap()
        XCTAssertFalse(save.isEnabled, "A Twice Weekly task must not save with only Thursday selected")
        monday.tap()
        XCTAssertTrue(save.isEnabled, "Restoring Monday should enable saving again")
        app.buttons["Cancel"].tap()
    }
}
