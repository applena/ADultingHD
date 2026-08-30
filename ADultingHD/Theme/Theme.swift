import SwiftUI

enum Theme {
    // MARK: - Colors

    // Cozy Domestic Adventure foundations
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.93)
    static let parchment = Color(red: 0.98, green: 0.93, blue: 0.84)
    static let adventureBlue = Color(red: 0.08, green: 0.20, blue: 0.35)
    static let hearthGold = Color(red: 0.94, green: 0.58, blue: 0.16)
    static let leafGreen = Color(red: 0.24, green: 0.43, blue: 0.29)
    static let coral = Color(red: 0.98, green: 0.45, blue: 0.45)
    static let sky = Color(red: 0.44, green: 0.66, blue: 0.91)
    static let plum = Color(red: 0.46, green: 0.36, blue: 0.78)

    /// The design system uses navy as the primary action color. Keeping this
    /// alias lets existing screens use the same semantic name while still
    /// honoring the new visual direction.
    static let accent = adventureBlue

    // Gamification — curated soft palette
    static let xpGold = hearthGold
    static let streakOrange = hearthGold
    static let levelPurple = plum
    static let successGreen = leafGreen
    static let warningRed = coral
    static let overdueRed = warningRed.opacity(0.85)

    // Compatibility aliases for older call sites.
    static let mint = leafGreen
    static let lavender = plum

    static func categoryColor(_ category: TaskCategory) -> Color {
        switch category {
        case .kitchen: hearthGold
        case .bathroom: sky
        case .bedroom: plum
        case .livingRoom: leafGreen
        case .laundry: Color(red: 0.24, green: 0.56, blue: 0.64)
        case .outdoor: Color(red: 0.30, green: 0.56, blue: 0.38)
        case .garage: Color(red: 0.35, green: 0.40, blue: 0.46)
        case .office: adventureBlue
        case .general: Color(red: 0.52, green: 0.42, blue: 0.32)
        }
    }

    /// Keeps the curated palette for legacy rooms and assigns every custom
    /// room a stable hue derived from its locale-independent identity.
    static func roomColor(_ room: String?) -> Color {
        guard let identity = HouseholdTask.roomIdentity(room) else {
            return categoryColor(.general)
        }
        if let category = TaskCategory.allCases.first(where: {
            HouseholdTask.roomIdentity($0.rawValue) == identity
        }) {
            return categoryColor(category)
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Color(
            hue: Double(hash % 360) / 360,
            saturation: 0.58,
            brightness: 0.72
        )
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
        case .easy: leafGreen
        case .medium: hearthGold
        case .hard: coral
        case .epic: plum
        }
    }

    // MARK: - Layout

    static let chipCornerRadius: CGFloat = 12
    static let controlHeight: CGFloat = 52

    #if os(macOS)
    static let cardPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let cornerRadius: CGFloat = 16
    static let macOSContentMaxWidth: CGFloat = 780
    static let rowSpacing: CGFloat = 8
    #else
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let cornerRadius: CGFloat = 16
    static let rowSpacing: CGFloat = 8
    static let rootTabBottomClearance: CGFloat = 72

    static let rootNavigationSurface = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.08, green: 0.12, blue: 0.19, alpha: 1)
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
                    .shadow(color: Theme.adventureBlue.opacity(0.08), radius: 12, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.adventureBlue.opacity(0.10))
            }
    }

    /// Card background only (no padding) - for views with custom padding.
    func cardBackground() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(.background)
                    .shadow(color: Theme.adventureBlue.opacity(0.08), radius: 12, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.adventureBlue.opacity(0.10))
            }
    }

    /// Shared primary action treatment for onboarding and prominent screen
    /// actions. The label remains native SwiftUI content, so Dynamic Type and
    /// accessibility labels continue to work normally.
    func adventurePrimaryAction() -> some View {
        self
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
            .padding(.horizontal, 16)
            .background(Theme.adventureBlue, in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
            .foregroundStyle(.white)
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
            Theme.cream.opacity(colorScheme == .dark ? 0.03 : 0.82)
        }
        .ignoresSafeArea()
        #else
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Theme.cream.opacity(colorScheme == .dark ? 0.03 : 0.62)
        }
        .ignoresSafeArea()
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
                RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                    .fill(color.opacity(0.14))
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 56, height: 56)

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
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
    }
}
