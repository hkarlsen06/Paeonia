import SwiftUI

/// Both avatars and the shared total counting up, with this round's points beside it.
struct ConsensioRevealScoreLine: View {
    let me: GamePlayer
    let partner: GamePlayer
    /// The total with this round's points in it.
    let sharedPoints: Int
    let points: Int
    /// How many of this round's points have counted up so far.
    let countedPoints: Int

    private var total: Int {
        max(0, sharedPoints - points + countedPoints)
    }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            HStack(spacing: -PaeoniaSpacing.space8) {
                avatar(me, tint: .paeoniaPartnerOne)
                avatar(partner, tint: .paeoniaPartnerTwo)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8) {
                    Text(verbatim: "\(total)")
                        .font(PaeoniaTypography.title.monospacedDigit())
                        .foregroundStyle(.paeoniaTextPrimary)
                        .contentTransition(.numericText(value: Double(total)))
                    if points > 0 {
                        Text(.consensioRevealPoints(points))
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaAccentPrimary)
                            .opacity(countedPoints > 0 ? 1 : 0)
                    }
                }
                Text(.consensioRevealPointsTogether)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.consensioPointsTogether(sharedPoints)))
    }

    private func avatar(_ player: GamePlayer, tint: Color) -> some View {
        PaeoniaProfilePhotoAvatar(mediaAssetID: player.photoAssetID, name: player.name, tint: tint, size: 32)
    }
}
