import SwiftUI

/// Hosts the five-page onboarding flow and its final Home walkthrough.
struct WelcomeView: View {
    @State private var selectedLocations: Set<HomeLocation> = []

    let onComplete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScreenBackground()
                WelcomeIntroductionView(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    isActive: true,
                    selectedLocations: $selectedLocations,
                    onComplete: onComplete
                )
            }
        }
    }
}

/// Shared pinned action treatment for the standard onboarding pages.
struct WelcomeActionBar: View {
    let title: String
    let action: () -> Void
    let isDisabled: Bool
    let showsProgress: Bool
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var secondaryIsDisabled = false
    var isAccessibilityHidden = false

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Group {
                    if showsProgress {
                        ProgressView()
                            .tint(.white)
                            .accessibilityLabel("Working")
                    } else {
                        HStack(spacing: 8) {
                            Text(title)
                            Image(systemName: "arrow.right")
                                .accessibilityHidden(true)
                        }
                    }
                }
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
                .padding(.horizontal, 16)
                .background(Theme.adventureBlue, in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
                .foregroundStyle(.white)
                .contentShape(RoundedRectangle(cornerRadius: Theme.chipCornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.58 : 1)
            .accessibilityIdentifier(
                isAccessibilityHidden ? "onboarding-inactive-primary-action" : "onboarding-primary-action"
            )
            .accessibilityLabel(title)
            .accessibilityHidden(isAccessibilityHidden)

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .buttonStyle(.plain)
                    .disabled(secondaryIsDisabled)
                    .accessibilityIdentifier(
                        isAccessibilityHidden ? "onboarding-inactive-secondary-action" : "onboarding-secondary-action"
                    )
                    .accessibilityHidden(isAccessibilityHidden)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}
