import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor
enum FeedbackManager {
    static func taskCompleted() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    static func levelUp() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        // Double tap for emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        }
        #endif
    }

    static func achievementUnlocked() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    static func streakMilestone() {
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        #endif
    }

    static func buttonTap() {
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #endif
    }
}
