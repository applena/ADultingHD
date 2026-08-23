import Foundation

/// Pure recurrence engine — the single source of truth for "when is this
/// task's next occurrence." Consumed by `HouseholdTask`'s `dueDate`,
/// `isDue(on:)`, and `isOverdue(on:)`, and transitively by every other
/// consumer that reads those (due-task sorting, Schedule bucketing, the
/// widget's due count, and local notifications) — so they all agree.
///
/// The core idea: an occurrence is a *fixed* calendar day, computed once
/// from a task's schedule and its last completion (or, if never completed,
/// its creation date). It does NOT float forward every time "today"
/// advances. That's what makes carry-forward work for free — comparing the
/// same fixed occurrence against a later `referenceDate` keeps returning
/// "due" (and, once the day has passed, "overdue") on every subsequent day
/// until the task is actually completed, which recomputes a new occurrence.
enum Recurrence {
    /// Days a streak survives past its last active day before dying: a
    /// completion on day D keeps the streak alive through D+1 (the grace
    /// day) and it dies at the following midnight. Shared by
    /// `computeStreak` (survival check) and `streakReminderFireDate`
    /// (which day the at-risk warning belongs on) so the two can't drift.
    private static let streakGraceDays = 1

    struct StreakSummary: Equatable {
        let currentStreak: Int
        let longestStreak: Int
        let lastActiveDate: Date?
    }

    /// Derives streak state from the completion log instead of trusting a
    /// running counter. Completion timestamps are reduced to unique calendar
    /// days, so completing several tasks on one day advances the streak once.
    /// A streak remains current through the day after the last completion —
    /// matching the app's existing end-of-day grace period — and becomes zero
    /// after a missed full day. This is intentionally pure so undo, CloudKit
    /// merges, reloads, and widgets all get the same answer.
    static func computeStreak(
        from completions: [TaskCompletion],
        asOf referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> StreakSummary {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let activeDays = Set(
            completions
                .map { calendar.startOfDay(for: $0.completedAt) }
                .filter { $0 <= referenceDay }
        )
        let sortedDays = activeDays.sorted()

        guard let lastActiveDate = sortedDays.last else {
            return StreakSummary(currentStreak: 0, longestStreak: 0, lastActiveDate: nil)
        }

        var longestStreak = 1
        var runningStreak = 1
        for (previousDay, day) in zip(sortedDays, sortedDays.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previousDay, to: day).day
            if gap == 1 {
                runningStreak += 1
            } else {
                longestStreak = max(longestStreak, runningStreak)
                runningStreak = 1
            }
        }
        longestStreak = max(longestStreak, runningStreak)

        let daysSinceLastActivity = calendar.dateComponents(
            [.day], from: lastActiveDate, to: referenceDay
        ).day ?? Int.max

        var currentStreak = 0
        if (0...streakGraceDays).contains(daysSinceLastActivity) {
            currentStreak = 1
            var cursor = lastActiveDate
            for day in sortedDays.dropLast().reversed() {
                guard let expectedPreviousDay = calendar.date(byAdding: .day, value: -1, to: cursor),
                      day == expectedPreviousDay else { break }
                currentStreak += 1
                cursor = day
            }
        }

        return StreakSummary(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            lastActiveDate: lastActiveDate
        )
    }

    /// The moment an evening "streak at risk" warning should fire, or `nil`
    /// when there's nothing to warn about. The streak survives through the
    /// day after `lastActiveDate` (see `computeStreak`'s grace period) and
    /// dies at the following midnight — so the one moment a warning has
    /// value is the evening of that grace day, while a single completion
    /// can still save it. Returns `lastActiveDate + 1 day` at
    /// `hour`:`minute`, or `nil` when the streak is already dead (`streak
    /// == 0`), never started (`lastActiveDate == nil`), or the warning
    /// moment has already passed — a trigger date in the past would fire
    /// immediately, pinging the user while they're likely in the app.
    static func streakReminderFireDate(
        lastActiveDate: Date?,
        currentStreak: Int,
        asOf referenceDate: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard currentStreak > 0, let lastActiveDate else { return nil }
        let lastActiveDay = calendar.startOfDay(for: lastActiveDate)
        guard let riskDay = calendar.date(byAdding: .day, value: streakGraceDays, to: lastActiveDay),
              let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: riskDay)
        else { return nil }
        return fireDate > referenceDate ? fireDate : nil
    }

    /// The fixed occurrence day for a task with the given schedule and
    /// completion history. Always calendar-day-normalized (midnight, in
    /// `calendar`'s time zone) so comparisons never depend on time-of-day.
    ///
    /// - A completed task's occurrence depends only on `lastCompleted` +
    ///   schedule — never on the day this function happens to be called.
    /// - A never-completed task falls back to `createdAt` as its anchor: for
    ///   an interval schedule (no specific weekday/day-of-month) the first
    ///   occurrence is the creation day itself, so a freshly added task is
    ///   immediately actionable without being born overdue. For a
    ///   weekday/day-of-month schedule, the first occurrence is the next
    ///   matching calendar day on or after creation — which may already be
    ///   in the past, so a never-completed scheduled task CAN still become
    ///   overdue once that first occurrence passes.
    /// - `scheduledOverrideDate`, when non-nil, wins outright: it's a one-off
    ///   manual reschedule (see `HouseholdTask.scheduledOverrideDate`) that
    ///   replaces the computed occurrence for this cycle only, without
    ///   touching `frequency`/`scheduledWeekdays`/`scheduledDayOfMonth`. It's
    ///   handled here rather than by callers so every consumer of this
    ///   function keeps agreeing on "when is this task's next occurrence" —
    ///   the whole point of centralizing the engine in the first place.
    static func nextOccurrence(
        frequency: TaskFrequency,
        scheduledWeekdays: [Int],
        scheduledDayOfMonth: Int?,
        scheduledMonth: Int?,
        lastCompleted: Date?,
        createdAt: Date,
        scheduledOverrideDate: Date? = nil,
        calendar: Calendar
    ) -> Date? {
        if let override = scheduledOverrideDate {
            return calendar.startOfDay(for: override)
        }

        let createdDay = calendar.startOfDay(for: createdAt)

        switch frequency {
        case .unscheduled:
            return nil

        case .daily:
            return intervalOccurrence(lastCompleted: lastCompleted, createdDay: createdDay, days: 1, calendar: calendar)

        case .weekly, .biweekly, .twiceWeekly:
            guard !scheduledWeekdays.isEmpty else {
                return intervalOccurrence(lastCompleted: lastCompleted, createdDay: createdDay, days: frequency.days, calendar: calendar)
            }
            return scheduledOccurrence(lastCompleted: lastCompleted, createdDay: createdDay, minGap: frequency.minGap, calendar: calendar) {
                nextMatchingWeekday(scheduledWeekdays, onOrAfter: $0, calendar: calendar)
            }

        case .monthly, .quarterly, .semiannually:
            guard let dayOfMonth = scheduledDayOfMonth else {
                return intervalOccurrence(lastCompleted: lastCompleted, createdDay: createdDay, days: frequency.days, calendar: calendar)
            }
            return scheduledOccurrence(lastCompleted: lastCompleted, createdDay: createdDay, minGap: frequency.minGap, calendar: calendar) {
                nextMatchingDayOfMonth(day: dayOfMonth, month: nil, onOrAfter: $0, calendar: calendar)
            }

        case .yearly:
            guard let dayOfMonth = scheduledDayOfMonth, let month = scheduledMonth else {
                return intervalOccurrence(lastCompleted: lastCompleted, createdDay: createdDay, days: frequency.days, calendar: calendar)
            }
            return scheduledOccurrence(lastCompleted: lastCompleted, createdDay: createdDay, minGap: frequency.minGap, calendar: calendar) {
                nextMatchingDayOfMonth(day: dayOfMonth, month: month, onOrAfter: $0, calendar: calendar)
            }
        }
    }

    /// Is `occurrence` due on or before `referenceDate` (calendar-day
    /// comparison, so a task completed in the evening is due starting the
    /// next morning rather than a raw 24-hour period later)?
    static func isDue(occurrence: Date, on referenceDate: Date, calendar: Calendar) -> Bool {
        occurrence <= calendar.startOfDay(for: referenceDate)
    }

    /// Has `occurrence` already passed as of `referenceDate` — i.e. is it
    /// strictly before today, not merely due today?
    static func isOverdue(occurrence: Date, on referenceDate: Date, calendar: Calendar) -> Bool {
        occurrence < calendar.startOfDay(for: referenceDate)
    }

    /// Whole calendar days `occurrence` has been overdue as of
    /// `referenceDate`. Zero when not overdue. Drives "longest-missed
    /// first" sort order and any "Nd overdue" UI badge.
    static func daysOverdue(occurrence: Date, on referenceDate: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: occurrence, to: calendar.startOfDay(for: referenceDate)).day ?? 0
        return max(0, days)
    }

    // MARK: - Private helpers

    /// Interval-style occurrence (no weekday/day-of-month anchor): `days`
    /// after the last completion, calendar-day-normalized. A never-completed
    /// task's occurrence is the creation day itself — due starting
    /// immediately, not `days` later.
    private static func intervalOccurrence(lastCompleted: Date?, createdDay: Date, days: Int, calendar: Calendar) -> Date {
        guard let last = lastCompleted else { return createdDay }
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: last)) ?? createdDay
    }

    /// Weekday/day-of-month-anchored occurrence: the next schedule match
    /// found by `search`, starting from `minGap` days after the last
    /// completion (long enough to skip the day just completed — which, for
    /// an on-schedule completion, is itself a schedule match — but short
    /// enough to still land on this cycle's occurrence). A never-completed
    /// task searches from the creation day directly, with no gap, since
    /// there's no just-completed day to skip.
    private static func scheduledOccurrence(
        lastCompleted: Date?, createdDay: Date, minGap: Int, calendar: Calendar,
        search: (Date) -> Date
    ) -> Date {
        guard let last = lastCompleted else { return search(createdDay) }
        let searchStart = calendar.date(byAdding: .day, value: minGap, to: calendar.startOfDay(for: last)) ?? createdDay
        return search(searchStart)
    }

    /// First date on or after `start` whose Apple weekday component
    /// (1 = Sunday … 7 = Saturday) is in `weekdays`. Bounded to one week —
    /// `weekdays` is never empty when called, so a match always exists.
    private static func nextMatchingWeekday(_ weekdays: [Int], onOrAfter start: Date, calendar: Calendar) -> Date {
        for offset in 0..<7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if weekdays.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
        }
        return start
    }

    /// First date on or after `start` that falls on `day` of the month
    /// (and, if `month` is given, that specific month too — for yearly
    /// schedules). `day` is always 1...28 (enforced by the schedule picker
    /// UI), so every candidate month has a valid date and there's no
    /// end-of-month or February 29 ambiguity to resolve. Bounded to 24
    /// month-steps (two years), comfortably more than a yearly schedule
    /// needs to cycle through every month.
    private static func nextMatchingDayOfMonth(day: Int, month: Int?, onOrAfter start: Date, calendar: Calendar) -> Date {
        var probe = start
        for _ in 0..<24 {
            let comps = calendar.dateComponents([.year, .month], from: probe)
            if let candidate = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: day)),
               candidate >= start,
               month == nil || calendar.component(.month, from: candidate) == month {
                return candidate
            }
            guard let monthStart = calendar.date(from: comps),
                  let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { break }
            probe = nextMonth
        }
        return start
    }
}
