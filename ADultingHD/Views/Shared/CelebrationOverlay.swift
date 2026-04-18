import SwiftUI

struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let color: Color
    let size: CGFloat
    let rotation: Double
}

struct CelebrationOverlay: View {
    let type: CelebrationType
    let onDismiss: () -> Void

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
        GeometryReader { geo in
            ZStack {
                if type.showConfetti {
                    ForEach(particles) { particle in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(particle.color)
                            .frame(width: particle.size, height: particle.size * 0.6)
                            .rotationEffect(.degrees(particle.rotation))
                            .position(x: particle.x, y: particle.y)
                    }
                }

                VStack(spacing: 12) {
                    Image(systemName: type.icon)
                        .font(.system(size: 50))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundStyle(type.color)
                        .scaleEffect(scale)

                    Text(type.title)
                        .font(.title.bold())
                        .foregroundStyle(type.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .opacity(textOpacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    generateConfetti(width: geo.size.width)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onDismiss()
                    }
                }
            }
        }
    }

    private func generateConfetti(width: CGFloat) {
        let colors: [Color] = [Theme.xpGold, Theme.levelPurple, Theme.streakOrange, Theme.successGreen, Theme.coral, Theme.sky, Theme.mint]

        for _ in 0..<40 {
            let piece = ConfettiPiece(
                x: CGFloat.random(in: 0...width),
                y: CGFloat.random(in: -50...0),
                color: colors.randomElement()!,
                size: CGFloat.random(in: 4...8),
                rotation: Double.random(in: 0...360)
            )
            particles.append(piece)
        }

        withAnimation(.easeIn(duration: 2)) {
            for i in particles.indices {
                particles[i].y += CGFloat.random(in: 400...800)
                particles[i].x += CGFloat.random(in: -50...50)
            }
        }
    }
}

extension View {
    func celebrationOverlay(type: CelebrationOverlay.CelebrationType?, onDismiss: @escaping () -> Void) -> some View {
        overlay {
            if let type {
                CelebrationOverlay(type: type, onDismiss: onDismiss)
            }
        }
    }
}
