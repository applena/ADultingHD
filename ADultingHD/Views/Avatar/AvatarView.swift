import SwiftUI

struct AvatarView: View {
    let avatarState: AvatarState
    var size: CGFloat = 120

    private var scale: CGFloat { size / 120 }

    private var equippedCharacter: AvatarItem? {
        guard let id = avatarState.equipped(slot: .character) else { return nil }
        return avatarItem(byId: id)
    }

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

    var body: some View {
        AvatarView(avatarState: avatarState, size: size)
            .clipShape(Circle())
    }
}
