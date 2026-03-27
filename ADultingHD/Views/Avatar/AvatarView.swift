import SwiftUI

struct AvatarView: View {
    let avatarState: AvatarState
    var size: CGFloat = 120

    private var scale: CGFloat { size / 120 }

    private func equippedItem(for slot: AvatarSlot) -> AvatarItem? {
        guard let id = avatarState.equipped(slot: slot) else { return nil }
        return avatarItem(byId: id)
    }

    var body: some View {
        ZStack {
            // Background
            if let bg = equippedItem(for: .background) {
                backgroundLayer(bg)
            } else {
                Circle()
                    .fill(Theme.levelPurple.opacity(0.12))
                    .frame(width: size, height: size)
            }

            ForEach([AvatarSlot.base, .hat, .glasses, .accessory], id: \.self) { slot in
                if let item = equippedItem(for: slot) {
                    Text(item.emoji)
                        .font(.system(size: item.fontSize * scale))
                        .offset(x: item.offsetX * scale, y: item.offsetY * scale)
                }
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func backgroundLayer(_ bg: AvatarItem) -> some View {
        ZStack {
            Circle()
                .fill(Theme.levelPurple.opacity(0.08))
                .frame(width: size, height: size)

            // Scatter the background emoji around
            let positions: [(CGFloat, CGFloat)] = [
                (-0.3, -0.35), (0.3, -0.3), (-0.35, 0.2),
                (0.35, 0.25), (0.0, -0.4), (0.0, 0.4),
            ]
            ForEach(Array(positions.enumerated()), id: \.offset) { _, pos in
                Text(bg.emoji)
                    .font(.system(size: 14 * scale))
                    .opacity(0.5)
                    .offset(x: pos.0 * size, y: pos.1 * size)
            }
        }
    }
}

// MARK: - Compact Avatar (for dashboard / nav)

struct CompactAvatarView: View {
    let avatarState: AvatarState
    var size: CGFloat = 44

    var body: some View {
        AvatarView(avatarState: avatarState, size: size)
            .clipShape(Circle())
    }
}
