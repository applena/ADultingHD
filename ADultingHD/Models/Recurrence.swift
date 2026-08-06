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
    ) -> Date {
        if let override = scheduledOverrideDate {
            return calendar.startOfDay(for: override)
        }

        let createdDay = calendar.startOfDay(for: createdAt)

        switch frequency {
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
