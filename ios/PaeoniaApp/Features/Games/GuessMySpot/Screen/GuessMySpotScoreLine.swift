import SwiftUI

/// The score counting up on the reveal. Together: both avatars and the shared total.
/// Against each other: each partner's own total, with the guesser's counting up.
/// This round's points stand beside the total that grows.
struct GuessMySpotScoreLine: View {
    let me: GamePlayer
    let partner: GamePlayer
    /// The score with this round's points in it.
    let score: GuessMySpotScore
    let guesserIsMe: Bool
    let points: Int
    /// How many of this round's points have counted up so far.
    let countedPoints: Int

    private var shown: GuessMySpotScore {
        score.counting(points: points, counted: countedPoints, guesserIsMe: guesserIsMe)
    }

    var body: some View {
        Group {
            switch shown {
            case let .together(total):
                HStack(spacing: PaeoniaSpacing.space12) {
                    HStack(spacing: -PaeoniaSpacing.space8) {
                        avatar(me, tint: .paeoniaPartnerOne)
                        avatar(partner, tint: .paeoniaPartnerTwo)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        totalLine(total, grows: true)
                        Text(.guessMySpotRevealPointsTogether)
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
            case let .against(mine, theirs):
                HStack(spacing: PaeoniaSpacing.space24) {
                    column(me, tint: .paeoniaPartnerOne, total: mine, grows: guesserIsMe)
                    column(partner, tint: .paeoniaPartnerTwo, total: theirs, grows: !guesserIsMe)
                }
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(GuessMySpotScoreCapsule.accessibilityText(score, partnerName: partner.name)))
    }

    private func column(_ player: GamePlayer, tint: Color, total: Int, grows: Bool) -> some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            avatar(player, tint: tint)
            totalLine(total, grows: grows)
        }
    }

    private func totalLine(_ total: Int, grows: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8) {
            Text(verbatim: GuessMySpotText.number(total))
                .font(PaeoniaTypography.title.monospacedDigit())
                .foregroundStyle(.paeoniaTextPrimary)
                .contentTransition(.numericText(value: Double(total)))
            if grows, points > 0 {
                Text(.guessMySpotRevealPoints(GuessMySpotText.number(points)))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .opacity(countedPoints > 0 ? 1 : 0)
            }
        }
    }

    private func avatar(_ player: GamePlayer, tint: Color) -> some View {
        PaeoniaProfilePhotoAvatar(mediaAssetID: player.photoAssetID, name: player.name, tint: tint, size: 32)
    }
}
