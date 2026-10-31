import SwiftUI

/// A recognizable portrait and its chosen artwork, independent of story controls or map placement.
struct PaeoniaDecoratedAvatar: View {
    let mediaAssetID: UUID?
    let name: String
    let tint: Color
    let size: CGFloat
    var decoration: AvatarDecoration = .none

    var body: some View {
        PaeoniaProfilePhotoAvatar(mediaAssetID: mediaAssetID, name: name, tint: tint, size: size)
            .overlay { AvatarDecorationArtwork(decoration: decoration, size: size) }
    }
}

/// Resolves a couple member's saved decoration and reserves room for its artwork.
struct PaeoniaCoupleAvatar: View {
    let mediaAssetID: UUID?
    let name: String
    let tint: Color
    let size: CGFloat
    let isCurrentUser: Bool

    @Environment(\.avatarStyling) private var avatarStyling

    private var decoration: AvatarDecoration {
        let decorations = avatarStyling?.decorations ?? CoupleAvatarDecorations()
        return isCurrentUser ? decorations.own : decorations.partner
    }

    var body: some View {
        PaeoniaDecoratedAvatar(
            mediaAssetID: mediaAssetID, name: name, tint: tint,
            size: size, decoration: decoration
        )
        .padding(size * decoration.outset)
    }
}
