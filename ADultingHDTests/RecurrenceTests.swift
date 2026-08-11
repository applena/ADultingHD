import XCTest
@testable import ADultingHD

/// Coverage for the recurrence model introduced to fix carry-forward and
/// overdue tracking (see issue #8): a never-completed task's first
/// occurrence, calendar-day rollover across DST/month/year boundaries,
/// on-schedule vs. off-schedule completion, multi-day carry-forward, and
/// the overdue-first sort order.
final class RecurrenceTests: XCTestCase {

    // MARK: - Fixtures

    /// A fixed, UTC-based calendar so weekday/day-of-month math in these
    /// tests doesn't depend on the machine running them.
    private let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeTask(
        frequency: TaskFrequency,
        scheduledWeekdays: [Int] = [],
        scheduledDayOfMonth: Int? = nil,
        scheduledMonth: Int? = nil,
        lastCompleted: Date? = nil,
        scheduledOverrideDate: Date? = nil,
        createdAt: Date
    ) -> HouseholdTask {
        var task = HouseholdTask(
            id: UUID(), name: "Test", description: "", category: .kitchen,
            frequency: frequency, estimatedMinutes: 10, difficulty: .easy,
            supplies: [], isActive: true, lastCompleted: lastCompleted
        )
        task.scheduledWeekdays = scheduledWeekdays
        task.scheduledDayOfMonth = scheduledDayOfMonth
        task.scheduledMonth = scheduledMonth
        task.scheduledOverrideDate = scheduledOverrideDate
        task.createdAt = createdAt
        return task
    }

    // MARK: - Never-completed (first-run) tasks

    func testNeverCompletedIntervalTaskIsDueTodayNotOverdue() {
        // A freshly created weekly task with no explicit schedule (the
        // catalog/onboarding default) is immediately actionable, not born
        // overdue — fixes the regression from #11's removal of default seeding.
        let now = utcDate(2024, 3, 6)
        let task = makeTask(frequency: .weekly, createdAt: now)
        XCTAssertTrue(task.isDue(on: now, calendar: utc))
        XCTAssertFalse(task.isOverdue(on: now, calendar: utc))
    }

    func testNeverCompletedIntervalTaskCreatedLongAgoBecomesOverdue() {
        // An anchor-less task that's sat untouched for weeks should still
        // become overdue — carry-forward isn't limited to tasks that have
        // been completed at least once.
        let createdAt = utcDate(2024, 2, 20)
        let referenceDate = utcDate(2024, 3, 6)
        let task = makeTask(frequency: .weekly, createdAt: createdAt)
        XCTAssertTrue(task.isOverdue(on: referenceDate, calendar: utc))
        XCTAssertEqual(task.daysOverdue(on: referenceDate, calendar: utc), 15)
    }

    func testNeverCompletedScheduledTaskAnchorsToNextMatchNotEveryDate() {
        // Created Wednesday, scheduled for Monday: the first occurrence is
        // the upcoming Monday, not "every date" and not "tomorrow."
        let wednesday = utcDate(2024, 3, 6)
        let task = makeTask(frequency: .weekly, scheduledWeekdays: [Weekday.monday.rawValue], createdAt: wednesday)

        let nextMonday = utcDate(2024, 3, 11)
        XCTAssertEqual(task.nextOccurrence(calendar: utc).map { utc.startOfDay(for: $0) }, utc.startOfDay(for: nextMonday))

        // Not due on the creation day, or any day before that Monday.
        XCTAssertFalse(task.isDue(on: wednesday, calendar: utc))
        XCTAssertFalse(task.isDue(on: utcDate(2024, 3, 10), calendar: utc))
        // Not overdue before the first occurrence has passed.
        XCTAssertFalse(task.isOverdue(on: wednesday, calendar: utc))
        XCTAssertFalse(task.isOverdue(on: nextMonday, calendar: utc))
    }

    func testNeverCompletedScheduledTaskBecomesOverdueAfterFirstOccurrencePasses() {
        // Created 10 days ago, scheduled for Monday, still never completed:
        // that first Monday has already come and gone, so it must now be
        // overdue — not perpetually re-anchored to "whatever day you ask."
        let createdAt = utcDate(2024, 2, 26) // a Monday
        let referenceDate = utcDate(2024, 3, 6) // the following Wednesday
        let task = makeTask(frequency: .weekly, scheduledWeekdays: [Weekday.monday.rawValue], createdAt: createdAt)

        // First occurrence is the creation day itself (it matches the schedule).
        XCTAssertEqual(task.nextOccurrence(calendar: utc).map { utc.startOfDay(for: $0) }, utc.startOfDay(for: createdAt))
        XCTAssertTrue(task.isOverdue(on: referenceDate, calendar: utc))
        XCTAssertEqual(task.daysOverdue(on: referenceDate, calendar: utc), 9)
    }

    func testInactiveTaskHasNoOccurrenceAndIsNeverDueOrOverdue() {
        var task = makeTask(frequency: .daily, createdAt: utcDate(2024, 1, 1))
        task.isActive = false
        let referenceDate = utcDate(2024, 3, 6)
        XCTAssertNil(task.nextOccurrence(calendar: utc))
        XCTAssertFalse(task.isDue(on: referenceDate, calendar: utc))
        XCTAssertFalse(task.isOverdue(on: referenceDate, calendar: utc))
    }

    // MARK: - On-schedule vs. off-schedule completion

    func testOnScheduleCompletionRollsToNextMatchingWeek() {
        // Completed exactly on the scheduled Monday: next occurrence is
        // next week's Monday, not any day in between.
        let monday = utcDate(2024, 3, 4)
        let task = makeTask(frequency: .weekly, scheduledWeekdays: [Weekday.monday.rawValue], lastCompleted: monday, createdAt: monday)

        let nextMonday = utcDate(2024, 3, 11)
        XCTAssertEqual(task.nextOccurrence(calendar: utc).map { utc.startOfDay(for: $0) }, utc.startOfDay(for: nextMonday))
        XCTAssertFalse(task.isDue(on: utcDate(2024, 3, 8), calendar: utc)) // Friday that week: not due yet
    }

    func testOffScheduleCompletionStillResumesCorrectCadence() {
        // Completed two days late, on Wednesday instead of Monday: the next
        // occurrence should still be the following Monday, not immediately
        // re-triggered by the stray completion date.
        let wednesday = utcDate(2024, 3, 6)
        let task = makeTask(frequency: .weekly, scheduledWeekdays: [Weekday.monday.rawValue], lastCompleted: wednesday, createdAt: wednesday)

        let followingMonday = utcDate(2024, 3, 18)
        XCTAssertEqual(task.nextOccurrence(calendar: utc).map { utc.startOfDay(for: $0) }, utc.startOfDay(for: followingMonday))
    }

    // MARK: - Multi-day carry-forward

    func testMissedOccurrenceCarriesForwardAcrossMultipleDays() {
        // Missed Monday's occurrence entirely: it should stay due AND
        // overdue on every subsequent day, with the overdue count climbing
        // each day, until actually completed.
        let onScheduleCompletion = utcDate(2024, 3, 4) // Monday
        let task = makeTask(
            frequency: .weekly, scheduledWeekdays: [Weekday.monday.rawValue],
            lastCompleted: onScheduleCompletion, createdAt: onScheduleCompletion
        )
        // Next occurrence is Mar 11. Check the days after it passes.
        for (dayOffset, expectedOverdue) in [(0, 0), (1, 1), (2, 2), (5, 5)] {
            let checkDate = utc.date(byAdding: .day, value: dayOffset, to: utcDate(2024, 3, 11))!
            XCTAssertTrue(task.isDue(on: checkDate, calendar: utc), "should still be due at +\(dayOffset)d")
            XCTAssertEqual(task.daysOverdue(on: checkDate, calendar: utc), expectedOverdue, "overdue count at +\(dayOffset)d")
        }
    }

    // MARK: - Month / year rollover

    func testMonthlyScheduleRollsOverToNextMonth() {
        let jan28 = utcDate(2024, 1, 28)
        let task = makeTask(frequency: .monthly, scheduledDayOfMonth: 28, lastCompleted: jan28, createdAt: jan28)
        let feb28 = utcDate(2024, 2, 28)
        XCTAssertEqual(task.nextOccurrence(calendar: utc).map { utc.startOfDay(for: $0) }, utc.startOfDay(for: feb28))
    }

    func testYearlyScheduleRollsOverAcrossYearBoundary() {
        let jan15_2024 = utcDate(2024, 1, 15)
        let task = makeTask(
            frequency: .yearly, scheduledDayOfMonth: 15, scheduledMonth: 1,
            lastCompleted: jan15_2024, createdAt: jan15_2024
        )
        guard let occurrence = task.nextOccurrence(calendar: utc) else {
            return XCTFail("expected an occurrence")
        }
        let comps = utc.dateComponents([.year, .month, .day], from: occurrence)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 15)
    }

    func testWeeklyScheduleRollsOverAcrossYearBoundary() {
        // Dec 30, 2024 is a Monday; the next occurrence should land on
        // Jan 6, 2025 without getting stuck at the year boundary.
        let dec30 = utcDate(2024, 12, 30)
        let task = makeTask(frequency: .weekly, scheduledWeekdays: [Weekday.monday.rawValue], lastCompleted: dec30, createdAt: dec30)
        let jan6 = utcDate(2025, 1, 6)
        XCTAssertEqual(task.nextOccurrence(calendar: utc).map { utc.startOfDay(for: $0) }, utc.startOfDay(for: jan6))
    }

    // MARK: - DST boundary

    func testDailyOccurrenceIsStableAcrossSpringForwardDST() {
        // US "spring forward" 2024: clocks jump 2am -> 3am on Mar 10 in
        // America/New_York, so the calendar day is only 23 real hours long.
        // Calendar-day arithmetic must still land exactly on the next
        // calendar day, not drift due to the missing hour.
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!

        let beforeDST = eastern.date(from: DateComponents(year: 2024, month: 3, day: 9, hour: 22))!
        let task = makeTask(frequency: .daily, lastCompleted: beforeDST, createdAt: beforeDST)

        guard let occurrence = task.nextOccurrence(calendar: eastern) else {
            return XCTFail("expected an occurrence")
        }
        let comps = eastern.dateComponents([.year, .month, .day], from: occurrence)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 10)

        let afternoonOfDST = eastern.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 15))!
        XCTAssertTrue(task.isDue(on: afternoonOfDST, calendar: eastern))
        let dayAfter = eastern.date(from: DateComponents(year: 2024, month: 3, day: 11, hour: 12))!
        XCTAssertTrue(task.isOverdue(on: dayAfter, calendar: eastern))
    }

    // MARK: - Sort order

    func testOverdueTasksSortAboveDueTodayLongestMissedFirst() {
        let referenceDate = utcDate(2024, 3, 14) // Thursday

        // Scheduled weekly, missed Monday's occurrence by 3 days.
        let scheduledMissed = makeTask(
            frequency: .weekly, scheduledWeekdays: [Weekday.monday.rawValue],
            lastCompleted: utcDate(2024, 3, 4), createdAt: utcDate(2024, 3, 4)
        )
        // Interval weekly (no schedule), missed by 1 day.
        let intervalMissed = makeTask(frequency: .weekly, lastCompleted: utcDate(2024, 3, 6), createdAt: utcDate(2024, 3, 6))
        // Daily, due today exactly — not overdue.
        let dueToday = makeTask(frequency: .daily, lastCompleted: utcDate(2024, 3, 13), createdAt: utcDate(2024, 3, 13))

        let all = [dueToday, intervalMissed, scheduledMissed] // deliberately out of expected order
        let due = all
            .filter { $0.isDue(on: referenceDate, calendar: utc) }
            .sorted { ($0.nextOccurrence(calendar: utc) ?? .distantFuture) < ($1.nextOccurrence(calendar: utc) ?? .distantFuture) }

        XCTAssertEqual(due.map(\.id), [scheduledMissed, intervalMissed, dueToday].map(\.id))
        XCTAssertEqual(scheduledMissed.daysOverdue(on: referenceDate, calendar: utc), 3)
        XCTAssertEqual(intervalMissed.daysOverdue(on: referenceDate, calendar: utc), 1)
        XCTAssertEqual(dueToday.daysOverdue(on: referenceDate, calendar: utc), 0)
        XCTAssertFalse(dueToday.isOverdue(on: referenceDate, calendar: utc))
    }

    // MARK: - Manual reschedule override (issue #25)

    func testOverrideWinsOverComputedOccurrence() {
        // Scheduled for Monday, but manually dragged to Wednesday: the
        // occurrence should be Wednesday, not the computed Monday match.
        let createdAt = utcDate(2024, 3, 4) // Monday
        let override = utcDate(2024, 3, 6) // Wednesday
        let task = makeTask(
            frequency: .weekly, scheduledWeekdays: [Weekday.monday.rawValue],
            scheduledOverrideDate: override, createdAt: createdAt
        )
        XCTAssertEqual(task.nextOccurrence(calendar: utc), utc.startOfDay(for: override))
        XCTAssertFalse(task.isDue(on: utcDate(2024, 3, 4), calendar: utc), "should not be due on the original computed day")
        XCTAssertTrue(task.isDue(on: override, calendar: utc), "should be due on the overridden day")
    }

    func testOverrideDoesNotChangeUnderlyingRecurrenceRule() {
        // The override is a one-off move — the stored schedule fields it's
        // layered on top of are untouched, so once cleared the task returns
        // to its normal cadence rather than adopting the override day.
        let task = makeTask(
            frequency: .weekly, scheduledWeekdays: [Weekday.monday.rawValue],
            scheduledOverrideDate: utcDate(2024, 3, 6), createdAt: utcDate(2024, 3, 4)
        )
        XCTAssertEqual(task.scheduledWeekdays, [Weekday.monday.rawValue])

        var cleared = task
        cleared.scheduledOverrideDate = nil
        XCTAssertEqual(cleared.nextOccurrence(calendar: utc), utc.startOfDay(for: utcDate(2024, 3, 4)))
    }

    func testOverriddenOccurrenceCarriesForwardWhenLeftUncompleted() {
        // An override that isn't completed by its target day behaves like
        // any other fixed occurrence: it becomes overdue via carry-forward,
        // it doesn't silently revert to the computed schedule.
        let override = utcDate(2024, 3, 6)
        let task = makeTask(frequency: .weekly, scheduledOverrideDate: override, createdAt: utcDate(2024, 3, 1))
        let threeDaysLater = utcDate(2024, 3, 9)
        XCTAssertTrue(task.isDue(on: threeDaysLater, calendar: utc))
        XCTAssertTrue(task.isOverdue(on: threeDaysLater, calendar: utc))
        XCTAssertEqual(task.daysOverdue(on: threeDaysLater, calendar: utc), 3)
    }

    func testOverrideIsIgnoredForInactiveTask() {
        var task = makeTask(frequency: .weekly, scheduledOverrideDate: utcDate(2024, 3, 6), createdAt: utcDate(2024, 3, 4))
        task.isActive = false
        XCTAssertNil(task.nextOccurrence(calendar: utc))
        XCTAssertFalse(task.isDue(on: utcDate(2024, 3, 6), calendar: utc))
    }

    func testOverrideNormalizesToStartOfDay() {
        // A drop target picked from a time-of-day-bearing Date (e.g. a
        // DatePicker selection) still compares as a whole calendar day.
        let overrideWithTime = utc.date(from: DateComponents(year: 2024, month: 3, day: 6, hour: 21, minute: 45))!
        let task = makeTask(frequency: .weekly, scheduledOverrideDate: overrideWithTime, createdAt: utcDate(2024, 3, 4))
        XCTAssertEqual(task.nextOccurrence(calendar: utc), utcDate(2024, 3, 6, hour: 0))
    }

    // MARK: - Streak history

    func testComputeStreakDeduplicatesDaysAndAllowsOneDayGrace() {
        let march1 = utcDate(2024, 3, 1)
        let march2 = utcDate(2024, 3, 2)
        let march3 = utcDate(2024, 3, 3)
        let completions = [march1, march2, march2, march3].map { date in
            TaskCompletion(
                id: UUID(), taskId: UUID(), taskName: "Test", completedAt: date,
                xpEarned: 10, streakBonus: 0, notes: nil
            )
        }

        let summary = Recurrence.computeStreak(
            from: completions,
            asOf: utcDate(2024, 3, 4),
            calendar: utc
        )

        XCTAssertEqual(summary.currentStreak, 3)
        XCTAssertEqual(summary.longestStreak, 3)
        XCTAssertEqual(summary.lastActiveDate, utc.startOfDay(for: march3))
    }

    func testComputeStreakKeepsBestRunAfterAStreakRestart() {
        let dates = [1, 2, 3, 6, 7].map { utcDate(2024, 3, $0) }
        let completions = dates.map { date in
            TaskCompletion(
                id: UUID(), taskId: UUID(), taskName: "Test", completedAt: date,
                xpEarned: 10, streakBonus: 0, notes: nil
            )
        }

        let summary = Recurrence.computeStreak(
            from: completions,
            asOf: utcDate(2024, 3, 7),
            calendar: utc
        )

        XCTAssertEqual(summary.currentStreak, 2)
        XCTAssertEqual(summary.longestStreak, 3)
    }

    func testComputeStreakExpiresAfterTwoMissedDays() {
        let completions = [1, 2, 3].map { day in
            TaskCompletion(
                id: UUID(), taskId: UUID(), taskName: "Test", completedAt: utcDate(2024, 3, day),
                xpEarned: 10, streakBonus: 0, notes: nil
            )
        }

        let summary = Recurrence.computeStreak(
            from: completions,
            asOf: utcDate(2024, 3, 5),
            calendar: utc
        )

        XCTAssertEqual(summary.currentStreak, 0)
        XCTAssertEqual(summary.longestStreak, 3)
    }

    // MARK: - Streak-at-risk reminder planning

    func testStreakReminderAfterCompletingTodayFiresTomorrowEvening() {
        // Completed March 3: the streak survives March 4 (grace day) and
        // dies March 5 at midnight — so the warning belongs on March 4 at
        // the warning hour.
        let fireDate = Recurrence.streakReminderFireDate(
            lastActiveDate: utcDate(2024, 3, 3, hour: 20),
            currentStreak: 3,
            asOf: utcDate(2024, 3, 3, hour: 21),
            hour: 18, minute: 0,
            calendar: utc
        )
        XCTAssertEqual(fireDate, utcDate(2024, 3, 4, hour: 18))
    }

    func testStreakReminderOnGraceDayBeforeWarningHourFiresToday() {
        // Last completion yesterday, now mid-morning of the grace day: the
        // warning still fires this evening.
        let fireDate = Recurrence.streakReminderFireDate(
            lastActiveDate: utcDate(2024, 3, 3),
            currentStreak: 1,
            asOf: utcDate(2024, 3, 4, hour: 9),
            hour: 18, minute: 30,
            calendar: utc
        )
        XCTAssertEqual(fireDate, utcDate(2024, 3, 4, hour: 18, minute: 30))
    }

    func testStreakReminderIsNilOncePastTheWarningMoment() {
        // 19:00 on the grace day with an 18:00 warning hour: scheduling now
        // would fire immediately — return nil instead.
        XCTAssertNil(Recurrence.streakReminderFireDate(
            lastActiveDate: utcDate(2024, 3, 3),
            currentStreak: 2,
            asOf: utcDate(2024, 3, 4, hour: 19),
            hour: 18, minute: 0,
            calendar: utc
        ))
    }

    func testStreakReminderIsNilForDeadOrAbsentStreak() {
        // Streak already reported dead — nothing left to protect.
        XCTAssertNil(Recurrence.streakReminderFireDate(
            lastActiveDate: utcDate(2024, 3, 1),
            currentStreak: 0,
            asOf: utcDate(2024, 3, 4),
            hour: 18, minute: 0,
            calendar: utc
        ))
        // Never completed anything.
        XCTAssertNil(Recurrence.streakReminderFireDate(
            lastActiveDate: nil,
            currentStreak: 1,
            asOf: utcDate(2024, 3, 4),
            hour: 18, minute: 0,
            calendar: utc
        ))
    }
}
