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
