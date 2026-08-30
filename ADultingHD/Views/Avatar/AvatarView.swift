import SwiftUI

struct AvatarView: View {
    private let equippedCharacter: AvatarItem?
    private let size: CGFloat

    init(avatarState: AvatarState, size: CGFloat = 120) {
        self.equippedCharacter = avatarState.equipped(slot: .character).flatMap(avatarItem(byId:))
        self.size = size
    }

    /// Renders a single item directly, for pickers that show catalog entries
    /// rather than what someone currently has equipped.
    init(item: AvatarItem?, size: CGFloat = 120) {
        self.equippedCharacter = item
        self.size = size
    }

    private var scale: CGFloat { size / 120 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.levelPurple.opacity(0.12))
                .frame(width: size, height: size)

            if let character = equippedCharacter {
                if let imgName = character.imageName {
                    Image(imgName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.85, height: size * 0.85)
                        .clipShape(Circle())
                } else {
                    Text(character.emoji)
                        .font(.system(size: character.fontSize * scale))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Compact Avatar (for dashboard / nav)

struct CompactAvatarView: View {
    let avatarState: AvatarState
    var size: CGFloat = 44
    /// Draws the "this is you" ring used across the leaderboards.
    var isCurrentUser: Bool = false

    var body: some View {
        AvatarView(avatarState: avatarState, size: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(isCurrentUser ? Theme.levelPurple : .clear, lineWidth: max(1.5, size / 20))
            }
    }
}
