import SwiftUI

/// Compact header control that displays the active household name and, when
/// tapped, opens a menu listing all known households plus a Pro-gated option
/// to create a new one. Place this in the main navigation toolbar (iOS) or
/// sidebar header (macOS).
struct HouseholdSwitcher: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    @State private var showCreateSheet = false
    @State private var showProUpgrade = false

    var body: some View {
        Menu {
            ForEach(dataStore.listHouseholds()) { household in
                Button {
                    guard household.id != dataStore.activeHouseholdId else { return }
                    Task { await dataStore.switchHousehold(to: household.id) }
                } label: {
                    HStack {
                        Text(household.name)
                        if household.id == dataStore.activeHouseholdId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                if storeManager.isPro {
                    showCreateSheet = true
                } else {
                    showProUpgrade = true
                }
            } label: {
                if storeManager.isPro {
                    Label("New Household…", systemImage: "plus")
                } else {
                    Label("New Household… (Pro)", systemImage: "crown.fill")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.caption)
                Text(dataStore.activeHousehold.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.15), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .sheet(isPresented: $showCreateSheet) {
            CreateHouseholdSheet(isPresented: $showCreateSheet)
        }
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeView()
        }
    }
}
