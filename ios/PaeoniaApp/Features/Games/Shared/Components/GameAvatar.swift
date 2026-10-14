import SwiftUI

/// One partner's avatar. Colors are fixed: the first partner color for me, the
/// second for the partner.
struct GameAvatar: View {
    let player: GamePlayer
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
