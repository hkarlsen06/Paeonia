import SwiftUI

/// Both players, and a capsule between them that slides toward whoever's turn it
/// is. My avatar is on the leading side, my partner's on the trailing side. At
/// accessibility text sizes the row stacks.
struct BoardGamePlayersRow: View {
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let turn: BoardGameTurnLabel
    let partnerName: String
    /// A quiet "Draw your mark" link under my avatar, while I have no mark.
    let showsDrawMarkLink: Bool
    let onDrawMark: () -> Void

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
        .animation(PaeoniaMotion.stateChange, value: showsDrawMarkLink)
    }

    // MARK: Layouts

    private var sideBySide: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
            column(for: me, isMe: true)
            BoardGameTurnCapsule(turn: turn, partnerName: partnerName)
                .padding(.horizontal, PaeoniaSpacing.space8)
                .frame(maxWidth: .infinity, minHeight: Self.avatarSize, alignment: turn.capsuleAlignment)
            column(for: partner, isMe: false)
        }
        .frame(maxWidth: .infinity)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            row(for: me, isMe: true)
            BoardGameTurnCapsule(turn: turn, partnerName: partnerName)
            row(for: partner, isMe: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Avatar over name, with the link under it.
    private func column(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            VStack(spacing: PaeoniaSpacing.space4) {
                BoardGamePlayerAvatar(player: player, ring: ringState(isMe: isMe), size: Self.avatarSize)
                name(isMe: isMe)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(isActive(isMe: isMe) ? .paeoniaTextPrimary : .paeoniaTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenName(isMe: isMe))
            if isMe, showsDrawMarkLink {
                drawMarkLink
            }
        }
        .frame(width: Self.columnWidth)
    }

    /// Avatar beside name, for accessibility text sizes.
    private func row(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            HStack(spacing: PaeoniaSpacing.space12) {
                BoardGamePlayerAvatar(player: player, ring: ringState(isMe: isMe), size: Self.avatarSize)
                name(isMe: isMe)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(isActive(isMe: isMe) ? .paeoniaTextPrimary : .paeoniaTextSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenName(isMe: isMe))
            if isMe, showsDrawMarkLink {
                drawMarkLink
            }
        }
    }

    // MARK: Pieces

    private func ringState(isMe: Bool) -> BoardGameRingState {
        turn.ringState(forMe: isMe)
    }

    private func isActive(isMe: Bool) -> Bool {
        ringState(isMe: isMe) != .resting
    }

    private func name(isMe: Bool) -> Text {
        isMe ? Text(.boardGamesPlayerYou) : Text(verbatim: partnerName)
    }

    /// "You, your turn" while it is my turn, otherwise just the name.
    private func spokenName(isMe: Bool) -> Text {
        isMe && turn == .yourTurn ? Text(.boardGamesPlayerYourTurnA11Y) : name(isMe: isMe)
    }

    /// Small to look at, 44 points tall to tap. The negative padding gives the
    /// extra height back to the layout.
    private var drawMarkLink: some View {
        Button(action: onDrawMark) {
            Text(.boardGamesPlayersDrawMark)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                // One line, wider than the avatar above it if it needs to be.
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -PaeoniaSpacing.space12)
        .accessibilityIdentifier("boardGames.players.drawMark")
    }
}

/// "Your turn", "[Name]'s turn", "You won", "[Name] won" or "Draw".
private struct BoardGameTurnCapsule: View {
    let turn: BoardGameTurnLabel
    let partnerName: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(turn.text(partnerName: partnerName))
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(textColor)
            // The stacked layout has the full width, so the turn never ends in "…" there.
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .background(fillColor, in: Capsule(style: .continuous))
            .contentTransition(.opacity)
            .accessibilityIdentifier("boardGames.turn")
    }

    private var fillColor: Color {
        turn == .yourTurn ? .paeoniaAccentPrimary : .paeoniaSurfaceSecondary
    }

    private var textColor: Color {
        turn == .yourTurn ? .paeoniaTextInverse : .paeoniaTextPrimary
    }
}

/// An avatar with a ring in the player's piece color and their mark in a small
/// badge at the bottom trailing edge.
struct BoardGamePlayerAvatar: View {
    let player: BoardGamePlayerInfo
    let ring: BoardGameRingState
    var size: CGFloat = 44

    private static let badgeSize: CGFloat = 20

    var body: some View {
        BoardGameAvatar(player: player, size: size)
            .overlay { BoardGameRing(color: player.style.color, state: ring) }
            .overlay(alignment: .bottomTrailing) {
                badge.offset(x: 4, y: 4)
            }
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

/// A ring just outside the avatar. It rests faintly, glows and fades on the
/// player's turn, and stays lit for the winner.
private struct BoardGameRing: View {
    let color: Color
    let state: BoardGameRingState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let lineWidth: CGFloat = 2
    private static let outset: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().strokeBorder(color.opacity(0.28), lineWidth: Self.lineWidth)
            switch state {
            case .resting:
                EmptyView()
            case .steady:
                glow(opacity: BoardGameRingPulse.high)
                    .transition(.opacity)
            case .breathing:
                breathing
            }
        }
        .padding(-Self.outset)
        .animation(PaeoniaMotion.stateChange, value: state)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var breathing: some View {
        if reduceMotion {
            glow(opacity: BoardGameRingPulse.still)
                .transition(.opacity)
        } else {
            TimelineView(.animation) { timeline in
                glow(opacity: BoardGameRingPulse.opacity(at: timeline.date.timeIntervalSinceReferenceDate))
            }
            .transition(.opacity)
        }
    }

    private func glow(opacity: Double) -> some View {
        Circle()
            .strokeBorder(color, lineWidth: Self.lineWidth)
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
                showsDrawMarkLink: turn == .yourTurn,
                onDrawMark: {}
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
        showsDrawMarkLink: true,
        onDrawMark: {}
    )
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
#endif
