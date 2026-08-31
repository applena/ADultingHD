import SwiftUI

/// A cozy, code-native home illustration whose rooms remain real controls.
/// It owns only temporary onboarding selection; tasks stay independent records.
struct HomeFloorPlanView: View {
    @Binding var selectedLocations: Set<HomeLocation>
    @State private var showsMoreSpaces = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 0) {
            twilightSky
            house
        }
        .background(Theme.onboardingTwilightBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius)
                .strokeBorder(Theme.sky.opacity(0.22))
        }
        .shadow(color: Theme.adventureBlue.opacity(0.22), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showsMoreSpaces) {
            moreSpacesSheet
        }
    }

    private var twilightSky: some View {
        ZStack {
            HStack(alignment: .top) {
                Image(systemName: "moon.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.hearthGold.opacity(0.92))

                Spacer()

                HStack(spacing: 14) {
                    Image(systemName: "sparkle")
                    Image(systemName: "sparkles")
                    Image(systemName: "sparkle")
                }
                .font(.caption)
                .foregroundStyle(Theme.cream.opacity(0.78))
            }
            .padding(.horizontal, 24)

            Image(systemName: "house.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.adventureBlue)
                .offset(y: 25)
        }
        .frame(height: 70)
        .accessibilityHidden(true)
    }

    private var house: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(HomeLocation.primaryCases) { location in
                locationTile(location)
            }

            moreSpacesButton
        }
        .padding(10)
        .background(Theme.adventureBlue.opacity(0.74))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.hearthGold.opacity(0.52))
                .frame(height: 2)
        }
        .accessibilityLabel("Home space selector")
    }

    private func locationTile(_ location: HomeLocation) -> some View {
        let selected = selectedLocations.contains(location)

        return Button {
            toggle(location)
        } label: {
            roomLabel(location, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-location-\(location.id)")
        .accessibilityLabel("\(location.rawValue) space")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(selected ? "Double tap to remove this space" : "Double tap to include this space")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func roomLabel(_ location: HomeLocation, selected: Bool) -> some View {
        let color = Theme.categoryColor(location.taskCategory)

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 7) {
                Image(systemName: location.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(selected ? Theme.cream : color.opacity(0.92))
                    .accessibilityHidden(true)

                Text(location.rawValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.sky)
                    .background(Theme.adventureBlue, in: Circle())
                    .padding(7)
                    .accessibilityHidden(true)
            }
        }
        .background(
            selected ? color.opacity(0.34) : Color.black.opacity(0.20),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Theme.sky : Theme.cream.opacity(0.20), lineWidth: selected ? 2.5 : 1)
        }
        .shadow(color: selected ? Theme.sky.opacity(0.30) : .clear, radius: 6)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var moreSpacesButton: some View {
        let additionalCount = selectedLocations.intersection(Set(HomeLocation.additionalCases)).count

        return Button {
            showsMoreSpaces = true
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 7) {
                    Image(systemName: "plus.circle")
                        .font(.title2.weight(.semibold))
                    Text("More spaces")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Theme.cream)
                .frame(maxWidth: .infinity, minHeight: 76)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)

                if additionalCount > 0 {
                    Text("\(additionalCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.adventureBlue)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Theme.hearthGold, in: Circle())
                        .padding(8)
                }
            }
            .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.cream.opacity(0.20))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-more-spaces")
        .accessibilityLabel("More spaces")
        .accessibilityValue(additionalCount == 0 ? "None selected" : "\(additionalCount) selected")
        .accessibilityHint("Shows additional rooms and areas")
    }

    private var moreSpacesSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(HomeLocation.additionalCases) { location in
                        locationTile(location)
                    }
                }
                .padding()

                Text("You can add any other room when you create a task.")
                    .font(.footnote)
                    .foregroundStyle(Theme.cream.opacity(0.72))
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .background(Theme.onboardingTwilightBackground.ignoresSafeArea())
            .navigationTitle("More spaces")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showsMoreSpaces = false
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func toggle(_ location: HomeLocation) {
        if selectedLocations.contains(location) {
            selectedLocations.remove(location)
        } else {
            selectedLocations.insert(location)
        }
    }
}
