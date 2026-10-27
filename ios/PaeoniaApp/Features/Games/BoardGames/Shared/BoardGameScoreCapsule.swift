import SwiftUI

/// One player's profile photo in their piece color.
struct BoardGameAvatar: View {
    let player: BoardGamePlayerInfo
    let size: CGFloat

    var body: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: player.photoAssetID,
            name: player.name,
            tint: player.style.color,
            size: size
        )
    }
}

/// The score as the couple's play style shows it, in a capsule that takes no taps.
struct BoardGameScoreCapsule: View {
    let score: BoardGameScore
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            switch score {
            case let .together(games):
                Image(systemName: "heart.fill")
                    .gameCapsuleIconStyle()
                    .accessibilityHidden(true)
                Text(.boardGamesScoreGames(games))
            case let .against(mine, theirs):
                HStack(spacing: PaeoniaSpacing.space4) {
                    BoardGameAvatar(player: me, size: 22)
                    Text(verbatim: "\(mine)")
                }
                HStack(spacing: PaeoniaSpacing.space4) {
                    BoardGameAvatar(player: partner, size: 22)
                    Text(verbatim: "\(theirs)")
                }
            }
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .monospacedDigit()
        .padding(horizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space4)
        .gameCapsuleStyle()
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(score.spoken(partnerName: partner.name)))
        .accessibilityIdentifier("boardGames.score")
    }

    /// The leading avatar sits as far from the edge as from the top and bottom,
    /// so its circle is concentric with the capsule's end.
    private var horizontalPadding: EdgeInsets {
        switch score {
        case .together:
            EdgeInsets(top: 0, leading: PaeoniaSpacing.space12, bottom: 0, trailing: PaeoniaSpacing.space12)
        case .against:
            EdgeInsets(top: 0, leading: PaeoniaSpacing.space4, bottom: 0, trailing: PaeoniaSpacing.space8)
        }
    }
}

/// The score capsule, as a link to "Past games" when the game has them.
private struct BoardGameScoreLink: View {
    let score: BoardGameScore
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let history: GamesDestination?

    var body: some View {
        if let history {
            NavigationLink(value: history) {
                BoardGameScoreCapsule(score: score, me: me, partner: partner)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(.boardGamesHistoryTitle))
        } else {
            BoardGameScoreCapsule(score: score, me: me, partner: partner)
        }
    }
}

extension View {
    /// The score capsule in the trailing toolbar, once a game has finished. At
    /// accessibility text sizes it moves into the content instead (see `BoardGameScoreHeader`).
    /// With `history`, a tap on it opens "Past games".
    func boardGameScoreToolbar(
        score: BoardGameScore?,
        me: BoardGamePlayerInfo,
        partner: BoardGamePlayerInfo,
        history: GamesDestination? = nil
    ) -> some View {
        modifier(BoardGameScoreToolbar(score: score, me: me, partner: partner, history: history))
    }
}

private struct BoardGameScoreToolbar: ViewModifier {
    let score: BoardGameScore?
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let history: GamesDestination?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.toolbar {
            if let score, !score.isEmpty, !dynamicTypeSize.isAccessibilitySize {
                ToolbarItem(placement: .topBarTrailing) {
                    BoardGameScoreLink(score: score, me: me, partner: partner, history: history)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}

/// The score on the first line of the content, only at accessibility text sizes.
struct BoardGameScoreHeader: View {
    let score: BoardGameScore?
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    var history: GamesDestination?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize, let score, !score.isEmpty {
            BoardGameScoreLink(score: score, me: me, partner: partner, history: history)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview("Against each other") {
    VStack(spacing: PaeoniaSpacing.space16) {
        BoardGameScoreCapsule(
            score: .against(mine: 4, partner: 3),
            me: BoardGamePreviewData.me,
            partner: BoardGamePreviewData.partner
        )
        BoardGameScoreCapsule(
            score: .together(games: 12),
            me: BoardGamePreviewData.me,
            partner: BoardGamePreviewData.partner
        )
    }
    .padding()
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
