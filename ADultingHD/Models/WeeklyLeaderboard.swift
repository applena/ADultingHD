import Foundation

/// One household member's XP earned within a given week, used to power the
/// "Superstar of the Week" leaderboard (`DataStore.weeklyLeaderboard` /
/// `DataStore.weeklySuperstar`, surfaced in `StatsView` and `DashboardView`).
struct WeeklyXPEntry: Identifiable {
    let profile: UserProfile
    let weeklyXP: Int

    var id: UUID { profile.id }
}

/// Pure aggregation of household members' XP earned within a calendar
/// week — no I/O, no mutation. Mirrors `DataStore`'s existing all-time
/// `leaderboard`, scoped to the current week.
enum WeeklyLeaderboard {
    /// Each member's `totalXP` earned within the week (see
    /// `Calendar.weekInterval(containing:)`) containing `referenceDate`,
    /// sorted highest XP first. Completions with no `profileId` (legacy data
    /// predating per-member attribution) aren't counted toward any member.
    static func entries(
        members: [UserProfile],
        completions: [TaskCompletion],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeeklyXPEntry] {
        let weekInterval = calendar.weekInterval(containing: referenceDate)
        var xpByProfile: [UUID: Int] = [:]
        for completion in completions {
            guard let profileId = completion.profileId,
                  let weekInterval, weekInterval.contains(completion.completedAt) else { continue }
            xpByProfile[profileId, default: 0] += completion.totalXP
        }
        return members
            .map { WeeklyXPEntry(profile: $0, weeklyXP: xpByProfile[$0.id] ?? 0) }
            .sorted { $0.weeklyXP > $1.weeklyXP }
    }

    /// The sole top-scoring member for the week, or `nil` when there's no
    /// clear "superstar" to call out: a solo household (nothing to compare
    /// against), no XP earned by anyone yet this week, or a tie for first.
    static func superstar(among entries: [WeeklyXPEntry]) -> WeeklyXPEntry? {
        guard entries.count > 1, let top = entries.first, top.weeklyXP > 0 else { return nil }
        guard entries[1].weeklyXP != top.weeklyXP else { return nil }
        return top
    }
}
