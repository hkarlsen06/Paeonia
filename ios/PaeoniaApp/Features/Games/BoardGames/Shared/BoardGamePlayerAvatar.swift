import SwiftUI

/// An avatar with their mark in a small badge at the bottom trailing edge. On
/// the player's turn it grows a little. A steady green ring
/// shows the player has the game open.
struct BoardGamePlayerAvatar: View {
    let player: BoardGamePlayerInfo
    let isActive: Bool
    var isHere = false
    var size: CGFloat = 44

    private static let badgeSize: CGFloat = 20
    private static let activeScale: CGFloat = 1.1

    var body: some View {
        BoardGameAvatar(player: player, size: size)
            .gamePresenceRing(isHere)
            .overlay(alignment: .bottomTrailing) {
                badge.offset(x: 4, y: 4)
            }
            .scaleEffect(isActive ? Self.activeScale : 1)
    }

    private var badge: some View {
        Circle()
            .fill(player.style.color)
            .frame(width: Self.badgeSize, height: Self.badgeSize)
            .overlay {
                BoardMarkView(style: player.style, tint: .paeoniaTextInverse)
                    .padding(3)
            }
            .overlay {
                Circle().strokeBorder(.paeoniaBackgroundSecondary, lineWidth: PaeoniaRadius.strokeEmphasis)
            }
    }
}
