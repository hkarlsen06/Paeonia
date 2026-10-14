import SwiftUI

/// Both players. My avatar is on the leading side, my partner's on the trailing
/// side. Whoever's turn it is, or whoever won, gets a lit ring and a bold name in
/// their piece color. At accessibility text sizes the row stacks.
struct BoardGamePlayersRow: View {
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let turn: BoardGameTurnLabel
    let partnerName: String

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
            BoardGamePlayerAvatar(player: player, ring: ringState(isMe: isMe), size: Self.avatarSize)
            styledName(for: player, isMe: isMe)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name(isMe: isMe))
        .accessibilityValue(spokenTurn(isMe: isMe))
        .frame(width: Self.columnWidth)
    }

    /// Avatar beside name, for accessibility text sizes.
    private func row(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            BoardGamePlayerAvatar(player: player, ring: ringState(isMe: isMe), size: Self.avatarSize)
            styledName(for: player, isMe: isMe)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name(isMe: isMe))
        .accessibilityValue(spokenTurn(isMe: isMe))
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

    /// The name, bold and in the piece color while it is this player's turn or they won.
    private func styledName(for player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        let active = isActive(isMe: isMe)
        return name(isMe: isMe)
            .font(PaeoniaTypography.caption.weight(active ? .bold : .regular))
            .foregroundStyle(active ? player.style.color : .paeoniaTextSecondary)
    }

    /// "Your turn", "[Name]'s turn", "You won" or "[Name] won" for the active
    /// player, so VoiceOver hears what the lit ring shows. Nothing for the other.
    private func spokenTurn(isMe: Bool) -> Text {
        guard isActive(isMe: isMe), let spoken = turn.spoken(partnerName: partnerName) else {
            return Text(verbatim: "")
        }
        return Text(spoken)
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
                partnerName: BoardGamePreviewData.partner.name
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
        partnerName: BoardGamePreviewData.partner.name
    )
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
#endif
