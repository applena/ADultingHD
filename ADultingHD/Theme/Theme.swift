import SwiftUI

enum Theme {
    // MARK: - Colors

    static let accent = Color.accentColor

    // Cozy Domestic Adventure foundations
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.93)
    static let parchment = Color(red: 0.98, green: 0.93, blue: 0.84)
    static let adventureBlue = Color(red: 0.08, green: 0.20, blue: 0.35)
    static let hearthGold = Color(red: 0.94, green: 0.58, blue: 0.16)
    static let leafGreen = Color(red: 0.24, green: 0.43, blue: 0.29)

    // Gamification — curated soft palette
    static let xpGold = Color(red: 0.96, green: 0.68, blue: 0.26)
    static let streakOrange = Color(red: 0.98, green: 0.52, blue: 0.33)
    static let levelPurple = Color(red: 0.47, green: 0.38, blue: 0.95)
    static let successGreen = Color(red: 0.30, green: 0.78, blue: 0.65)
    static let warningRed = Color(red: 0.93, green: 0.36, blue: 0.36)
    static let overdueRed = warningRed.opacity(0.85)

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
    static let cornerRadius: CGFloat = 8
    static let macOSContentMaxWidth: CGFloat = 780
    static let rowSpacing: CGFloat = 8
    #else
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 16
    static let cornerRadius: CGFloat = 8
    static let rowSpacing: CGFloat = 6
    static let rootTabBottomClearance: CGFloat = 72

    static let rootNavigationSurface = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        }
        return UIColor(red: 1.00, green: 0.97, blue: 0.93, alpha: 1)
    })
    #endif

    static let onboardingContentMaxWidth: CGFloat = 760
    static let onboardingArtworkCornerRadius: CGFloat = 20

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
    /// Standard surface: padding + adaptive background + fine border.
    func card() -> some View {
        self
            .padding(Theme.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Color.secondary.opacity(0.10))
            }
    }

    /// Card background only (no padding) - for views with custom padding.
    func cardBackground() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Color.secondary.opacity(0.10))
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

    /// Keeps every iOS root tab on the same compact navigation baseline.
    func rootTabNavigation(_ title: LocalizedStringKey) -> some View {
        #if os(iOS)
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.rootNavigationSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Leaves room to scroll the final control clear of iOS's floating tab bar.
    func rootTabScrollClearance() -> some View {
        #if os(iOS)
        self.contentMargins(.bottom, Theme.rootTabBottomClearance, for: .scrollContent)
        #else
        self
        #endif
    }
}

struct ScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(iOS)
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            Theme.cream.opacity(colorScheme == .dark ? 0.03 : 0.72)
        }
        .ignoresSafeArea()
        #else
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
        #endif
    }
}

struct LandingHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.14))
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
