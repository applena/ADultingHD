import SwiftUI

struct ScheduleView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var selectedDate = Date()
    @State private var showPowerHour = false
    @State private var expandedCategories: Set<TaskCategory> = []

    private var calendar: Calendar { Calendar.current }

    private var weekDates: [Date] {
        let start = calendar.startOfDay(for: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Bucket each active task by day across `dates`. Today gets
    /// carry-forward semantics (`isDue(on:)` — anything due or overdue as of
    /// today lands there, matching the app's main due list) so a missed
    /// task actually shows up as today's problem instead of vanishing.
    /// Future days show only each task's exact next occurrence — a forecast
    /// view isn't the place to repeat an already-overdue backlog item across
    /// every remaining day of the week.
    private func tasksByDate(for dates: [Date]) -> [Date: [HouseholdTask]] {
        var map: [Date: [HouseholdTask]] = Dictionary(uniqueKeysWithValues: dates.map { ($0, []) })
        let today = calendar.startOfDay(for: Date())
        for task in dataStore.activeTasks {
            guard let occurrence = task.nextOccurrence(calendar: calendar) else { continue }
            for date in dates {
                let isToday = calendar.isDate(date, inSameDayAs: today)
                let matches = isToday
                    ? Recurrence.isDue(occurrence: occurrence, on: date, calendar: calendar)
                    : calendar.isDate(occurrence, inSameDayAs: date)
                if matches { map[date, default: []].append(task) }
            }
        }
        return map
    }

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let dates = weekDates
        let allDates = dates.contains(today) ? dates : ([today] + dates)
        let tasksByDate = tasksByDate(for: allDates)
        let todayTasks = tasksByDate[today] ?? []
        let todayByCategory = Dictionary(grouping: todayTasks, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
        let dueCount = dataStore.dueTasks.count

        return ZStack {
            ScreenBackground()
            ScrollView {
                #if os(macOS)
                macOSLayout(dates: dates, tasksByDate: tasksByDate, todayTasks: todayTasks, todayByCategory: todayByCategory, dueCount: dueCount)
                #else
                iOSLayout(dates: dates, tasksByDate: tasksByDate, todayTasks: todayTasks, todayByCategory: todayByCategory, dueCount: dueCount)
                #endif
            }
            .rootTabScrollClearance()
        }
        .rootTabNavigation("Schedule")
        .sheet(isPresented: $showPowerHour) {
            PowerHourView(tasks: todayTasks)
        }
    }

    private var dueSummaryChip: some View {
        let overdueCount = dataStore.overdueTasks.count
        return HStack(spacing: 12) {
            Label("\(dataStore.dueTasks.count) due", systemImage: "clock.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.streakOrange)
            if overdueCount > 0 {
                Label("\(overdueCount) overdue", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.overdueRed)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func iOSLayout(
        dates: [Date],
        tasksByDate: [Date: [HouseholdTask]],
        todayTasks: [HouseholdTask],
        todayByCategory: [(TaskCategory, [HouseholdTask])],
        dueCount: Int
    ) -> some View {
        VStack(spacing: Theme.sectionSpacing) {
            scheduleHeader(todayTasks: todayTasks, todayByCategory: todayByCategory, dueCount: dueCount)

            DatePicker("Week starting", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .card()

            if dueCount > 0 {
                dueSummaryChip
            }

            if !todayByCategory.isEmpty {
                todayBatchesCard(todayTasks: todayTasks, todayByCategory: todayByCategory)
            }

            ForEach(dates, id: \.self) { date in
                let tasks = tasksByDate[date] ?? []
                if !tasks.isEmpty { weekDayCard(date: date, tasks: tasks) }
            }
        }
        .padding()
    }

    #if os(macOS)
    private func macOSLayout(
        dates: [Date],
        tasksByDate: [Date: [HouseholdTask]],
        todayTasks: [HouseholdTask],
        todayByCategory: [(TaskCategory, [HouseholdTask])],
        dueCount: Int
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.sectionSpacing) {
            // Left: calendar picker (label hidden — it pushes the calendar off-center)
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .card()
                .frame(width: 260)

            // Right: summary + batches + week view
            VStack(spacing: Theme.sectionSpacing) {
                scheduleHeader(todayTasks: todayTasks, todayByCategory: todayByCategory, dueCount: dueCount)

                if dueCount > 0 {
                    dueSummaryChip
                }

                if !todayByCategory.isEmpty {
                    todayBatchesCard(todayTasks: todayTasks, todayByCategory: todayByCategory)
                }

                ForEach(dates, id: \.self) { date in
                    let tasks = tasksByDate[date] ?? []
                    if !tasks.isEmpty { weekDayCard(date: date, tasks: tasks) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }
    #endif

    private func scheduleHeader(
        todayTasks: [HouseholdTask],
        todayByCategory: [(TaskCategory, [HouseholdTask])],
        dueCount: Int
    ) -> some View {
        LandingHeader(
            eyebrow: "Schedule",
            title: dueCount == 0 ? "Nothing is pressing today" : "Plan today's cleaning run",
            subtitle: todayTasks.isEmpty
                ? "Pick a date to see upcoming maintenance and recurring work."
                : "\(todayTasks.count) tasks across \(todayByCategory.count) rooms, about \(todayTasks.totalMinutes) minutes total.",
            icon: "calendar.badge.clock",
            color: dueCount == 0 ? Theme.successGreen : Theme.streakOrange
        )
        .accessibilityIdentifier("schedule-root-header")
    }

    private func todayBatchesCard(
        todayTasks: [HouseholdTask],
        todayByCategory: [(TaskCategory, [HouseholdTask])]
    ) -> some View {
        let completedCount = dataStore.todayCompletions.count
        let totalCount = todayTasks.count + completedCount
        let progress = totalCount == 0 ? 0.0 : min(Double(completedCount) / Double(totalCount), 1.0)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Theme.successGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Tasks")
                        .font(.headline)
                    Text("\(todayTasks.count) tasks across \(todayByCategory.count) rooms — about \(todayTasks.totalMinutes / 60)h \(todayTasks.totalMinutes % 60)m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if todayTasks.count >= 2 {
                Button {
                    showPowerHour = true
                } label: {
                    Label("Start Power Hour", systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.streakOrange, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            // Collapsible category batches
            ForEach(todayByCategory, id: \.0) { category, tasks in
                batchSection(category: category, tasks: tasks)
            }
        }
        .card()
    }

    private func batchSection(category: TaskCategory, tasks: [HouseholdTask]) -> some View {
        let isExpanded = expandedCategories.contains(category)
        let catColor = Theme.categoryColor(category)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: category.icon)
                        .foregroundStyle(catColor)

                    Text(category.rawValue)
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Text("\(tasks.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text("\(tasks.totalMinutes)m")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text("+\(tasks.totalXP) XP")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.xpGold)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded task list
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(tasks) { task in
                        HStack(spacing: 10) {
                            Button {
                                Task { await dataStore.completeTask(task) }
                            } label: {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                            }
                            .buttonStyle(.plain)

                            Text(task.name)
                                .font(.subheadline)

                            Spacer()

                            Text("\(task.estimatedMinutes)m")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.leading, 22)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.leading, 4)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(catColor.opacity(0.6))
                .frame(width: 3)
        }
    }

    private func weekDayCard(date: Date, tasks: [HouseholdTask]) -> some View {
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
                let status = task.dueStatus()
                HStack(spacing: 8) {
                    Image(systemName: task.category.icon)
                        .foregroundStyle(Theme.categoryColor(task.category))
                        .frame(width: 20)
                    Text(task.name)
                        .font(.subheadline)
                    Spacer()
                    if status.isOverdue {
                        Text("\(status.daysOverdue)d overdue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.overdueRed)
                    } else {
                        Text("\(task.estimatedMinutes)m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            GeometryReader { geo in
                ScrollView {
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
                            Spacer(minLength: 8)

                            Image(systemName: task.category.icon)
                                .font(.system(size: 50))
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                .foregroundStyle(Theme.categoryColor(task.category))

                            Text(task.name)
                                .font(.title.bold())
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(task.description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("~\(task.estimatedMinutes) min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 8)

                            Button {
                                Task {
                                    await dataStore.completeTask(task)
                                    advanceOrFinish()
                                }
                            } label: {
                                Label(currentIndex < tasks.count - 1 ? "Done — Next" : "Done — Finish!", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Theme.successGreen, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            Button("Skip") { advanceOrFinish() }
                            .foregroundStyle(.secondary)
                        } else {
                            Spacer(minLength: 8)
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 60))
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                .foregroundStyle(Theme.xpGold)
                            Text("All done!")
                                .font(.title.bold())
                            Spacer(minLength: 8)
                        }
                    }
                    .padding()
                    .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
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
            Task { @MainActor in
                elapsedSeconds += 1
            }
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
