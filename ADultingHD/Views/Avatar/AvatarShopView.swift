import SwiftUI

struct AvatarShopView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    @State private var selectedSlot: AvatarSlot = .base

    private var coins: Int { dataStore.profile.coins }
    private var level: Int { dataStore.profile.level }
    private var state: AvatarState { dataStore.profile.avatarState }

    private var itemsForSlot: [AvatarItem] {
        avatarShopItems.filter { $0.slot == selectedSlot }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                // Avatar Preview
                previewCard

                // Coin Balance
                coinBalance

                // Slot Picker
                slotPicker

                // Items Grid
                itemsGrid

                if !storeManager.isPro {
                    ProPromptCard(title: "Full Avatar Shop", icon: "paintpalette.fill")
                }
            }
            .padding()
        }
        .navigationTitle("Avatar Shop")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

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

    // MARK: - Slot Picker

    private var slotPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AvatarSlot.allCases) { slot in
                    FilterChip(
                        label: slot.rawValue,
                        icon: slot.icon,
                        isSelected: selectedSlot == slot
                    ) {
                        selectedSlot = slot
                    }
                }
            }
        }
    }

    // MARK: - Items Grid

    private var itemsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Unequip option for non-base slots
            if selectedSlot != .base {
                unequipCard
            }

            ForEach(itemsForSlot) { item in
                ShopItemCard(item: item)
            }
        }
    }

    private var unequipCard: some View {
        let isUnequipped = state.equipped(slot: selectedSlot) == nil
        return Button {
            Task { await dataStore.unequipAvatarItem(slot: selectedSlot) }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 50, height: 50)
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text("None")
                    .font(.caption.bold())
                Text("Remove")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                isUnequipped ? Theme.successGreen.opacity(0.1) : Color.secondary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isUnequipped ? Theme.successGreen : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shop Item Card

private struct ShopItemCard: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    let item: AvatarItem

    private var profile: UserProfile { dataStore.profile }
    private var owned: Bool { profile.avatarState.owns(item.id) }
    private var equipped: Bool { profile.avatarState.equipped(slot: item.slot) == item.id }
    private var canAfford: Bool { profile.coins >= item.cost }
    private var levelLocked: Bool { profile.level < item.unlockLevel }
    private var proLocked: Bool { !storeManager.isPro && item.cost > 0 && !owned }

    var body: some View {
        Button { handleTap() } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(equipped ? Theme.levelPurple.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 50, height: 50)
                    Text(item.emoji)
                        .font(.system(size: 30))
                        .opacity(levelLocked && !owned ? 0.3 : 1.0)

                    if (levelLocked && !owned) || proLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(proLocked ? Theme.xpGold : .secondary)
                            .offset(x: 18, y: 18)
                    }
                }

                Text(item.name)
                    .font(.caption.bold())
                    .lineLimit(1)

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
