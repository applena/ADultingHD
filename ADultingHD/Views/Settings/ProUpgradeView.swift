import SwiftUI

struct ProUpgradeView: View {
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss

    private let features: [(icon: String, title: String, detail: String)] = [
        ("person.3.fill", "Household Profiles", "Add family members and compete on the leaderboard"),
        ("chart.bar.fill", "Advanced Analytics", "XP charts, completion trends, category breakdown, streak calendar"),
        ("medal.fill", "All 18 Achievements", "Unlock the complete achievement collection"),
        ("paintpalette.fill", "Full Avatar Shop", "38 items: characters, hats, glasses, accessories, backgrounds"),
        ("plus.circle.fill", "Unlimited Custom Tasks", "Create as many custom tasks as you want"),
        ("flame.fill", "Streak & Consistency Bonuses", "Earn bonus XP for daily, weekly, and monthly consistency"),
        ("leaf.fill", "Seasonal Suggestions", "Seasonal task recommendations throughout the year"),
        ("list.clipboard.fill", "Shopping List Export", "Share your supply shopping list"),
        ("square.and.arrow.up", "Data Export & Import", "Backup and restore your progress"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    featureList
                    purchaseSection
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 50))
                .foregroundStyle(Theme.xpGold)

            Text("Upgrade to Pro")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("One-time purchase. No subscription. Ever.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.element.title) { index, feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.icon)
                        .font(.title3)
                        .foregroundStyle(Theme.levelPurple)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline.weight(.semibold))
                        Text(feature.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal)

                if index < features.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .cardBackground()
        .padding(.horizontal)
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await storeManager.purchase() }
            } label: {
                Group {
                    if storeManager.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else if let product = storeManager.proProduct {
                        Text("Unlock Pro \u{2014} \(product.displayPrice)")
                            .font(.headline)
                    } else {
                        Text("Unlock Pro \u{2014} $9.99")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.levelPurple, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(storeManager.proProduct == nil || storeManager.isPurchasing)

            Button {
                Task { await storeManager.restorePurchases() }
            } label: {
                Text("Restore Purchase")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)

            if let message = storeManager.failureMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}

// MARK: - Inline Pro Prompt

struct ProPromptCard: View {
    let title: String
    let icon: String
    @State private var showUpgrade = false

    var body: some View {
        Button { showUpgrade = true } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.xpGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Upgrade to Pro to unlock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.xpGold)
            }
            .padding(12)
            .background(Theme.xpGold.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showUpgrade) {
            ProUpgradeView()
        }
    }
}
