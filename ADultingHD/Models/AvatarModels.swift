import Foundation

// MARK: - Avatar Tier

enum AvatarTier {
    case animal
    case hero
}

// MARK: - Avatar Slot

enum AvatarSlot: String, Codable, Identifiable {
    case character = "Character"
    // Legacy slots retained for Codable compatibility with existing saved data
    case hat = "Hat"
    case glasses = "Glasses"
    case accessory = "Accessory"
    case background = "Background"

    var id: String { rawValue }
}

// MARK: - Avatar Item

struct AvatarItem: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let cost: Int
    let fontSize: Double
    let unlockLevel: Int
    let imageName: String?

    init(id: String, name: String, emoji: String, cost: Int,
         fontSize: Double = 60, unlockLevel: Int = 0, imageName: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.cost = cost
        self.fontSize = fontSize
        self.unlockLevel = unlockLevel
        self.imageName = imageName
    }

    /// Species family inferred from id prefix: "cat_chef" -> "cat", "cat" -> "cat"
    var family: String { id.components(separatedBy: "_").first ?? id }

    /// Hero avatars have an underscore in their id (e.g. "cat_chef"); others are base animals
    var tier: AvatarTier { id.contains("_") ? .hero : .animal }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AvatarItem, rhs: AvatarItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Avatar State

struct AvatarState: Codable {
    var ownedItemIds: Set<String> = ["person"]
    var equippedItemIds: [AvatarSlot: String] = [.character: "person"]

    func owns(_ itemId: String) -> Bool { ownedItemIds.contains(itemId) }

    func equipped(slot: AvatarSlot) -> String? { equippedItemIds[slot] }

    mutating func purchase(_ item: AvatarItem) {
        ownedItemIds.insert(item.id)
    }

    mutating func equip(_ item: AvatarItem) {
        equippedItemIds[.character] = item.id
    }

    mutating func unequip(slot: AvatarSlot) {
        if slot != .character { equippedItemIds.removeValue(forKey: slot) }
    }
}

// MARK: - Shop Catalog

/// Family display order, derived from `avatarShopItems` declaration order so a
/// newly added avatar can't silently miss its filter chip or sort to the end.
let avatarFamilies: [String] = avatarShopItems.reduce(into: [String]()) { families, item in
    if !families.contains(item.family) { families.append(item.family) }
}

let avatarShopItems: [AvatarItem] = [
    // Default starter
    AvatarItem(id: "person",  name: "Person",  emoji: "🧑", cost: 0),

    // Free onboarding companions
    AvatarItem(id: "raccoon", name: "Raccoon", emoji: "🦝", cost: 0, imageName: "raccoon"),
    AvatarItem(id: "turtle", name: "Turtle", emoji: "🐢", cost: 0, imageName: "turtle"),
    AvatarItem(id: "otter", name: "Otter", emoji: "🦦", cost: 0, imageName: "otter"),
    AvatarItem(id: "capybara", name: "Capybara", emoji: "🦫", cost: 0, imageName: "capybara"),

    // Base animals
    AvatarItem(id: "cat",     name: "Cat",     emoji: "🐱", cost: 200,  imageName: "cat"),
    AvatarItem(id: "dog",     name: "Dog",     emoji: "🐶", cost: 200,  imageName: "dog"),
    AvatarItem(id: "bunny",   name: "Bunny",   emoji: "🐰", cost: 200,  imageName: "bunny"),
    AvatarItem(id: "bear",    name: "Bear",    emoji: "🐻", cost: 300,  imageName: "bear"),
    AvatarItem(id: "fox",     name: "Fox",     emoji: "🦊", cost: 300,  imageName: "fox"),
    AvatarItem(id: "panda",   name: "Panda",   emoji: "🐼", cost: 400,  unlockLevel: 5,  imageName: "panda"),
    AvatarItem(id: "unicorn", name: "Unicorn", emoji: "🦄", cost: 500,  unlockLevel: 10, imageName: "unicorn"),
    AvatarItem(id: "dragon",  name: "Dragon",  emoji: "🐲", cost: 1000, unlockLevel: 20, imageName: "dragon"),

    // Hero classes
    AvatarItem(id: "cat_chef",        name: "Chef Cat",         emoji: "🐱", cost: 600,  unlockLevel: 5,  imageName: "cat_chef"),
    AvatarItem(id: "cat_ninja",       name: "Ninja Cat",        emoji: "🐱", cost: 800,  unlockLevel: 8,  imageName: "cat_ninja"),
    AvatarItem(id: "dog_firefighter", name: "Firefighter Dog",  emoji: "🐶", cost: 800,  unlockLevel: 8,  imageName: "dog_firefighter"),
    AvatarItem(id: "dog_astronaut",   name: "Astronaut Dog",    emoji: "🐶", cost: 1000, unlockLevel: 12, imageName: "dog_astronaut"),
    AvatarItem(id: "bunny_gardener",  name: "Gardener Bunny",   emoji: "🐰", cost: 700,  unlockLevel: 6,  imageName: "bunny_gardener"),
    AvatarItem(id: "bunny_wizard",    name: "Wizard Bunny",     emoji: "🐰", cost: 900,  unlockLevel: 10, imageName: "bunny_wizard"),
    AvatarItem(id: "bear_lumberjack", name: "Lumberjack Bear",  emoji: "🐻", cost: 800,  unlockLevel: 8,  imageName: "bear_lumberjack"),
    AvatarItem(id: "bear_knight",     name: "Knight Bear",      emoji: "🐻", cost: 1000, unlockLevel: 12, imageName: "bear_knight"),
    AvatarItem(id: "fox_detective",   name: "Detective Fox",    emoji: "🦊", cost: 900,  unlockLevel: 10, imageName: "fox_detective"),
    AvatarItem(id: "fox_pirate",      name: "Pirate Fox",       emoji: "🦊", cost: 1000, unlockLevel: 12, imageName: "fox_pirate"),
    AvatarItem(id: "panda_sensei",    name: "Sensei Panda",     emoji: "🐼", cost: 1500, unlockLevel: 15, imageName: "panda_sensei"),
    AvatarItem(id: "panda_emperor",   name: "Emperor Panda",    emoji: "🐼", cost: 2000, unlockLevel: 20, imageName: "panda_emperor"),
    AvatarItem(id: "unicorn_fairy",   name: "Fairy Unicorn",    emoji: "🦄", cost: 2000, unlockLevel: 18, imageName: "unicorn_fairy"),
    AvatarItem(id: "unicorn_rockstar",name: "Rockstar Unicorn", emoji: "🦄", cost: 2500, unlockLevel: 22, imageName: "unicorn_rockstar"),
    AvatarItem(id: "dragon_king",     name: "Dragon King",      emoji: "🐲", cost: 3000, unlockLevel: 25, imageName: "dragon_king"),
    AvatarItem(id: "dragon_mecha",    name: "Mecha Dragon",     emoji: "🐲", cost: 5000, unlockLevel: 30, imageName: "dragon_mecha"),
]

private let avatarItemLookup: [String: AvatarItem] = Dictionary(
    uniqueKeysWithValues: avatarShopItems.map { ($0.id, $0) }
)

func avatarItem(byId id: String) -> AvatarItem? {
    avatarItemLookup[id]
}
