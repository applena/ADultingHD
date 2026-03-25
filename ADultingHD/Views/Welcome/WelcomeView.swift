import SwiftUI

struct WelcomeView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var currentPage = 0
    @State private var isCompletingStarterTask = false
    @State private var starterXPMessage: String?

    let onComplete: () -> Void

    private var starterTask: HouseholdTask? {
        dataStore.tasks.first { $0.name == "Wipe the counters" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 80))
                .foregroundStyle(pageColor)
                .contentTransition(.symbolEffect(.replace))
                .padding(.bottom, 28)

            Text(pageTitle)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)

            Text(pageSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            if currentPage == 1 {
                starterTaskSection
                    .padding(.top, 20)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button {
                handlePrimaryAction()
            } label: {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 16)
                    .background(pageColor, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(currentPage == 1 && starterXPMessage == nil)

            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .fill(i == currentPage ? pageColor : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                        .scaleEffect(i == currentPage ? 1.2 : 1.0)
                }
            }
            .padding(.top, 20)
            .animation(.spring(response: 0.3), value: currentPage)

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

    private var starterTaskSection: some View {
        VStack(spacing: 12) {
            Button {
                completeStarterTask()
            } label: {
                HStack {
                    if isCompletingStarterTask {
                        ProgressView()
                    } else {
                        Image(systemName: starterXPMessage == nil ? "sparkles" : "checkmark.circle.fill")
                    }
                    Text(starterXPMessage == nil ? "Complete: Wipe the counters" : "Starter task complete")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isCompletingStarterTask || starterXPMessage != nil)

            if let starterXPMessage {
                Text(starterXPMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.successGreen)
            }
        }
    }

    private func handlePrimaryAction() {
        if currentPage == 1 {
            onComplete()
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentPage += 1
            }
        }
    }

    private func completeStarterTask() {
        guard let task = starterTask else {
            starterXPMessage = "Nice! Your starter task is ready on Home."
            return
        }

        let beforeXP = dataStore.profile.totalXP
        isCompletingStarterTask = true

        Task {
            await dataStore.completeTask(task)
            let gained = max(dataStore.profile.totalXP - beforeXP, task.xpReward)
            starterXPMessage = "+\(gained) XP earned for finishing \"\(task.name)\""
            isCompletingStarterTask = false
        }
    }

    private var iconName: String {
        currentPage == 0 ? "house.fill" : "sparkles"
    }

    private var pageColor: Color {
        currentPage == 0 ? Theme.coral : Theme.xpGold
    }

    private var pageTitle: String {
        currentPage == 0 ? "Welcome to\nADultingHD!" : "Start Small"
    }

    private var pageSubtitle: String {
        if currentPage == 0 {
            return "We keep day one simple: just a couple daily tasks so you can build momentum, not stress."
        }
        return "Your first quest is quick. Finish it once and instantly see the XP you earned."
    }

    private var primaryButtonTitle: String {
        currentPage == 0 ? "Show Me My First Task" : "Start My Day"
    }
}
