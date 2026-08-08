import SwiftUI

struct AvatarShopView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    @State private var selectedFamily: String? = nil

    private let families = [
        "person", "raccoon", "turtle", "otter", "capybara",
        "cat", "dog", "bunny", "bear", "fox", "panda", "unicorn", "dragon",
    ]

    private var coins: Int { dataStore.profile.coins }
    private var state: AvatarState { dataStore.profile.avatarState }

    private var filteredItems: [AvatarItem] {
        if let family = selectedFamily {
            return avatarShopItems
                .filter { $0.family == family }
                .sorted { $0.unlockLevel < $1.unlockLevel }
        }
        // All: group by family order, animal tier before hero within each family
        return avatarShopItems.sorted {
            let fi = families.firstIndex(of: $0.family) ?? 99
            let fj = families.firstIndex(of: $1.family) ?? 99
            if fi != fj { return fi < fj }
            let ti = $0.tier == .animal ? 0 : 1
            let tj = $1.tier == .animal ? 0 : 1
            if ti != tj { return ti < tj }
            return $0.unlockLevel < $1.unlockLevel
        }
    }

    var body: some View {
        ScrollView {
            #if os(macOS)
            macOSLayout
            #else
            VStack(spacing: Theme.sectionSpacing) {
                previewCard
                coinBalance
                familyPicker
                itemsGrid
                if !storeManager.isPro {
                    ProPromptCard(title: "Full Avatar Shop", icon: "paintpalette.fill")
                }
            }
            .padding()
            #endif
        }
        .navigationTitle("Avatar Shop")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    #if os(macOS)
    private var macOSLayout: some View {
        HStack(alignment: .top, spacing: Theme.sectionSpacing) {
            // Left sidebar: avatar preview + coin balance
            VStack(spacing: Theme.sectionSpacing) {
                previewCard
                coinBalance
                Spacer()
            }
            .frame(width: 220)

            // Right: family filter + items grid
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                familyPicker
                itemsGrid
                if !storeManager.isPro {
                    ProPromptCard(title: "Full Avatar Shop", icon: "paintpalette.fill")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .macOSContentFrame()
    }
    #endif

    // MARK: - Preview

    private var previewCard: some View {
        VStack(spacing: 12) {
            AvatarView(avatarState: state, size: 140)
            Text("Your Avatar")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardBackground()
    }

    // MARK: - Coin Balance

    private var coinBalance: some View {
        HStack {
            Image(systemName: "dollarsign.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.xpGold)
            Text("\(coins)")
                .font(.title3.bold())
                .foregroundStyle(Theme.xpGold)
            Text("coins to spend")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .card()
    }

    // MARK: - Family Picker

    private var familyPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", icon: "person.2.fill", isSelected: selectedFamily == nil) {
                    selectedFamily = nil
                }
                ForEach(families, id: \.self) { family in
                    FilterChip(label: family.capitalized, isSelected: selectedFamily == family) {
                        selectedFamily = family
                    }
                }
            }
        }
    }

    // MARK: - Items Grid

    private var itemsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: Theme.gridColumns), spacing: 12) {
            ForEach(filteredItems) { item in
                ShopItemCard(item: item)
            }
        }
    }

}

// MARK: - Shop Item Card

private struct ShopItemCard: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    let item: AvatarItem

    private var profile: UserProfile { dataStore.profile }
    private var owned: Bool { profile.avatarState.owns(item.id) }
    private var equipped: Bool { profile.avatarState.equipped(slot: .character) == item.id }
    private var canAfford: Bool { profile.coins >= item.cost }
    private var levelLocked: Bool { profile.level < item.unlockLevel }
    private var proLocked: Bool { !storeManager.isPro && item.cost > 0 && !owned }

    var body: some View {
        Button { handleTap() } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(equipped ? Theme.levelPurple.opacity(0.15) : Color.secondary.opacity(0.08))
                            .frame(width: 70, height: 70)

                        if let imgName = item.imageName {
                            Image(imgName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 62, height: 62)
                                .clipShape(Circle())
                                .opacity(levelLocked && !owned ? 0.3 : 1.0)
                        } else {
                            Text(item.emoji)
                                .font(.system(size: item.fontSize * 0.5))
                                .opacity(levelLocked && !owned ? 0.3 : 1.0)
                        }

                        if (levelLocked && !owned) || proLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(proLocked ? Theme.xpGold : .secondary)
                                .offset(x: 22, y: 22)
                        }
                    }

                    if item.tier == .hero {
                        Text("Hero")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.levelPurple, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }

                Text(item.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if owned {
                    if equipped {
                        Text("Equipped")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.successGreen)
                    } else {
                        Text("Owned")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if proLocked {
                    Text("Pro")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.xpGold)
                } else if levelLocked {
                    Text("Lvl \(item.unlockLevel)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if item.cost == 0 {
                    Text("Free")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.successGreen)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.caption2)
                        Text("\(item.cost)")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(canAfford ? Theme.xpGold : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                equipped ? Theme.levelPurple.opacity(0.08) : Color.secondary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(equipped ? Theme.levelPurple : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled((levelLocked && !owned) || proLocked)
    }

    private func handleTap() {
        if owned {
            if !equipped {
                Task { await dataStore.equipAvatarItem(item) }
            }
        } else if canAfford && !levelLocked {
            Task {
                await dataStore.purchaseAvatarItem(item)
                FeedbackManager.achievementUnlocked()
            }
        }
    }
}
