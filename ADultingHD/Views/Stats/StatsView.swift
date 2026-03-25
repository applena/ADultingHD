import SwiftUI
import Charts

struct StatsView: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                xpPerDayChart
                completionTrendChart
                categoryBreakdownChart
                streakCalendar
            }
            .padding()
        }
        .navigationTitle("Stats")
    }

    // MARK: - XP Per Day (last 14 days)

    private var xpPerDay: [(date: Date, xp: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<14).reversed().compactMap { offset -> (Date, Int)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayXP = dataStore.completions
                .filter { calendar.isDate($0.completedAt, inSameDayAs: date) }
                .reduce(0) { $0 + $1.xpEarned + $1.streakBonus }
            return (date, dayXP)
        }
    }

    private var xpPerDayChart: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private var completionsPerDay: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<30).reversed().compactMap { offset -> (Date, Int)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = dataStore.completions
                .filter { calendar.isDate($0.completedAt, inSameDayAs: date) }
                .count
            return (date, count)
        }
    }

    private var completionTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private var categoryData: [(category: TaskCategory, count: Int)] {
        TaskCategory.allCases.compactMap { category in
            let count = dataStore.completions.filter { completion in
                dataStore.tasks.first { $0.id == completion.taskId }?.category == category
            }.count
            return count > 0 ? (category, count) : nil
        }
    }

    private var categoryBreakdownChart: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private var streakData: [Date: Int] {
        let calendar = Calendar.current
        var result: [Date: Int] = [:]
        for completion in dataStore.completions {
            let day = calendar.startOfDay(for: completion.completedAt)
            result[day, default: 0] += 1
        }
        return result
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

    private var streakCalendar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Activity (Last 12 Weeks)", systemImage: "square.grid.3x3.fill")
                .font(.headline)

            let data = streakData
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
