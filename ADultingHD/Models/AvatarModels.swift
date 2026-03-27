import Foundation

// MARK: - Avatar Item Slot

enum AvatarSlot: String, Codable, CaseIterable, Identifiable {
    case base = "Character"
    case hat = "Hat"
    case glasses = "Glasses"
    case accessory = "Accessory"
    case background = "Background"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .base: "person.fill"
        case .hat: "crown"
        case .glasses: "eyeglasses"
        case .accessory: "sparkles"
        case .background: "circle.fill"
        }
    }
}

// MARK: - Avatar Item

struct AvatarItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let slot: AvatarSlot
    let cost: Int
    let offsetX: Double
    let offsetY: Double
    let fontSize: Double
    let unlockLevel: Int

    init(id: String, name: String, emoji: String, slot: AvatarSlot, cost: Int,
         offsetX: Double = 0, offsetY: Double = 0, fontSize: Double = 24, unlockLevel: Int = 0) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.slot = slot
        self.cost = cost
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.fontSize = fontSize
        self.unlockLevel = unlockLevel
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AvatarItem, rhs: AvatarItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Avatar State

struct AvatarState: Codable {
    var ownedItemIds: Set<String> = ["cat"]
    var equippedItemIds: [AvatarSlot: String] = [.base: "cat"]

    func owns(_ itemId: String) -> Bool { ownedItemIds.contains(itemId) }

    func equipped(slot: AvatarSlot) -> String? { equippedItemIds[slot] }

    mutating func purchase(_ item: AvatarItem) {
        ownedItemIds.insert(item.id)
    }

    mutating func equip(_ item: AvatarItem) {
        equippedItemIds[item.slot] = item.id
    }

    mutating func unequip(slot: AvatarSlot) {
        if slot != .base { equippedItemIds.removeValue(forKey: slot) }
    }
}

// MARK: - Shop Catalog

let avatarShopItems: [AvatarItem] = [
    // Base characters
    AvatarItem(id: "cat", name: "Cat", emoji: "🐱", slot: .base, cost: 0, fontSize: 60),
    AvatarItem(id: "dog", name: "Dog", emoji: "🐶", slot: .base, cost: 200, fontSize: 60),
    AvatarItem(id: "bunny", name: "Bunny", emoji: "🐰", slot: .base, cost: 200, fontSize: 60),
    AvatarItem(id: "bear", name: "Bear", emoji: "🐻", slot: .base, cost: 300, fontSize: 60),
    AvatarItem(id: "fox", name: "Fox", emoji: "🦊", slot: .base, cost: 300, fontSize: 60),
    AvatarItem(id: "panda", name: "Panda", emoji: "🐼", slot: .base, cost: 400, fontSize: 60, unlockLevel: 5),
    AvatarItem(id: "unicorn", name: "Unicorn", emoji: "🦄", slot: .base, cost: 500, fontSize: 60, unlockLevel: 10),
    AvatarItem(id: "dragon", name: "Dragon", emoji: "🐲", slot: .base, cost: 1000, fontSize: 60, unlockLevel: 20),

    // Hats
    AvatarItem(id: "party_hat", name: "Party Hat", emoji: "🥳", slot: .hat, cost: 50, offsetY: -38, fontSize: 28),
    AvatarItem(id: "baseball_cap", name: "Baseball Cap", emoji: "🧢", slot: .hat, cost: 100, offsetY: -36, fontSize: 30),
    AvatarItem(id: "top_hat", name: "Top Hat", emoji: "🎩", slot: .hat, cost: 200, offsetY: -38, fontSize: 30),
    AvatarItem(id: "crown", name: "Crown", emoji: "👑", slot: .hat, cost: 500, offsetY: -36, fontSize: 28, unlockLevel: 5),
    AvatarItem(id: "grad_cap", name: "Grad Cap", emoji: "🎓", slot: .hat, cost: 300, offsetY: -38, fontSize: 30, unlockLevel: 3),
    AvatarItem(id: "cowboy", name: "Cowboy Hat", emoji: "🤠", slot: .hat, cost: 150, offsetY: -36, fontSize: 28),
    AvatarItem(id: "helmet", name: "Hard Hat", emoji: "⛑️", slot: .hat, cost: 175, offsetY: -36, fontSize: 26),
    AvatarItem(id: "wizard_hat", name: "Wizard Hat", emoji: "🧙", slot: .hat, cost: 400, offsetY: -38, fontSize: 28, unlockLevel: 8),
    AvatarItem(id: "ribbon", name: "Ribbon", emoji: "🎀", slot: .hat, cost: 75, offsetY: -32, fontSize: 22),
    AvatarItem(id: "flower_crown", name: "Flower Crown", emoji: "🌸", slot: .hat, cost: 125, offsetY: -34, fontSize: 24),

    // Glasses
    AvatarItem(id: "sunglasses", name: "Sunglasses", emoji: "🕶️", slot: .glasses, cost: 100, offsetY: -4, fontSize: 24),
    AvatarItem(id: "nerd_glasses", name: "Nerd Glasses", emoji: "🤓", slot: .glasses, cost: 75, offsetY: -4, fontSize: 24),
    AvatarItem(id: "monocle", name: "Monocle", emoji: "🧐", slot: .glasses, cost: 200, offsetX: 6, offsetY: -4, fontSize: 24),
    AvatarItem(id: "star_eyes", name: "Star Eyes", emoji: "🤩", slot: .glasses, cost: 250, offsetY: -4, fontSize: 24, unlockLevel: 3),
    AvatarItem(id: "heart_eyes", name: "Heart Eyes", emoji: "😻", slot: .glasses, cost: 150, offsetY: -4, fontSize: 24),

    // Accessories
    AvatarItem(id: "scarf", name: "Scarf", emoji: "🧣", slot: .accessory, cost: 100, offsetY: 32, fontSize: 24),
    AvatarItem(id: "medal", name: "Medal", emoji: "🏅", slot: .accessory, cost: 200, offsetY: 34, fontSize: 22),
    AvatarItem(id: "broom", name: "Cleaning Broom", emoji: "🧹", slot: .accessory, cost: 150, offsetX: 36, offsetY: 10, fontSize: 28),
    AvatarItem(id: "sparkle_wand", name: "Sparkle Wand", emoji: "✨", slot: .accessory, cost: 175, offsetX: 36, offsetY: -10, fontSize: 24),
    AvatarItem(id: "trophy", name: "Trophy", emoji: "🏆", slot: .accessory, cost: 500, offsetX: 36, offsetY: 10, fontSize: 26, unlockLevel: 10),
    AvatarItem(id: "soap_bubbles", name: "Soap Bubbles", emoji: "🫧", slot: .accessory, cost: 125, offsetX: -36, offsetY: -10, fontSize: 24),
    AvatarItem(id: "spray_bottle", name: "Spray Bottle", emoji: "🧴", slot: .accessory, cost: 100, offsetX: 36, offsetY: 12, fontSize: 24),
    AvatarItem(id: "rubber_gloves", name: "Rubber Gloves", emoji: "🧤", slot: .accessory, cost: 100, offsetX: -36, offsetY: 14, fontSize: 24),
    AvatarItem(id: "cape", name: "Cape", emoji: "🦸", slot: .accessory, cost: 400, offsetY: 28, fontSize: 24, unlockLevel: 7),

    // Backgrounds
    AvatarItem(id: "bg_rainbow", name: "Rainbow", emoji: "🌈", slot: .background, cost: 200, fontSize: 44),
    AvatarItem(id: "bg_stars", name: "Starry", emoji: "⭐", slot: .background, cost: 100, fontSize: 44),
    AvatarItem(id: "bg_hearts", name: "Hearts", emoji: "💕", slot: .background, cost: 150, fontSize: 44),
    AvatarItem(id: "bg_sparkle", name: "Sparkle", emoji: "💫", slot: .background, cost: 175, fontSize: 44),
    AvatarItem(id: "bg_fire", name: "On Fire", emoji: "🔥", slot: .background, cost: 300, fontSize: 44, unlockLevel: 5),
    AvatarItem(id: "bg_clean", name: "Squeaky Clean", emoji: "🫧", slot: .background, cost: 125, fontSize: 44),
]

private let avatarItemLookup: [String: AvatarItem] = Dictionary(
    uniqueKeysWithValues: avatarShopItems.map { ($0.id, $0) }
)

func avatarItem(byId id: String) -> AvatarItem? {
    avatarItemLookup[id]
}
