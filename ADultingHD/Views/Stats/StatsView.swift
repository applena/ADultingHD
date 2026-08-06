import SwiftUI
import Charts

/// Aggregated stats pre-computed once per body evaluation. Previously each
/// chart re-ran `Dictionary(grouping: completions)` on render, so three charts
/// meant three full passes over every completion. Bundling the derived data
/// into one struct means each dependency is computed once.
private struct StatsAggregates {
    let completionsByDay: [Date: [TaskCompletion]]
    let taskCategoryMap: [UUID: TaskCategory]

    init(completions: [TaskCompletion], tasks: [HouseholdTask]) {
        let calendar = Calendar.current
        self.completionsByDay = Dictionary(grouping: completions) { calendar.startOfDay(for: $0.completedAt) }
        self.taskCategoryMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.category) })
    }
}

struct StatsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager

    var body: some View {
        let aggregates = StatsAggregates(completions: dataStore.completions, tasks: dataStore.tasks)
        ZStack {
            ScreenBackground()
            ScrollView {
                #if os(macOS)
                macOSLayout(aggregates: aggregates)
                #else
                VStack(spacing: Theme.sectionSpacing) {
                    statsHeader
                    if storeManager.isPro {
                        xpPerDayChart(aggregates: aggregates)
                        completionTrendChart(aggregates: aggregates)
                        categoryBreakdownChart(aggregates: aggregates)
                    } else {
                        ProPromptCard(title: "Pro Analytics", icon: "chart.bar.fill")
                    }
                    streakCalendar(aggregates: aggregates)
                }
                .padding()
                #endif
            }
            .rootTabScrollClearance()
        }
        .rootTabNavigation("Stats")
    }

    #if os(macOS)
    private func macOSLayout(aggregates: StatsAggregates) -> some View {
        VStack(spacing: Theme.sectionSpacing) {
            statsHeader
            if storeManager.isPro {
                HStack(alignment: .top, spacing: Theme.sectionSpacing) {
                    xpPerDayChart(aggregates: aggregates).frame(maxWidth: .infinity)
                    completionTrendChart(aggregates: aggregates).frame(maxWidth: .infinity)
                }
                HStack(alignment: .top, spacing: Theme.sectionSpacing) {
                    categoryBreakdownChart(aggregates: aggregates).frame(maxWidth: .infinity)
                    streakCalendar(aggregates: aggregates).frame(maxWidth: .infinity)
                }
            } else {
                ProPromptCard(title: "Pro Analytics", icon: "chart.bar.fill")
                streakCalendar(aggregates: aggregates)
            }
        }
        .padding()
        .macOSContentFrame()
    }
    #endif

    private var statsHeader: some View {
        LandingHeader(
            eyebrow: "Analytics",
            title: "See what is actually getting done",
            subtitle: "\(dataStore.completions.count) completions tracked across \(dataStore.tasks.count) tasks. Use this to tune the routine instead of guessing.",
            icon: "chart.bar.xaxis",
            color: Theme.successGreen
        )
        .accessibilityIdentifier("stats-root-header")
    }

    // MARK: - XP Per Day (last 14 days)

    private func xpPerDay(aggregates: StatsAggregates) -> [(date: Date, xp: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let grouped = aggregates.completionsByDay
        return (0..<14).reversed().compactMap { offset -> (Date, Int)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayXP = (grouped[date] ?? []).reduce(0) { $0 + $1.xpEarned + $1.streakBonus }
            return (date, dayXP)
        }
    }

    private func xpPerDayChart(aggregates: StatsAggregates) -> some View {
        let xpPerDay = xpPerDay(aggregates: aggregates)
        return VStack(alignment: .leading, spacing: 8) {
            Label("XP Earned (Last 14 Days)", systemImage: "star.fill")
                .font(.headline)

            if xpPerDay.contains(where: { $0.xp > 0 }) {
                Chart(xpPerDay, id: \.date) { entry in
                    BarMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("XP", entry.xp)
                    )
                    .foregroundStyle(Theme.xpGold.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .frame(height: 200)
            } else {
                emptyState("Complete tasks to see your XP chart")
            }
        }
        .card()
    }

    // MARK: - Completion Trend (last 30 days)

    private func completionsPerDay(aggregates: StatsAggregates) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let grouped = aggregates.completionsByDay
        return (0..<30).reversed().compactMap { offset -> (Date, Int)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, (grouped[date] ?? []).count)
        }
    }

    private func completionTrendChart(aggregates: StatsAggregates) -> some View {
        let completionsPerDay = completionsPerDay(aggregates: aggregates)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Completions (Last 30 Days)", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            if completionsPerDay.contains(where: { $0.count > 0 }) {
                Chart(completionsPerDay, id: \.date) { entry in
                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Tasks", entry.count)
                    )
                    .foregroundStyle(Theme.successGreen)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Tasks", entry.count)
                    )
                    .foregroundStyle(Theme.successGreen.opacity(0.1).gradient)
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .frame(height: 200)
            } else {
                emptyState("Complete tasks to see trends")
            }
        }
        .card()
    }

    // MARK: - Category Breakdown

    private func categoryData(aggregates: StatsAggregates) -> [(category: TaskCategory, count: Int)] {
        let categoryMap = aggregates.taskCategoryMap
        var counts: [TaskCategory: Int] = [:]
        for completion in dataStore.completions {
            if let category = categoryMap[completion.taskId] {
                counts[category, default: 0] += 1
            }
        }
        return TaskCategory.allCases.compactMap { category in
            guard let count = counts[category], count > 0 else { return nil }
            return (category, count)
        }
    }

    private func categoryBreakdownChart(aggregates: StatsAggregates) -> some View {
        let categoryData = categoryData(aggregates: aggregates)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Completions by Category", systemImage: "chart.pie")
                .font(.headline)

            if !categoryData.isEmpty {
                Chart(categoryData, id: \.category) { entry in
                    SectorMark(
                        angle: .value("Count", entry.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Theme.categoryColor(entry.category))
                    .cornerRadius(4)
                }
                .frame(height: 200)

                // Legend
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(categoryData, id: \.category) { entry in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Theme.categoryColor(entry.category))
                                .frame(width: 8, height: 8)
                            Text(entry.category.rawValue)
                                .font(.caption)
                            Spacer()
                            Text("\(entry.count)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                emptyState("Complete tasks to see category breakdown")
            }
        }
        .card()
    }

    // MARK: - Streak Calendar (GitHub-style heatmap, last 12 weeks)

    private func streakData(aggregates: StatsAggregates) -> [Date: Int] {
        aggregates.completionsByDay.mapValues(\.count)
    }

    private var calendarWeeks: [[Date]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Go back 12 weeks (84 days)
        guard let start = calendar.date(byAdding: .day, value: -83, to: today) else { return [] }

        var weeks: [[Date]] = []
        var current = start
        var week: [Date] = []

        while current <= today {
            week.append(current)
            if week.count == 7 {
                weeks.append(week)
                week = []
            }
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? today
        }
        if !week.isEmpty { weeks.append(week) }
        return weeks
    }

    private func heatColor(count: Int) -> Color {
        switch count {
        case 0: return Color.secondary.opacity(0.1)
        case 1: return Theme.successGreen.opacity(0.3)
        case 2...3: return Theme.successGreen.opacity(0.5)
        case 4...6: return Theme.successGreen.opacity(0.7)
        default: return Theme.successGreen
        }
    }

    private func streakCalendar(aggregates: StatsAggregates) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Activity (Last 12 Weeks)", systemImage: "square.grid.3x3.fill")
                .font(.headline)

            let data = streakData(aggregates: aggregates)
            HStack(spacing: 3) {
                // Day labels
                VStack(spacing: 3) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 12)
                    }
                }

                // Weeks grid
                ForEach(Array(calendarWeeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(week, id: \.self) { date in
                            let count = data[date] ?? 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(heatColor(count: count))
                                .frame(width: 12, height: 12)
                                .help("\(count) tasks on \(date.formatted(.dateTime.month().day()))")
                        }
                        // Pad incomplete weeks
                        ForEach(0..<(7 - week.count), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.clear)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                ForEach([0, 1, 3, 5, 8], id: \.self) { count in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(count: count))
                        .frame(width: 12, height: 12)
                }
                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: - Empty State

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
    }
}
