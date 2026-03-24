import SwiftUI

struct WelcomeView: View {
    @State private var currentPage = 0
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 80))
                .foregroundStyle(pageColor)
                .contentTransition(.symbolEffect(.replace))
                .padding(.bottom, 28)

            // Title
            Text(pageTitle)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)

            // Subtitle
            Text(pageSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            Spacer()

            // Action button
            Button {
                if currentPage == 3 {
                    onComplete()
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        currentPage += 1
                    }
                }
            } label: {
                Text(currentPage == 3 ? "Let's Go!" : "Next")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 16)
                    .background(pageColor, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == currentPage ? pageColor : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                        .scaleEffect(i == currentPage ? 1.2 : 1.0)
                }
            }
            .padding(.top, 20)
            .animation(.spring(response: 0.3), value: currentPage)

            // Skip / Back
            Button {
                if currentPage > 0 {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        currentPage -= 1
                    }
                } else {
                    onComplete()
                }
            } label: {
                Text(currentPage > 0 ? "Back" : "Skip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [pageColor.opacity(0.10), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)
        }
    }

    // MARK: - Page Content

    private var iconName: String {
        switch currentPage {
        case 0: "house.fill"
        case 1: "star.circle.fill"
        case 2: "flame.fill"
        default: "trophy.fill"
        }
    }

    private var pageColor: Color {
        switch currentPage {
        case 0: Theme.coral
        case 1: Theme.xpGold
        case 2: Theme.streakOrange
        default: Theme.levelPurple
        }
    }

    private var pageTitle: String {
        switch currentPage {
        case 0: "Welcome to\nADultingHD!"
        case 1: "Earn XP"
        case 2: "Build Streaks"
        default: "Ready to\nLevel Up?"
        }
    }

    private var pageSubtitle: String {
        switch currentPage {
        case 0: "Turn boring chores into an epic adventure. Because adulting is hard — but it doesn't have to be boring."
        case 1: "Complete household tasks to earn experience points. The harder the task, the bigger the reward!"
        case 2: "Stay consistent day after day. The longer your streak, the more bonus XP you earn."
        default: "Start conquering your household quests and become the ultimate adulting champion."
        }
    }
}
