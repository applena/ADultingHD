import Foundation

enum Season: String {
    case spring = "Spring"
    case summer = "Summer"
    case fall = "Fall"
    case winter = "Winter"

    static var current: Season {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .fall
        default: return .winter
        }
    }

    var icon: String {
        switch self {
        case .spring: "leaf.fill"
        case .summer: "sun.max.fill"
        case .fall: "wind"
        case .winter: "snowflake"
        }
    }
}

struct SeasonalSuggestion: Identifiable {
    let id = UUID()
    let season: Season
    let name: String
    let description: String
    let suggestedRoom: String?
    let estimatedMinutes: Int
    let difficulty: Difficulty

    var category: TaskCategory { TaskCategory.legacyFallback(for: suggestedRoom) }

    init(
        season: Season,
        name: String,
        description: String,
        category: TaskCategory? = nil,
        estimatedMinutes: Int,
        difficulty: Difficulty
    ) {
        self.season = season
        self.name = name
        self.description = description
        self.suggestedRoom = category?.roomValue
        self.estimatedMinutes = estimatedMinutes
        self.difficulty = difficulty
    }

    func toTask() -> HouseholdTask {
        var task = HouseholdTask(
            id: UUID(),
            name: name,
            description: description,
            category: .general,
            frequency: .yearly,
            estimatedMinutes: estimatedMinutes,
            difficulty: difficulty,
            supplies: [],
            isActive: true
        )
        task.room = suggestedRoom
        return task
    }
}

let seasonalSuggestions: [SeasonalSuggestion] = [
    // Spring
    SeasonalSuggestion(season: .spring, name: "Deep Clean Windows", description: "Wash all windows inside and out after winter", category: .livingRoom, estimatedMinutes: 60, difficulty: .hard),
    SeasonalSuggestion(season: .spring, name: "Service Air Conditioner", description: "Clean or replace AC filters, check refrigerant", category: .general, estimatedMinutes: 30, difficulty: .medium),
    SeasonalSuggestion(season: .spring, name: "Power Wash Driveway", description: "Remove winter grime from driveway and walkways", category: .outdoor, estimatedMinutes: 60, difficulty: .hard),
    SeasonalSuggestion(season: .spring, name: "Organize Garage (Spring)", description: "Post-winter garage cleanup and reorganization", category: .garage, estimatedMinutes: 120, difficulty: .epic),
    SeasonalSuggestion(season: .spring, name: "Garden Prep", description: "Prep garden beds, plan plantings, start seeds", category: .outdoor, estimatedMinutes: 90, difficulty: .medium),

    // Summer
    SeasonalSuggestion(season: .summer, name: "Clean Patio Furniture", description: "Wash and treat outdoor furniture for the season", category: .outdoor, estimatedMinutes: 45, difficulty: .medium),
    SeasonalSuggestion(season: .summer, name: "Clean Grill", description: "Deep clean barbecue grill grates and interior", category: .outdoor, estimatedMinutes: 30, difficulty: .medium),
    SeasonalSuggestion(season: .summer, name: "Check Deck/Patio for Damage", description: "Inspect and repair deck boards, stain if needed", category: .outdoor, estimatedMinutes: 60, difficulty: .hard),
    SeasonalSuggestion(season: .summer, name: "Trim Hedges & Bushes", description: "Shape and trim overgrown hedges and bushes", category: .outdoor, estimatedMinutes: 60, difficulty: .medium),

    // Fall
    SeasonalSuggestion(season: .fall, name: "Clean Gutters (Fall)", description: "Remove leaves and debris from gutters before winter", category: .outdoor, estimatedMinutes: 60, difficulty: .epic),
    SeasonalSuggestion(season: .fall, name: "Winterize Outdoor Faucets", description: "Disconnect hoses, insulate outdoor spigots", category: .outdoor, estimatedMinutes: 20, difficulty: .easy),
    SeasonalSuggestion(season: .fall, name: "Check Weather Stripping", description: "Inspect and replace worn weather stripping on doors/windows", category: .general, estimatedMinutes: 30, difficulty: .medium),
    SeasonalSuggestion(season: .fall, name: "Test Heating System", description: "Run furnace/heat pump before cold weather arrives", category: .general, estimatedMinutes: 15, difficulty: .easy),
    SeasonalSuggestion(season: .fall, name: "Rake Leaves", description: "Rake and bag fallen leaves from the yard", category: .outdoor, estimatedMinutes: 60, difficulty: .medium),

    // Winter
    SeasonalSuggestion(season: .winter, name: "Deep Clean Closets", description: "Organize winter clothing, donate unused items", category: .bedroom, estimatedMinutes: 60, difficulty: .medium),
    SeasonalSuggestion(season: .winter, name: "Clean Fireplace/Chimney", description: "Clear ash, inspect chimney, schedule cleaning if needed", category: .livingRoom, estimatedMinutes: 30, difficulty: .medium),
    SeasonalSuggestion(season: .winter, name: "Insulate Pipes", description: "Check and insulate exposed water pipes to prevent freezing", category: .general, estimatedMinutes: 30, difficulty: .medium),
    SeasonalSuggestion(season: .winter, name: "Organize Pantry (Year-End)", description: "Audit pantry, discard expired items, restock for new year", category: .kitchen, estimatedMinutes: 30, difficulty: .easy),
]

func currentSeasonSuggestions() -> [SeasonalSuggestion] {
    seasonalSuggestions.filter { $0.season == Season.current }
}
