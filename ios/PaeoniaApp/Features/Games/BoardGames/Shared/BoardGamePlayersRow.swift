import SwiftUI

/// Both players. My avatar is on the leading side, my partner's on the trailing
/// side. Whoever's turn it is, or whoever won, gets a glow, a slightly larger
/// avatar and a bold name in their piece color. A green dot on my partner's
/// avatar shows they have the game open. At accessibility text sizes the row stacks.
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
            styledName(for: player, isMe: isMe)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName(isMe: isMe))
        .accessibilityValue(spokenTurn(isMe: isMe))
        .frame(width: Self.columnWidth)
    }

    /// Avatar beside name, for accessibility text sizes.
    private func row(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            avatar(for: player, isMe: isMe)
            styledName(for: player, isMe: isMe)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName(isMe: isMe))
        .accessibilityValue(spokenTurn(isMe: isMe))
    }

    // MARK: Pieces

    private func avatar(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        BoardGamePlayerAvatar(
            player: player,
            glow: glowState(isMe: isMe),
            isHere: !isMe && partnerIsHere,
            size: Self.avatarSize
        )
    }

    private func glowState(isMe: Bool) -> BoardGameGlowState {
        turn.glowState(forMe: isMe)
    }

    private func isActive(isMe: Bool) -> Bool {
        glowState(isMe: isMe) != .resting
    }

    private func name(isMe: Bool) -> Text {
        isMe ? Text(.boardGamesPlayerYou) : Text(verbatim: partnerName)
    }

    /// The name, bold and in the piece color while it is this player's turn or they won.
    private func styledName(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        let active = isActive(isMe: isMe)
        return name(isMe: isMe)
            .font(PaeoniaTypography.caption.weight(active ? .bold : .regular))
            .foregroundStyle(active ? player.style.color : .paeoniaTextSecondary)
    }

    /// "[Name] is here" while my partner has the game open, otherwise the name.
    private func spokenName(isMe: Bool) -> Text {
        !isMe && partnerIsHere ? Text(.boardGamesStatusHere(partnerName)) : name(isMe: isMe)
    }

    /// "Your turn", "[Name]'s turn", "You won" or "[Name] won" for the active
    /// player, so VoiceOver hears what the glow shows. Nothing for the other.
    private func spokenTurn(isMe: Bool) -> Text {
        guard isActive(isMe: isMe), let spoken = turn.spoken(partnerName: partnerName) else {
            return Text(verbatim: "")
        }
        return Text(spoken)
    }
}

/// An avatar with their mark in a small badge at the bottom trailing edge. It
/// glows in the player's piece color on their turn and grows a little. A green
/// dot at the top trailing edge shows the player has the game open.
struct BoardGamePlayerAvatar: View {
    let player: BoardGamePlayerInfo
    let glow: BoardGameGlowState
    var isHere = false
    var size: CGFloat = 44

    private static let badgeSize: CGFloat = 20
    private static let activeScale: CGFloat = 1.1

    var body: some View {
        BoardGameAvatar(player: player, size: size)
            .background { BoardGameGlow(color: player.style.color, state: glow) }
            .overlay(alignment: .bottomTrailing) {
                badge.offset(x: 4, y: 4)
            }
            .overlay(alignment: .topTrailing) {
                if isHere {
                    BoardGamePresenceDot(size: 12)
                        .overlay {
                            Circle().strokeBorder(.paeoniaBackgroundSecondary, lineWidth: PaeoniaRadius.strokeEmphasis)
                        }
                        .offset(x: 2, y: -2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(glow == .resting ? 1 : Self.activeScale)
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

/// A soft glow behind the avatar in the player's piece color. It breathes on the
/// player's turn, stays lit for the winner, and is gone otherwise.
private struct BoardGameGlow: View {
    let color: Color
    let state: BoardGameGlowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the glow reaches past the avatar before the blur.
    private static let spread: CGFloat = 6
    private static let blur: CGFloat = 12

    var body: some View {
        ZStack {
            switch state {
            case .resting:
                EmptyView()
            case .steady:
                glow(opacity: BoardGameGlowPulse.high)
                    .transition(.opacity)
            case .breathing:
                breathing
            }
        }
        .animation(PaeoniaMotion.stateChange, value: state)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var breathing: some View {
        if reduceMotion {
            glow(opacity: BoardGameGlowPulse.still)
                .transition(.opacity)
        } else {
            TimelineView(.animation) { timeline in
                glow(opacity: BoardGameGlowPulse.opacity(at: timeline.date.timeIntervalSinceReferenceDate))
            }
            .transition(.opacity)
        }
    }

    private func glow(opacity: Double) -> some View {
        Circle()
            .fill(color)
            .padding(-Self.spread)
            .blur(radius: Self.blur)
            .opacity(opacity)
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
