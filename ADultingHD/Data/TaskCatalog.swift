import Foundation

/// A suggested task template that users can add to their task list.
struct CatalogTask: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: TaskCategory
    let suggestedFrequency: TaskFrequency
    let estimatedMinutes: Int
    let difficulty: Difficulty
    let supplies: [String]

    func toHouseholdTask() -> HouseholdTask {
        HouseholdTask(
            id: UUID(),
            name: name,
            description: description,
            category: category,
            frequency: suggestedFrequency,
            estimatedMinutes: estimatedMinutes,
            difficulty: difficulty,
            supplies: supplies,
            isActive: true
        ).withDefaultSchedule()
    }
}

/// The small, approachable set of rooms used to shape a first-run task list.
/// Users can expand this during onboarding or from the full catalog later.
let onboardingStarterCategories: Set<TaskCategory> = [.kitchen, .bathroom, .general]

private let onboardingRecommendationNames: [TaskCategory: [String]] = [
    .kitchen: ["Wash dishes", "Wipe kitchen counters", "Scrub the kitchen sink"],
    .bathroom: ["Wipe bathroom sink and mirror", "Scrub the toilet", "Swap out bathroom towels"],
    .bedroom: ["Make the bed", "Change bed sheets", "Dust bedroom surfaces"],
    .livingRoom: ["Tidy up living room", "Vacuum living room floor", "Dust shelves and surfaces"],
    .laundry: ["Do a load of laundry", "Fold and put away clean laundry", "Wash towels and linens"],
    .general: ["Take out trash and recycling", "Wipe light switches and door handles", "Clean entry area and front door"],
]

/// Returns a deterministic, intentionally small recommendation set for the
/// onboarding picker. Empty catalog categories are omitted so a new user never
/// selects a room and lands on an empty task list.
func onboardingRecommendedCatalogTasks(for categories: Set<TaskCategory>) -> [CatalogTask] {
    TaskCategory.allCases
        .filter { categories.contains($0) }
        .flatMap { category in
            let preferredNames = onboardingRecommendationNames[category] ?? []
            let preferred = preferredNames.compactMap { preferredName in
                taskCatalog.first { $0.category == category && $0.name == preferredName }
            }
            let fallback = taskCatalog.filter {
                $0.category == category && !preferredNames.contains($0.name)
            }
            return Array((preferred + fallback).prefix(3))
        }
}

// ~50 cleaning and maintenance tasks for someone renting their first place.

let taskCatalog: [CatalogTask] = [

    // MARK: - Kitchen (10)

    CatalogTask(
        name: "Wash dishes",
        description: "Hand-wash or load the dishwasher and clear the sink.",
        category: .kitchen, suggestedFrequency: .daily, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Dish soap", "Sponge"]
    ),
    CatalogTask(
        name: "Wipe kitchen counters",
        description: "Spray and wipe all counter surfaces; put items back in place.",
        category: .kitchen, suggestedFrequency: .daily, estimatedMinutes: 5, difficulty: .easy,
        supplies: ["All-purpose cleaner", "Microfiber cloth"]
    ),
    CatalogTask(
        name: "Clean stovetop",
        description: "Wipe burners, drip pans, and surrounding area to remove grease splatter.",
        category: .kitchen, suggestedFrequency: .weekly, estimatedMinutes: 15, difficulty: .medium,
        supplies: ["Degreaser", "Scrub brush", "Paper towels"]
    ),
    CatalogTask(
        name: "Clean microwave inside and out",
        description: "Steam with vinegar water, then wipe interior walls, turntable, and door.",
        category: .kitchen, suggestedFrequency: .biweekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["White vinegar", "Microfiber cloth"]
    ),
    CatalogTask(
        name: "Clean out the fridge",
        description: "Toss expired food, wipe down shelves and drawers, restock neatly.",
        category: .kitchen, suggestedFrequency: .biweekly, estimatedMinutes: 20, difficulty: .medium,
        supplies: ["Baking soda", "Sponge", "Trash bag"]
    ),
    CatalogTask(
        name: "Scrub the kitchen sink",
        description: "Scrub basin with baking soda, polish the faucet, clean the drain screen.",
        category: .kitchen, suggestedFrequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Baking soda", "Dish soap", "Sponge"]
    ),
    CatalogTask(
        name: "Sweep and mop kitchen floor",
        description: "Sweep up crumbs then mop the whole kitchen floor.",
        category: .kitchen, suggestedFrequency: .weekly, estimatedMinutes: 15, difficulty: .medium,
        supplies: ["Broom", "Mop", "Floor cleaner"]
    ),
    CatalogTask(
        name: "Empty and clean trash can",
        description: "Take out the kitchen trash bag and wipe down the inside of the bin.",
        category: .kitchen, suggestedFrequency: .weekly, estimatedMinutes: 5, difficulty: .easy,
        supplies: ["Trash bags", "Disinfecting spray"]
    ),
    CatalogTask(
        name: "Clean oven",
        description: "Deep-clean oven interior, racks, and door glass — important for deposit.",
        category: .kitchen, suggestedFrequency: .quarterly, estimatedMinutes: 45, difficulty: .hard,
        supplies: ["Oven cleaner", "Rubber gloves", "Scrub pad"]
    ),
    CatalogTask(
        name: "Wipe cabinet fronts and handles",
        description: "Remove grease and fingerprints from cabinet doors and drawer pulls.",
        category: .kitchen, suggestedFrequency: .monthly, estimatedMinutes: 15, difficulty: .easy,
        supplies: ["All-purpose cleaner", "Microfiber cloth"]
    ),

    // MARK: - Bathroom (8)

    CatalogTask(
        name: "Wipe bathroom sink and mirror",
        description: "Spray and wipe the sink, faucet, counter, and mirror.",
        category: .bathroom, suggestedFrequency: .twiceWeekly, estimatedMinutes: 5, difficulty: .easy,
        supplies: ["Glass cleaner", "Bathroom cleaner", "Paper towels"]
    ),
    CatalogTask(
        name: "Scrub the toilet",
        description: "Clean bowl with brush, wipe seat, lid, base, and handle.",
        category: .bathroom, suggestedFrequency: .weekly, estimatedMinutes: 10, difficulty: .medium,
        supplies: ["Toilet cleaner", "Toilet brush", "Rubber gloves"]
    ),
    CatalogTask(
        name: "Clean shower and tub",
        description: "Scrub walls, tub floor, fixtures, and glass door or curtain.",
        category: .bathroom, suggestedFrequency: .weekly, estimatedMinutes: 20, difficulty: .medium,
        supplies: ["Shower cleaner", "Scrub brush", "Squeegee"]
    ),
    CatalogTask(
        name: "Wash shower curtain liner",
        description: "Toss the liner in the wash or replace it to prevent mildew.",
        category: .bathroom, suggestedFrequency: .monthly, estimatedMinutes: 5, difficulty: .easy,
        supplies: ["Laundry detergent"]
    ),
    CatalogTask(
        name: "Sweep and mop bathroom floor",
        description: "Sweep hair and dust, then mop the bathroom floor.",
        category: .bathroom, suggestedFrequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Broom", "Mop", "Floor cleaner"]
    ),
    CatalogTask(
        name: "Swap out bathroom towels",
        description: "Replace used towels and hand towels with fresh ones.",
        category: .bathroom, suggestedFrequency: .twiceWeekly, estimatedMinutes: 3, difficulty: .easy,
        supplies: []
    ),
    CatalogTask(
        name: "Scrub bathroom grout and tile",
        description: "Deep-clean grout lines in shower and floor tile to prevent mold.",
        category: .bathroom, suggestedFrequency: .monthly, estimatedMinutes: 30, difficulty: .hard,
        supplies: ["Grout cleaner", "Stiff brush", "Rubber gloves"]
    ),
    CatalogTask(
        name: "Clean exhaust fan cover",
        description: "Remove the vent cover, rinse off dust, and let dry before replacing.",
        category: .bathroom, suggestedFrequency: .quarterly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Dish soap"]
    ),

    // MARK: - Bedroom (6)

    CatalogTask(
        name: "Make the bed",
        description: "Straighten sheets, fluff pillows, and pull up the comforter.",
        category: .bedroom, suggestedFrequency: .daily, estimatedMinutes: 3, difficulty: .easy,
        supplies: []
    ),
    CatalogTask(
        name: "Change bed sheets",
        description: "Strip sheets and pillowcases, put on a fresh set.",
        category: .bedroom, suggestedFrequency: .weekly, estimatedMinutes: 15, difficulty: .easy,
        supplies: ["Fresh sheets", "Pillowcases"]
    ),
    CatalogTask(
        name: "Dust bedroom surfaces",
        description: "Dust nightstands, dresser tops, shelves, and windowsills.",
        category: .bedroom, suggestedFrequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Dusting cloth"]
    ),
    CatalogTask(
        name: "Vacuum or sweep bedroom floor",
        description: "Vacuum carpet (or sweep hard floor), under the bed, and along baseboards.",
        category: .bedroom, suggestedFrequency: .weekly, estimatedMinutes: 15, difficulty: .easy,
        supplies: ["Vacuum cleaner"]
    ),
    CatalogTask(
        name: "Organize closet",
        description: "Return stray clothes to hangers, sort shoes, declutter the shelf.",
        category: .bedroom, suggestedFrequency: .monthly, estimatedMinutes: 20, difficulty: .medium,
        supplies: []
    ),
    CatalogTask(
        name: "Flip or rotate mattress",
        description: "Rotate 180 degrees (or flip if double-sided) for even wear.",
        category: .bedroom, suggestedFrequency: .quarterly, estimatedMinutes: 10, difficulty: .medium,
        supplies: []
    ),

    // MARK: - Living Room (7)

    CatalogTask(
        name: "Tidy up living room",
        description: "Put remotes, blankets, and items back in place; straighten cushions.",
        category: .livingRoom, suggestedFrequency: .daily, estimatedMinutes: 5, difficulty: .easy,
        supplies: []
    ),
    CatalogTask(
        name: "Dust shelves and surfaces",
        description: "Dust TV stand, bookshelves, coffee table, and lamp bases.",
        category: .livingRoom, suggestedFrequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Dusting cloth"]
    ),
    CatalogTask(
        name: "Vacuum living room floor",
        description: "Vacuum carpet or rugs, along baseboards, and under furniture edges.",
        category: .livingRoom, suggestedFrequency: .weekly, estimatedMinutes: 15, difficulty: .easy,
        supplies: ["Vacuum cleaner"]
    ),
    CatalogTask(
        name: "Wipe TV and electronics",
        description: "Gently clean TV screen, game consoles, and remotes.",
        category: .livingRoom, suggestedFrequency: .biweekly, estimatedMinutes: 5, difficulty: .easy,
        supplies: ["Screen cleaner", "Microfiber cloth"]
    ),
    CatalogTask(
        name: "Vacuum couch and cushions",
        description: "Pull off cushions, vacuum crumbs and pet hair, replace cushions.",
        category: .livingRoom, suggestedFrequency: .biweekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Vacuum cleaner"]
    ),
    CatalogTask(
        name: "Clean interior windows",
        description: "Spray and wipe all window glass from inside; wipe sills and tracks.",
        category: .livingRoom, suggestedFrequency: .monthly, estimatedMinutes: 20, difficulty: .medium,
        supplies: ["Glass cleaner", "Microfiber cloth"]
    ),
    CatalogTask(
        name: "Wipe baseboards",
        description: "Wipe dust and scuffs off baseboards around the room.",
        category: .livingRoom, suggestedFrequency: .monthly, estimatedMinutes: 15, difficulty: .easy,
        supplies: ["Damp cloth"]
    ),

    // MARK: - Laundry (5)

    CatalogTask(
        name: "Do a load of laundry",
        description: "Sort, wash, dry, and put away one load of clothes.",
        category: .laundry, suggestedFrequency: .twiceWeekly, estimatedMinutes: 15, difficulty: .easy,
        supplies: ["Laundry detergent"]
    ),
    CatalogTask(
        name: "Wash towels and linens",
        description: "Gather all used bath and kitchen towels and run a hot wash.",
        category: .laundry, suggestedFrequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Laundry detergent"]
    ),
    CatalogTask(
        name: "Fold and put away clean laundry",
        description: "Fold the clean pile and return everything to drawers and closets.",
        category: .laundry, suggestedFrequency: .twiceWeekly, estimatedMinutes: 15, difficulty: .easy,
        supplies: []
    ),
    CatalogTask(
        name: "Clean washing machine",
        description: "Run an empty hot cycle with cleaner; wipe the door seal and tray.",
        category: .laundry, suggestedFrequency: .monthly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Washing machine cleaner", "Microfiber cloth"]
    ),
    CatalogTask(
        name: "Clean lint trap and dryer",
        description: "Remove lint from the trap, wipe the drum, check the vent hose.",
        category: .laundry, suggestedFrequency: .monthly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Lint brush"]
    ),

    // MARK: - General (14)

    CatalogTask(
        name: "Take out trash and recycling",
        description: "Empty all bins, replace bags, and bring trash and recycling out.",
        category: .general, suggestedFrequency: .twiceWeekly, estimatedMinutes: 8, difficulty: .easy,
        supplies: ["Trash bags"]
    ),
    CatalogTask(
        name: "Vacuum the whole apartment",
        description: "Vacuum every room, hallways, and along all baseboards.",
        category: .general, suggestedFrequency: .weekly, estimatedMinutes: 25, difficulty: .medium,
        supplies: ["Vacuum cleaner"]
    ),
    CatalogTask(
        name: "Mop all hard floors",
        description: "Mop kitchen, bathroom, and any other hard-surface floors.",
        category: .general, suggestedFrequency: .weekly, estimatedMinutes: 20, difficulty: .medium,
        supplies: ["Mop", "Floor cleaner"]
    ),
    CatalogTask(
        name: "Dust ceiling fans and light fixtures",
        description: "Use an extendable duster to clean fan blades and fixture covers.",
        category: .general, suggestedFrequency: .monthly, estimatedMinutes: 15, difficulty: .medium,
        supplies: ["Extendable duster"]
    ),
    CatalogTask(
        name: "Wipe light switches and door handles",
        description: "Disinfect every switch plate and door knob in the apartment.",
        category: .general, suggestedFrequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Disinfecting wipes"]
    ),
    CatalogTask(
        name: "Clean entry area and front door",
        description: "Sweep the entryway, shake out the doormat, wipe the door.",
        category: .general, suggestedFrequency: .weekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Broom", "All-purpose cleaner"]
    ),
    CatalogTask(
        name: "Clean mirrors throughout",
        description: "Spray and buff every mirror in the apartment.",
        category: .general, suggestedFrequency: .biweekly, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["Glass cleaner", "Microfiber cloth"]
    ),
    CatalogTask(
        name: "Wipe all door frames and trim",
        description: "Damp-wipe the tops of door frames and any crown molding to remove dust.",
        category: .general, suggestedFrequency: .monthly, estimatedMinutes: 15, difficulty: .easy,
        supplies: ["Damp cloth"]
    ),
    CatalogTask(
        name: "Clean air vents and registers",
        description: "Remove vent covers, wash in soapy water, vacuum the duct opening.",
        category: .general, suggestedFrequency: .quarterly, estimatedMinutes: 20, difficulty: .medium,
        supplies: ["Dish soap", "Vacuum cleaner"]
    ),
    CatalogTask(
        name: "Check and replace smoke detector batteries",
        description: "Press the test button on each detector; swap batteries if needed.",
        category: .general, suggestedFrequency: .semiannually, estimatedMinutes: 10, difficulty: .easy,
        supplies: ["9V batteries"]
    ),
    CatalogTask(
        name: "Deep clean the whole apartment",
        description: "Full top-to-bottom clean of every room — great before guests or move-out.",
        category: .general, suggestedFrequency: .monthly, estimatedMinutes: 120, difficulty: .epic,
        supplies: ["All-purpose cleaner", "Vacuum", "Mop", "Microfiber cloths", "Rubber gloves"]
    ),
    CatalogTask(
        name: "Declutter and donate",
        description: "Go through one area, bag up items to donate or toss, and clear the space.",
        category: .general, suggestedFrequency: .monthly, estimatedMinutes: 30, difficulty: .medium,
        supplies: ["Trash bags", "Donation bag"]
    ),
    CatalogTask(
        name: "Clean inside cabinets and drawers",
        description: "Empty one cabinet or drawer, wipe inside, and reorganize contents.",
        category: .general, suggestedFrequency: .quarterly, estimatedMinutes: 20, difficulty: .medium,
        supplies: ["All-purpose cleaner", "Shelf liner"]
    ),
    CatalogTask(
        name: "Spot-clean walls and scuff marks",
        description: "Magic-eraser scuffs, wipe fingerprints near switches — protects your deposit.",
        category: .general, suggestedFrequency: .monthly, estimatedMinutes: 15, difficulty: .easy,
        supplies: ["Magic eraser", "Damp cloth"]
    ),
]
