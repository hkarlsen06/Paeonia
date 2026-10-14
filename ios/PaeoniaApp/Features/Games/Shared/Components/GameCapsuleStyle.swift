import SwiftUI

extension EnvironmentValues {
    /// True inside the badge of a hub card, where a capsule sits on the card's picture.
    @Entry var gameCapsuleIsOnArtwork = false
}

/// The look of a game's score or count capsule. On a game screen it is a plum capsule
/// with light text. On a hub card's picture it turns blush with plum text, so it stands
/// out from any dark part of the painting at more than 3:1.
private struct GameCapsuleStyle: ViewModifier {
    @Environment(\.gameCapsuleIsOnArtwork) private var isOnArtwork

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isOnArtwork ? Color.paeoniaTextInverse : .paeoniaTextPrimary)
            .background(
                isOnArtwork ? Color.paeoniaTextPrimary : .paeoniaSurfaceSecondary,
                in: Capsule(style: .continuous)
            )
            .shadow(color: .paeoniaBackgroundSecondary.opacity(isOnArtwork ? 0.5 : 0), radius: 6, y: 2)
    }
}

/// The color of a small icon in a game capsule. Petal pink on the plum capsule, and the
/// deeper pink on the blush one, which keeps 3:1.
private struct GameCapsuleIconStyle: ViewModifier {
    @Environment(\.gameCapsuleIsOnArtwork) private var isOnArtwork

    func body(content: Content) -> some View {
        content.foregroundStyle(isOnArtwork ? Color.paeoniaAccentSecondary : .paeoniaAccentPrimary)
    }
}

extension View {
    /// The capsule's fill, text color, and shadow. Apply it after the padding.
    func gameCapsuleStyle() -> some View {
        modifier(GameCapsuleStyle())
    }

    /// The color of an icon inside a game capsule.
    func gameCapsuleIconStyle() -> some View {
        modifier(GameCapsuleIconStyle())
    }
}
