import Foundation

enum ContributionMetric: String, CaseIterable, Identifiable {
    case tasks = "Tasks"
    case xp = "XP"
    var id: String { rawValue }

    func score(_ entry: WeeklyXPEntry) -> Int {
        self == .tasks ? entry.taskCount : entry.weeklyXP
    }
}

enum ContributionPeriod: String, CaseIterable, Identifiable {
    case week = "This week"
    case allTime = "All time"
    var id: String { rawValue }
}

/// Contributions from the selected period, rather than lifetime profile totals.
struct WeeklyXPEntry: Identifiable {
    let profile: UserProfile
    let weeklyXP: Int
    var taskCount: Int = 0
    var id: UUID { profile.id }
}

enum WeeklyLeaderboard {
    static func entries(
        members: [UserProfile],
        completions: [TaskCompletion],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        period: ContributionPeriod = .week,
        metric: ContributionMetric = .xp
    ) -> [WeeklyXPEntry] {
        let interval = calendar.weekInterval(containing: referenceDate)
        var xp: [UUID: Int] = [:]
        var counts: [UUID: Int] = [:]
        var seen = Set<UUID>()
        for completion in completions {
            guard let profileID = completion.profileId,
                  completion.completedAt <= referenceDate,
                  seen.insert(completion.id).inserted else { continue }
            if period == .week {
                guard let interval,
                      completion.completedAt >= interval.start,
                      completion.completedAt < interval.end else { continue }
            }
            xp[profileID, default: 0] += completion.totalXP
            counts[profileID, default: 0] += 1
        }
        return members.map {
            WeeklyXPEntry(profile: $0, weeklyXP: xp[$0.id] ?? 0, taskCount: counts[$0.id] ?? 0)
        }.sorted {
            let left = metric.score($0), right = metric.score($1)
            if left != right { return left > right }
            if $0.profile.name != $1.profile.name { return $0.profile.name < $1.profile.name }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func rank(of entry: WeeklyXPEntry, among entries: [WeeklyXPEntry], metric: ContributionMetric) -> Int {
        1 + entries.filter { metric.score($0) > metric.score(entry) }.count
    }

    static func superstar(among entries: [WeeklyXPEntry]) -> WeeklyXPEntry? {
        let leaders = champions(among: entries)
        return leaders.count == 1 ? leaders.first : nil
    }

    /// Tied positive leaders share the reward; an empty or solo week earns none.
    static func champions(among entries: [WeeklyXPEntry]) -> [WeeklyXPEntry] {
        guard entries.count > 1, let best = entries.map(\.weeklyXP).max(), best > 0 else { return [] }
        return entries.filter { $0.weeklyXP == best }
    }

    /// A crown for the last completed calendar week, derived from synced records.
    /// No bonus XP is minted, so refreshes and multiple devices cannot double-award it.
    static func previousWeekChampions(
        members: [UserProfile], completions: [TaskCompletion],
        referenceDate: Date = Date(), calendar: Calendar = .current
    ) -> [WeeklyXPEntry] {
        guard let current = calendar.weekInterval(containing: referenceDate) else { return [] }
        return champions(among: entries(
            members: members, completions: completions,
            referenceDate: current.start.addingTimeInterval(-0.001), calendar: calendar
        ))
    }
}
