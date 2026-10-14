import SwiftUI

/// One partner's avatar. The colors are fixed, as in Draw & Guess: the first
/// partner color for me and the second for my partner.
struct StoryChainAvatar: View {
    let mediaAssetID: UUID?
    let name: String
    let isMe: Bool
    let size: CGFloat

    var body: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: mediaAssetID,
            name: name,
            tint: isMe ? .paeoniaPartnerOne : .paeoniaPartnerTwo,
            size: size
        )
    }
}

extension StoryChainAvatar {
    init(participants: GameParticipants, isMe: Bool, size: CGFloat) {
        self.init(
            mediaAssetID: isMe ? participants.currentPhotoAssetID : participants.partnerPhotoAssetID,
            name: isMe ? participants.currentName : participants.partnerName,
            isMe: isMe,
            size: size
        )
    }
}
