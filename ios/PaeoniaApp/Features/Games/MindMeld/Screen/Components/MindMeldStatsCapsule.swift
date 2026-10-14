import SwiftUI

/// How many times the couple has melded, in a capsule that takes no taps, on the
/// hub card. Callers show it only when `melds` is above zero.
struct MindMeldStatsCapsule: View {
    let melds: Int

    var body: some View {
        // An HStack, not a Label: the toolbar shows a Label as its icon only.
        HStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: "camera.macro")
                .gameCapsuleIconStyle()
                .accessibilityHidden(true)
            Text(.mindMeldStatsMelds(melds))
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space4)
        .gameCapsuleStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.mindMeldStatsMeldsA11Y(melds)))
        .accessibilityIdentifier("mindMeld.stats")
    }
}

/// The couple's melds in the toolbar of the game screen: both avatars, slightly
/// overlapping, and the count, in the same capsule as the other games' scores.
/// Tapping it opens "Our melds". It shows at 0 melds too, because it is the way
/// to "Our melds".
struct MindMeldMeldsLink: View {
    let melds: Int
    let me: MindMeldPlayer
    let partner: MindMeldPlayer

    private static let avatarSize: CGFloat = 22

    var body: some View {
        NavigationLink(value: GamesDestination.mindMeldHistory) {
            HStack(spacing: PaeoniaSpacing.space4) {
                HStack(spacing: -PaeoniaSpacing.space8) {
                    avatar(me, tint: .paeoniaPartnerOne)
                    avatar(partner, tint: .paeoniaPartnerTwo)
                }
                Text(verbatim: "\(melds)")
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.paeoniaTextPrimary)
            // The leading avatar is concentric with the capsule's end.
            .padding(.leading, PaeoniaSpacing.space4)
            .padding(.trailing, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space4)
            .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.mindMeldHistoryTitle))
            .accessibilityValue(Text(.mindMeldStatsMeldsA11Y(melds)))
        }
        .buttonStyle(.plain)
        // The capsule stays one line in the toolbar.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier("mindMeld.history.open")
    }

    /// A ring in the capsule's color separates the overlapping circles.
    private func avatar(_ player: MindMeldPlayer, tint: Color) -> some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: player.photoAssetID,
            name: player.name,
            tint: tint,
            size: Self.avatarSize
        )
        .background(Circle().fill(.paeoniaSurfaceSecondary).padding(-2))
    }
}

#if DEBUG
#Preview {
    VStack(spacing: PaeoniaSpacing.space16) {
        MindMeldStatsCapsule(melds: 1)
        MindMeldStatsCapsule(melds: 12)
        MindMeldMeldsLink(
            melds: 3,
            me: MindMeldPlayer(name: "Alex", photoAssetID: nil),
            partner: MindMeldPlayer(name: "Robin", photoAssetID: nil)
        )
    }
    .padding()
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
