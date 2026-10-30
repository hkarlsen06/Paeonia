import SwiftUI

/// Both players. My avatar is on the leading side, my partner's on the trailing
/// side. Whoever's turn it is, or whoever won, gets glass in their piece color, a
/// slightly larger avatar and a bold name. A steady green ring on my partner's avatar shows
/// they have the game open. At accessibility text sizes the row stacks.
struct BoardGamePlayersRow: View {
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let turn: BoardGameTurnLabel
    let partnerName: String
    let partnerIsHere: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let avatarSize: CGFloat = 44
    private static let columnWidth: CGFloat = 88

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                sideBySide
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: turn)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: partnerIsHere)
    }

    // MARK: Layouts

    private var sideBySide: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
            column(for: me, isMe: true)
            Spacer(minLength: 0)
            column(for: partner, isMe: false)
        }
        .frame(maxWidth: .infinity)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            row(for: me, isMe: true)
            row(for: partner, isMe: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Avatar over name.
    private func column(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            avatar(for: player, isMe: isMe)
            styledName(isMe: isMe)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(PaeoniaSpacing.space8)
        .backdrop(color: player.style.color, isActive: isActive(isMe: isMe))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName(isMe: isMe))
        .accessibilityValue(spokenTurn(isMe: isMe))
        .frame(width: Self.columnWidth)
    }

    /// Avatar beside name, for accessibility text sizes.
    private func row(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            avatar(for: player, isMe: isMe)
            styledName(isMe: isMe)
        }
        .padding(PaeoniaSpacing.space8)
        .backdrop(color: player.style.color, isActive: isActive(isMe: isMe))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName(isMe: isMe))
        .accessibilityValue(spokenTurn(isMe: isMe))
    }

    // MARK: Pieces

    private func avatar(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        BoardGamePlayerAvatar(
            player: player,
            isActive: isActive(isMe: isMe),
            isHere: !isMe && partnerIsHere,
            size: Self.avatarSize
        )
    }

    private func isActive(isMe: Bool) -> Bool {
        turn.isActive(forMe: isMe)
    }

    private func name(isMe: Bool) -> Text {
        isMe ? Text(.boardGamesPlayerYou) : Text(verbatim: partnerName)
    }

    /// The name, bold and white while it is this player's turn or they won.
    private func styledName(isMe: Bool) -> some View {
        let active = isActive(isMe: isMe)
        return name(isMe: isMe)
            .font(PaeoniaTypography.caption.weight(active ? .bold : .regular))
            .foregroundStyle(active ? Color.paeoniaTextPrimary : .paeoniaTextSecondary)
    }

    /// "[Name] is here" while my partner has the game open, otherwise the name.
    private func spokenName(isMe: Bool) -> Text {
        !isMe && partnerIsHere ? Text(.boardGamesStatusHere(partnerName)) : name(isMe: isMe)
    }

    /// "Your turn", "[Name]'s turn", "You won" or "[Name] won" for the active
    /// player, so VoiceOver hears what the colored glass shows. Nothing for the other.
    private func spokenTurn(isMe: Bool) -> Text {
        guard isActive(isMe: isMe), let spoken = turn.spoken(partnerName: partnerName) else {
            return Text(verbatim: "")
        }
        return Text(spoken)
    }
}

private extension View {
    /// Glass hugging the avatar and name. It keeps them readable where a board
    /// runs under the row, as Ludo's does. Plum like a hub card's badge, and the
    /// player's piece color for the active player, mixed with plum so white text
    /// stays readable. The tint is light, so a scene under the row, such as Ludo's
    /// warm room, shows through the glass.
    func backdrop(color: Color, isActive: Bool) -> some View {
        let tint = isActive
            ? color.mix(with: .paeoniaBackgroundSecondary, by: 0.45)
            : .paeoniaBackgroundSecondary
        return glassEffect(
            .regular.tint(tint.opacity(0.45)),
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
        )
    }
}

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

#if DEBUG
#Preview("Turns") {
    VStack(spacing: PaeoniaSpacing.space24) {
        ForEach([BoardGameTurnLabel.yourTurn, .partnerTurn, .youWon, .partnerWon, .draw], id: \.self) { turn in
            BoardGamePlayersRow(
                me: BoardGamePreviewData.me,
                partner: BoardGamePreviewData.partner,
                turn: turn,
                partnerName: BoardGamePreviewData.partner.name,
                partnerIsHere: turn == .yourTurn
            )
        }
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}

#Preview("Accessibility size") {
    BoardGamePlayersRow(
        me: BoardGamePreviewData.me,
        partner: BoardGamePreviewData.partner,
        turn: .partnerTurn,
        partnerName: BoardGamePreviewData.partner.name,
        partnerIsHere: true
    )
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
#endif
