import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct TaskEntry: TimelineEntry {
    let date: Date
    let dueTasks: Int
    let overdueTasks: Int
    let streak: Int
    let level: Int
    let levelTitle: String
    let xpProgress: Double
    let totalXP: Int
    let todayCompleted: Int
    let nextTask: String?
}

// MARK: - Timeline Provider

struct TaskTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), dueTasks: 5, overdueTasks: 1, streak: 7, level: 3, levelTitle: "Chore Champion", xpProgress: 0.6, totalXP: 450, todayCompleted: 2, nextTask: "Wash Dishes")
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = currentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> TaskEntry {
        TaskEntry(
            date: Date(),
            dueTasks: SharedDefaults.dueTasks,
            overdueTasks: SharedDefaults.overdueTasks,
            streak: SharedDefaults.streak,
            level: SharedDefaults.level,
            levelTitle: SharedDefaults.levelTitle,
            xpProgress: SharedDefaults.xpProgress,
            totalXP: SharedDefaults.totalXP,
            todayCompleted: SharedDefaults.todayCompleted,
            nextTask: SharedDefaults.nextTask
        )
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: TaskEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(entry.streak > 0 ? .orange : .gray)
                Text("\(entry.streak)d")
                    .font(.caption.bold())
                Spacer()
                Text("Lv \(entry.level)")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
            }

            Text("\(entry.dueTasks)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("tasks due")
                .font(.caption)
                .foregroundStyle(.secondary)

            if entry.overdueTasks > 0 {
                Text("\(entry.overdueTasks) overdue")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: TaskEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(entry.streak > 0 ? .orange : .gray)
                    Text("\(entry.streak)d streak")
                        .font(.caption.bold())
                }

                Text("\(entry.dueTasks) due")
                    .font(.title.bold())

                if let next = entry.nextTask {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                        Text(next)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.purple.opacity(0.2), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: entry.xpProgress)
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(entry.level)")
                        .font(.title2.bold())
                        .foregroundStyle(.purple)
                }
                .frame(width: 50, height: 50)

                Text("\(entry.totalXP) XP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

struct ADultingHDWidget: Widget {
    let kind = "ADultingHDWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskTimelineProvider()) { entry in
            if #available(iOS 17.0, macOS 14.0, *) {
                WidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("ADultingHD")
        .description("Track your due tasks, streak, and level.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TaskEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

@main
struct ADultingHDWidgetBundle: WidgetBundle {
    var body: some Widget {
        ADultingHDWidget()
    }
}
