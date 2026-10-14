import SwiftUI

extension EnvironmentValues {
    /// True for the badge of a hub card, which floats over the card's painting.
    @Entry var gameCapsuleIsOnArtwork = false
}

/// The look of a game's score or count capsule. On a game screen it is a plum capsule
/// with light text. On a hub card it floats over the painting as Liquid Glass tinted deep
/// plum: the glass's light rim reads on the dark parts of a painting and its dark tint on
/// the bright ones, and the light text keeps more than 4.5:1 inside it.
private struct GameCapsuleStyle: ViewModifier {
    @Environment(\.gameCapsuleIsOnArtwork) private var isOnArtwork

    func body(content: Content) -> some View {
        if isOnArtwork {
            content
                .foregroundStyle(.paeoniaTextPrimary)
                .glassEffect(
                    .regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.75)),
                    in: Capsule(style: .continuous)
                )
        } else {
            content
                .foregroundStyle(.paeoniaTextPrimary)
                .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
        }
    }
}

extension View {
    /// The capsule's fill and text color. Apply it after the padding.
    func gameCapsuleStyle() -> some View {
        modifier(GameCapsuleStyle())
    }

    /// The color of an icon inside a game capsule.
    func gameCapsuleIconStyle() -> some View {
        foregroundStyle(.paeoniaAccentPrimary)
    }
}
