import SwiftUI

/// One partner's avatar. Colors are fixed: the first partner color for me, the
/// second for the partner.
struct DrawAndGuessAvatar: View {
    let player: DrawAndGuessPlayer
    let isMe: Bool
    let size: CGFloat

    var body: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: player.photoAssetID,
            name: player.name,
            tint: isMe ? .paeoniaPartnerOne : .paeoniaPartnerTwo,
            size: size
        )
    }
}

/// The score as the couple's play style shows it, in a capsule that takes no taps.
struct DrawAndGuessScoreCapsule: View {
    let score: DrawAndGuessScore
    let me: DrawAndGuessPlayer
    let partner: DrawAndGuessPlayer

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            switch score {
            case let .together(total):
                Image(systemName: "heart.fill")
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
                Text(.gamesDrawAndGuessPoints(total))
            case let .against(mine, theirs):
                HStack(spacing: PaeoniaSpacing.space4) {
                    DrawAndGuessAvatar(player: me, isMe: true, size: 22)
                    Text(verbatim: "\(mine)")
                }
                HStack(spacing: PaeoniaSpacing.space4) {
                    DrawAndGuessAvatar(player: partner, isMe: false, size: 22)
                    Text(verbatim: "\(theirs)")
                }
            }
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(horizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space4)
        .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("draw.score")
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

    private var accessibilityText: Text {
        switch score {
        case let .together(total):
            Text(.gamesDrawAndGuessScoreTogetherA11Y(String(localized: .gamesDrawAndGuessPoints(total))))
        case let .against(mine, theirs):
            Text(.gamesDrawAndGuessScoreAgainstA11Y(
                String(localized: .gamesDrawAndGuessPoints(mine)),
                partner.name,
                String(localized: .gamesDrawAndGuessPoints(theirs))
            ))
        }
    }
}

extension View {
    /// The score capsule in the trailing toolbar. At accessibility text sizes it
    /// moves into the content instead (see `DrawAndGuessScoreHeader`).
    func drawAndGuessScoreToolbar(_ viewModel: DrawAndGuessViewModel) -> some View {
        modifier(DrawAndGuessScoreToolbar(viewModel: viewModel))
    }
}

private struct DrawAndGuessScoreToolbar: ViewModifier {
    let viewModel: DrawAndGuessViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.toolbar {
            if let score = viewModel.score, !dynamicTypeSize.isAccessibilitySize {
                ToolbarItem(placement: .topBarTrailing) {
                    DrawAndGuessScoreCapsule(score: score, me: viewModel.me, partner: viewModel.partner)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}

/// The score on the first line of the content, only at accessibility text sizes.
struct DrawAndGuessScoreHeader: View {
    let viewModel: DrawAndGuessViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize, let score = viewModel.score {
            DrawAndGuessScoreCapsule(score: score, me: viewModel.me, partner: viewModel.partner)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
