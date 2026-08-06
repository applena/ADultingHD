import Foundation

private func starterTask(
    name: String,
    description: String,
    category: TaskCategory,
    frequency: TaskFrequency,
    estimatedMinutes: Int,
    difficulty: Difficulty,
    supplies: [String],
    isActive: Bool = true
) -> HouseholdTask {
    HouseholdTask(
        id: UUID(),
        name: name,
        description: description,
        category: category,
        frequency: frequency,
        estimatedMinutes: estimatedMinutes,
        difficulty: difficulty,
        supplies: supplies,
        isActive: isActive
    )
}

let defaultHouseholdTasks: [HouseholdTask] = [
    starterTask(
        name: "Do dishes",
        description: "Wash dishes and clear the sink so tomorrow starts clean.",
        category: .kitchen,
        frequency: .daily,
        estimatedMinutes: 10,
        difficulty: .easy,
        supplies: ["Dish soap", "Sponge"]
    ),
    starterTask(
        name: "Wipe the counters",
        description: "Quick kitchen reset: wipe counters and put items back in place.",
        category: .kitchen,
        frequency: .daily,
        estimatedMinutes: 5,
        difficulty: .easy,
        supplies: ["All-purpose cleaner", "Microfiber cloth"]
    ),
    starterTask(
        name: "Take out trash",
        description: "Empty kitchen and bathroom bins.",
        category: .general,
        frequency: .twiceWeekly,
        estimatedMinutes: 8,
        difficulty: .easy,
        supplies: ["Trash bags"]
    ),
    starterTask(
        name: "Quick bathroom wipe-down",
        description: "Wipe sink and mirror to keep things fresh.",
        category: .bathroom,
        frequency: .weekly,
        estimatedMinutes: 10,
        difficulty: .easy,
        supplies: ["Bathroom cleaner", "Paper towels"]
    ),
]
