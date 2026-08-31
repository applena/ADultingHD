import Foundation

/// Presentation-only spaces used while setting up a home.
///
/// A location is never a parent object for tasks and is not persisted as a
/// household hierarchy. It only gives onboarding a friendly way to scope
/// catalog suggestions and search results; saved work remains a flat list of
/// `HouseholdTask` values with an optional `room` string.
enum HomeLocation: String, CaseIterable, Hashable, Identifiable {
    case entryway = "Entryway"
    case livingRoom = "Living room"
    case kitchen = "Kitchen"
    case bathroom = "Bathroom"
    case bedroom = "Bedroom"
    case laundryRoom = "Laundry room"
    case office = "Office"
    case garage = "Garage"
    case outsideArea = "Outdoor space"
    case diningRoom = "Dining room"
    case basement = "Basement"
    case playroom = "Playroom"
    case nursery = "Nursery"
    case guestRoom = "Guest room"
    case storage = "Storage"

    static let primaryCases: [HomeLocation] = [
        .bedroom, .bathroom, .kitchen, .livingRoom, .laundryRoom,
        .office, .entryway, .garage, .outsideArea,
    ]

    static let additionalCases: [HomeLocation] = [
        .diningRoom, .basement, .playroom, .nursery, .guestRoom, .storage,
    ]

    var id: String {
        rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// The room identity used by catalog templates and `HouseholdTask.room`.
    /// Display copy can say "Outside area" while the existing task vocabulary
    /// continues to use "Outdoor" for compatibility.
    var taskRoom: String {
        switch self {
        case .laundryRoom: TaskCategory.laundry.rawValue
        case .outsideArea: TaskCategory.outdoor.rawValue
        default: rawValue
        }
    }

    /// Legacy category projection used only for colors and catalog grouping.
    /// It does not make a category a parent of a task.
    var taskCategory: TaskCategory {
        TaskCategory.legacyFallback(for: taskRoom)
    }

    var icon: String {
        switch self {
        case .entryway: "door.left.hand.open"
        case .livingRoom: "sofa"
        case .kitchen: "fork.knife"
        case .bathroom: "shower"
        case .bedroom: "bed.double"
        case .laundryRoom: "washer"
        case .office: "desktopcomputer"
        case .garage: "car"
        case .outsideArea: "leaf"
        case .diningRoom: "table.furniture"
        case .basement: "stairs"
        case .playroom: "teddybear"
        case .nursery: "figure.and.child.holdinghands"
        case .guestRoom: "bed.double.fill"
        case .storage: "shippingbox"
        }
    }

    func matches(taskRoom: String?) -> Bool {
        HouseholdTask.roomIdentity(taskRoom) == HouseholdTask.roomIdentity(self.taskRoom)
    }
}
