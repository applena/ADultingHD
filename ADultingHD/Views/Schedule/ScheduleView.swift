import SwiftUI

struct ScheduleView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var selectedDate = Date()

    private var calendar: Calendar { Calendar.current }

    private var weekDates: [Date] {
        let start = calendar.startOfDay(for: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func tasksForDate(_ date: Date) -> [HouseholdTask] {
        dataStore.activeTasks.filter { task in
            guard let lastCompleted = task.lastCompleted else { return true }
            let nextDue = calendar.date(byAdding: .day, value: task.frequency.days, to: lastCompleted) ?? date
            return calendar.isDate(nextDue, inSameDayAs: date) || nextDue < date
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                // Date Picker
                DatePicker("Week starting", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(Theme.cardPadding)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))

                // Summary stats
                let overdue = dataStore.overdueTasks.count
                let due = dataStore.dueTasks.count
                if overdue > 0 || due > 0 {
                    HStack(spacing: 12) {
                        if overdue > 0 {
                            Label("\(overdue) overdue", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.warningRed)
                        }
                        if due > 0 {
                            Label("\(due) due", systemImage: "clock.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.streakOrange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.cardPadding)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }

                // Week View
                ForEach(weekDates, id: \.self) { date in
                    let tasks = tasksForDate(date)
                    if !tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(date, format: .dateTime.weekday(.wide).month().day())
                                    .font(.headline)
                                if calendar.isDateInToday(date) {
                                    Text("TODAY")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent, in: Capsule())
                                }
                                Spacer()
                                Text("\(tasks.count) tasks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(tasks) { task in
                                HStack(spacing: 8) {
                                    Image(systemName: task.category.icon)
                                        .foregroundStyle(Theme.categoryColor(task.category))
                                        .frame(width: 20)
                                    Text(task.name)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(task.estimatedMinutes)m")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if task.isOverdue {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(Theme.warningRed)
                                            .font(.caption)
                                    }
                                }
                            }

                            let totalMinutes = tasks.reduce(0) { $0 + $1.estimatedMinutes }
                            Text("Total: \(totalMinutes) minutes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(Theme.cardPadding)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Schedule")
    }
}
