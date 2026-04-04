import SwiftUI

enum Theme {
    // MARK: - Colors

    static let accent = Color.accentColor

    // Gamification — curated soft palette
    static let xpGold = Color(red: 0.96, green: 0.68, blue: 0.26)
    static let streakOrange = Color(red: 0.98, green: 0.52, blue: 0.33)
    static let levelPurple = Color(red: 0.47, green: 0.38, blue: 0.95)
    static let successGreen = Color(red: 0.30, green: 0.78, blue: 0.65)
    static let warningRed = Color(red: 0.93, green: 0.36, blue: 0.36)
    static let overdueRed = Color(red: 0.93, green: 0.36, blue: 0.36).opacity(0.85)

    // Fun accent colors for welcome / highlights
    static let coral = Color(red: 0.98, green: 0.45, blue: 0.45)
    static let mint = Color(red: 0.40, green: 0.85, blue: 0.72)
    static let lavender = Color(red: 0.68, green: 0.56, blue: 0.96)
    static let sky = Color(red: 0.45, green: 0.72, blue: 0.98)

    static func categoryColor(_ category: TaskCategory) -> Color {
        switch category {
        case .kitchen: Color(red: 0.96, green: 0.58, blue: 0.38)
        case .bathroom: Color(red: 0.40, green: 0.69, blue: 0.94)
        case .bedroom: Color(red: 0.68, green: 0.53, blue: 0.93)
        case .livingRoom: Color(red: 0.48, green: 0.80, blue: 0.55)
        case .laundry: Color(red: 0.38, green: 0.78, blue: 0.82)
        case .outdoor: Color(red: 0.45, green: 0.82, blue: 0.58)
        case .garage: Color(red: 0.58, green: 0.58, blue: 0.64)
        case .office: Color(red: 0.48, green: 0.42, blue: 0.85)
        case .general: Color(red: 0.72, green: 0.60, blue: 0.48)
        }
    }

    static func supplyStockColor(_ stock: SupplyStock) -> Color {
        switch stock {
        case .inStock: successGreen
        case .low: streakOrange
        case .out: warningRed
        }
    }

    static func difficultyColor(_ difficulty: Difficulty) -> Color {
        switch difficulty {
        case .easy: Color(red: 0.40, green: 0.82, blue: 0.60)
        case .medium: Color(red: 0.96, green: 0.76, blue: 0.30)
        case .hard: Color(red: 0.96, green: 0.58, blue: 0.33)
        case .epic: Color(red: 0.93, green: 0.36, blue: 0.36)
        }
    }

    // MARK: - Layout

    #if os(macOS)
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let cornerRadius: CGFloat = 12
    static let macOSContentMaxWidth: CGFloat = 780
    static let rowSpacing: CGFloat = 8
    #else
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 16
    static let cornerRadius: CGFloat = 16
    static let rowSpacing: CGFloat = 6
    #endif

    /// Grid column count: 4 on macOS wide layouts, 2 on iOS.
    static var gridColumns: Int {
        #if os(macOS)
        return 4
        #else
        return 2
        #endif
    }
}

// MARK: - Card Styling

extension View {
    /// Standard card: padding + white background + soft shadow
    func card() -> some View {
        self
            .padding(Theme.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            }
    }

    /// Card background only (no padding) — for views with custom padding
    func cardBackground() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            }
    }

    /// Constrains ScrollView content to a readable max width on macOS; no-op on iOS.
    func macOSContentFrame() -> some View {
        #if os(macOS)
        self.frame(maxWidth: Theme.macOSContentMaxWidth, alignment: .leading)
        #else
        self
        #endif
    }
}
