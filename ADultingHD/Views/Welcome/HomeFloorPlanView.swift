import SwiftUI

/// An interactive, code-native cutaway of a home. It deliberately owns only
/// the temporary onboarding selection; tasks remain independent records.
struct HomeFloorPlanView: View {
    @Binding var selectedLocations: Set<HomeLocation>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Choose your spaces", systemImage: "hand.tap.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.adventureBlue)

                Spacer(minLength: 8)

                Text("\(selectedLocations.count) selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Spaces selected")
            }

            floorPlan

            Text("Spaces help us filter task suggestions and search. You can add any task later, even if it does not have a room.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.parchment.opacity(0.62), in: RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.onboardingArtworkCornerRadius)
                .strokeBorder(Theme.adventureBlue.opacity(0.14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var floorPlan: some View {
        VStack(spacing: 0) {
            roof

            roomGrid
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.adventureBlue.opacity(0.16))
        }
        .accessibilityLabel("Cross-sectional home map")
    }

    /// GeometryReader supplies a real width to each room row. That keeps the
    /// two-column living room row proportional without allowing an intrinsic
    /// grid width to push the onboarding scroll view sideways on iPhone.
    private var roomGrid: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / 3

            VStack(spacing: 0) {
                equalRoomRow([.bedroom, .bathroom, .office], width: columnWidth)

                HStack(spacing: 0) {
                    locationTile(.livingRoom)
                        .frame(width: columnWidth * 2)
                    locationTile(.kitchen)
                        .frame(width: columnWidth)
                }

                equalRoomRow([.laundryRoom, .entryway, .garage], width: columnWidth)

                locationTile(.outsideArea)
                    .frame(width: columnWidth * 3)
            }
        }
        .frame(height: 4 * roomRowHeight)
        .frame(maxWidth: .infinity)
    }

    private func equalRoomRow(_ locations: [HomeLocation], width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(locations) { location in
                locationTile(location)
                    .frame(width: width)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private let roomRowHeight: CGFloat = 104

    private var roof: some View {
        ZStack {
            HomeRoofShape()
                .fill(Theme.adventureBlue)

            HStack(spacing: 8) {
                Image(systemName: "house.fill")
                    .accessibilityHidden(true)
                Text("YOUR HOME")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
            }
            .foregroundStyle(.white)
            .padding(.top, 18)
        }
        .frame(height: 68)
        .padding(.horizontal, 20)
        .accessibilityHidden(true)
    }

    private func locationTile(_ location: HomeLocation) -> some View {
        let selected = selectedLocations.contains(location)
        let color = Theme.categoryColor(location.taskCategory)

        return Button {
            if selected {
                selectedLocations.remove(location)
            } else {
                selectedLocations.insert(location)
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: location.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? color : Theme.adventureBlue.opacity(0.78))
                    .accessibilityHidden(true)

                Text(location.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(selected ? color : .secondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                selected ? color.opacity(0.18) : Color.white.opacity(0.48),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? color : Theme.adventureBlue.opacity(0.12), lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(1)
        .accessibilityIdentifier("onboarding-location-\(location.id)")
        .accessibilityLabel("\(location.rawValue) space")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(selected ? "Double tap to remove this space" : "Double tap to include this space")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HomeRoofShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
