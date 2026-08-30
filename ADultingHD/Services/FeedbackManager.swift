import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor
enum FeedbackManager {
    #if os(iOS)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    #endif

    static func taskCompleted() {
        #if os(iOS)
        notificationGenerator.notificationOccurred(.success)
        #endif
    }

    static func levelUp() {
        #if os(iOS)
        notificationGenerator.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            heavyImpact.impactOccurred()
        }
        #endif
    }

    static func achievementUnlocked() {
        taskCompleted()
    }

    static func streakMilestone() {
        #if os(iOS)
        mediumImpact.impactOccurred()
        #endif
    }
}
