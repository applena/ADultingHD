import SwiftUI

// MARK: - Confetti Particle

struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let color: Color
    let size: CGFloat
    let rotation: Double
    let speed: CGFloat
}

// MARK: - Celebration Overlay

struct CelebrationOverlay: View {
    let type: CelebrationType
    @Binding var isShowing: Bool

    @State private var particles: [ConfettiPiece] = []
    @State private var opacity: Double = 1
    @State private var scale: CGFloat = 0.5
    @State private var textOpacity: Double = 0

    enum CelebrationType {
        case levelUp(Int)
        case achievement(String)
        case streakMilestone(Int)
        case taskComplete

        var title: String {
            switch self {
            case .levelUp(let level): "Level \(level)!"
            case .achievement(let name): name
            case .streakMilestone(let days): "\(days)-Day Streak!"
            case .taskComplete: "Done!"
            }
        }

        var icon: String {
            switch self {
            case .levelUp: "arrow.up.circle.fill"
            case .achievement: "medal.fill"
            case .streakMilestone: "flame.fill"
            case .taskComplete: "checkmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .levelUp: Theme.levelPurple
            case .achievement: Theme.xpGold
            case .streakMilestone: Theme.streakOrange
            case .taskComplete: Theme.successGreen
            }
        }

        var showConfetti: Bool {
            switch self {
            case .taskComplete: false
            default: true
            }
        }
    }

    var body: some View {
        ZStack {
            // Confetti
            if type.showConfetti {
                ForEach(particles) { particle in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size * 0.6)
                        .rotationEffect(.degrees(particle.rotation))
                        .position(x: particle.x, y: particle.y)
                }
            }

            // Central badge
            VStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.system(size: 50))
                    .foregroundStyle(type.color)
                    .scaleEffect(scale)

                Text(type.title)
                    .font(.title.bold())
                    .foregroundStyle(type.color)
                    .opacity(textOpacity)
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                scale = 1.2
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.1)) {
                textOpacity = 1
            }

            if type.showConfetti {
                generateConfetti()
            }

            // Dismiss after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isShowing = false
                }
            }
        }
    }

    private func generateConfetti() {
        let colors: [Color] = [Theme.xpGold, Theme.levelPurple, Theme.streakOrange, Theme.successGreen, Theme.coral, Theme.sky, Theme.mint]
        let screenWidth: CGFloat = 400

        for _ in 0..<40 {
            let piece = ConfettiPiece(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: -50...0),
                color: colors.randomElement()!,
                size: CGFloat.random(in: 4...8),
                rotation: Double.random(in: 0...360),
                speed: CGFloat.random(in: 2...5)
            )
            particles.append(piece)
        }

        // Animate particles falling
        withAnimation(.easeIn(duration: 2)) {
            for i in particles.indices {
                particles[i].y += CGFloat.random(in: 400...800)
                particles[i].x += CGFloat.random(in: -50...50)
            }
        }
    }
}

// MARK: - View Extension

extension View {
    func celebrationOverlay(type: CelebrationOverlay.CelebrationType?, isShowing: Binding<Bool>) -> some View {
        overlay {
            if let type, isShowing.wrappedValue {
                CelebrationOverlay(type: type, isShowing: isShowing)
            }
        }
    }
}
