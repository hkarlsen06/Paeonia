import SwiftUI

/// The score in a small capsule, as the toolbar and the hub card show it: a heart
/// and the shared total, or each partner's avatar with their own total.
struct GuessMySpotScoreCapsule: View {
    let score: GuessMySpotScore
    let me: GamePlayer
    let partner: GamePlayer
    /// The hub card's glass capsule, or the toolbar's plain one.
    var onHub = false

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            switch score {
            case let .together(total):
                Image(systemName: "heart.fill")
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
                Text(verbatim: GuessMySpotText.number(total))
                    .contentTransition(.numericText(value: Double(total)))
            case let .against(mine, theirs):
                HStack(spacing: PaeoniaSpacing.space4) {
                    GameAvatar(player: me, isMe: true, size: 20)
                    Text(verbatim: GuessMySpotText.number(mine))
                }
                HStack(spacing: PaeoniaSpacing.space4) {
                    GameAvatar(player: partner, isMe: false, size: 20)
                    Text(verbatim: GuessMySpotText.number(theirs))
                }
            }
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(.leading, isAgainst ? PaeoniaSpacing.space4 : PaeoniaSpacing.space12)
        .padding(.trailing, isAgainst ? PaeoniaSpacing.space8 : PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space4)
        .modifier(CapsuleBackground(onHub: onHub))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.accessibilityText(score, partnerName: partner.name)))
    }

    private var isAgainst: Bool {
        if case .against = score { return true }
        return false
    }

    static func accessibilityText(_ score: GuessMySpotScore, partnerName: String) -> LocalizedStringResource {
        switch score {
        case let .together(total):
            .guessMySpotPointsTogether(total)
        case let .against(mine, theirs):
            .guessMySpotScoreAgainstA11Y(
                String(localized: .guessMySpotStatsPoints(mine)),
                partnerName,
                String(localized: .guessMySpotStatsPoints(theirs))
            )
        }
    }
}

private struct CapsuleBackground: ViewModifier {
    let onHub: Bool

    func body(content: Content) -> some View {
        if onHub {
            content.gameCapsuleStyle()
        } else {
            content.background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
        }
    }
}
