import SwiftUI

struct ScheduleView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var selectedDate = Date()
    @State private var showPowerHour = false

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

    private var todayTasks: [HouseholdTask] {
        tasksForDate(calendar.startOfDay(for: Date()))
    }

    private var todayByCategory: [(TaskCategory, [HouseholdTask])] {
        Dictionary(grouping: todayTasks, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                // Date Picker
                DatePicker("Week starting", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .card()

                // Summary stats
                let due = dataStore.dueTasks.count
                if due > 0 {
                    HStack(spacing: 12) {
                        Label("\(due) due", systemImage: "clock.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.streakOrange)
                    }
                    .frame(maxWidth: .infinity)
                    .card()
                }

                // Smart Batching — today's tasks grouped by category
                if !todayByCategory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Today's Batches", systemImage: "tray.2.fill")
                                .font(.headline)
                            Spacer()
                            let totalMin = todayTasks.totalMinutes
                            Text("\(totalMin) min total")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }

                        ForEach(todayByCategory, id: \.0) { category, tasks in
                            let batchMinutes = tasks.totalMinutes
                            let batchXP = tasks.totalXP
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: category.icon)
                                        .foregroundStyle(Theme.categoryColor(category))
                                    Text("\(category.rawValue) block")
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("\(tasks.count) tasks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(batchMinutes)m")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Text("+\(batchXP) XP")
                                        .font(.caption.bold())
                                        .foregroundStyle(Theme.xpGold)
                                }
                                ForEach(tasks) { task in
                                    HStack(spacing: 6) {
                                        Text("  \(task.name)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(task.estimatedMinutes)m")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            if category != todayByCategory.last?.0 {
                                Divider()
                            }
                        }

                        if todayTasks.count >= 2 {
                            Button {
                                showPowerHour = true
                            } label: {
                                Label("Power Hour", systemImage: "bolt.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Theme.streakOrange, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card()
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
                                }
                            }

                            let totalMinutes = tasks.totalMinutes
                            let totalXP = tasks.totalXP
                            HStack {
                                Text("Total: \(totalMinutes) min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("+\(totalXP) XP")
                                    .font(.caption.bold())
                                    .foregroundStyle(Theme.xpGold)
                            }
                        }
                        .padding(Theme.cardPadding)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Schedule")
        .sheet(isPresented: $showPowerHour) {
            PowerHourView(tasks: todayTasks)
        }
    }
}

// MARK: - Power Hour

struct PowerHourView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    let tasks: [HouseholdTask]
    @State private var currentIndex = 0
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?

    private var currentTask: HouseholdTask? {
        currentIndex < tasks.count ? tasks[currentIndex] : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Progress
                HStack {
                    Text("Task \(min(currentIndex + 1, tasks.count)) of \(tasks.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(elapsedSeconds))
                        .font(.system(.title3, design: .monospaced).bold())
                        .foregroundStyle(Theme.streakOrange)
                }

                ProgressView(value: Double(currentIndex), total: Double(tasks.count))
                    .tint(Theme.successGreen)

                if let task = currentTask {
                    Spacer()

                    Image(systemName: task.category.icon)
                        .font(.system(size: 50))
                        .foregroundStyle(Theme.categoryColor(task.category))

                    Text(task.name)
                        .font(.title.bold())

                    Text(task.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("~\(task.estimatedMinutes) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        Task {
                            await dataStore.completeTask(task)
                            advanceOrFinish()
                        }
                    } label: {
                        Label(currentIndex < tasks.count - 1 ? "Done — Next" : "Done — Finish!", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.successGreen, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button("Skip") { advanceOrFinish() }
                    .foregroundStyle(.secondary)
                } else {
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.xpGold)
                    Text("All done!")
                        .font(.title.bold())
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Power Hour")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") { dismiss() }
                }
            }
            .onAppear { startTimer() }
            .onDisappear { stopTimer() }
        }
    }

    private func advanceOrFinish() {
        if currentIndex < tasks.count - 1 {
            currentIndex += 1
        } else {
            dismiss()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
