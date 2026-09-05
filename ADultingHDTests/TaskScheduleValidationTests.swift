import XCTest
@testable import ADultingHD

final class TaskScheduleValidationTests: XCTestCase {
    func testTwiceWeeklyRequiresTwoDistinctValidDays() {
        XCTAssertFalse(isValid(.twiceWeekly, weekdays: []))
        XCTAssertFalse(isValid(.twiceWeekly, weekdays: [2]))
        XCTAssertTrue(isValid(.twiceWeekly, weekdays: [2, 5]))
        XCTAssertFalse(isValid(.twiceWeekly, weekdays: [2, 5, 7]))
        XCTAssertFalse(isValid(.twiceWeekly, weekdays: [0, 5]))
        XCTAssertFalse(isValid(.twiceWeekly, weekdays: [2, 8]))
    }

    func testWeeklyAndBiweeklyRequireOneDay() {
        for frequency in [TaskFrequency.weekly, .biweekly] {
            XCTAssertFalse(isValid(frequency, weekdays: []))
            XCTAssertTrue(isValid(frequency, weekdays: [1]))
            XCTAssertTrue(isValid(frequency, weekdays: [7]))
            XCTAssertFalse(isValid(frequency, weekdays: [2, 5]))
        }
    }

    func testMonthlySchedulesAcceptOnlySupportedMonthDays() {
        for frequency in [TaskFrequency.monthly, .quarterly, .semiannually, .yearly] {
            XCTAssertFalse(isValid(frequency, dayOfMonth: 0))
            XCTAssertTrue(isValid(frequency, dayOfMonth: 1))
            XCTAssertTrue(isValid(frequency, dayOfMonth: 28))
            XCTAssertFalse(isValid(frequency, dayOfMonth: 29))
        }
    }

    func testOnlyYearlyScheduleValidatesMonth() {
        XCTAssertFalse(isValid(.yearly, month: 0))
        XCTAssertTrue(isValid(.yearly, month: 1))
        XCTAssertTrue(isValid(.yearly, month: 12))
        XCTAssertFalse(isValid(.yearly, month: 13))
        XCTAssertTrue(isValid(.monthly, month: 0))
        XCTAssertTrue(isValid(.daily, weekdays: [], dayOfMonth: 0, month: 0))
        XCTAssertTrue(isValid(.unscheduled, weekdays: [], dayOfMonth: 0, month: 0))
    }

    private func isValid(
        _ frequency: TaskFrequency,
        weekdays: Set<Int> = [],
        dayOfMonth: Int = 1,
        month: Int = 1
    ) -> Bool {
        TaskScheduleValidation.isValid(
            frequency: frequency,
            weekdays: weekdays,
            dayOfMonth: dayOfMonth,
            month: month
        )
    }
}
