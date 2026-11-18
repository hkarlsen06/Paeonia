import SwiftUI

/// An avatar with their mark in a small badge at the bottom trailing edge. On
/// the player's turn a ring in their color circles it.
struct BoardGamePlayerAvatar: View {
    let player: BoardGamePlayerInfo
    let isActive: Bool
    var size: CGFloat = 44

    private static let badgeSize: CGFloat = 20
    private static let turnRingOutset: CGFloat = 4

    var body: some View {
        BoardGameAvatar(player: player, size: size)
            .overlay { turnRing }
            .overlay(alignment: .bottomTrailing) {
                badge.offset(x: 4, y: 4)
            }
    }

    private var turnRing: some View {
        Circle()
            .strokeBorder(player.style.color, lineWidth: PaeoniaRadius.strokeEmphasis)
            .padding(-Self.turnRingOutset)
            .opacity(isActive ? 1 : 0)
            .animation(PaeoniaMotion.stateChange, value: isActive)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
