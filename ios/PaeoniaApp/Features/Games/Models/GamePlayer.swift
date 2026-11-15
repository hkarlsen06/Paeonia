import Foundation

extension GameParticipants {
    /// Both people as the avatars show them.
    var players: (me: GamePlayer, partner: GamePlayer) {
        (
            GamePlayer(name: currentName, photoAssetID: currentPhotoAssetID, sharedName: currentSharedName),
            GamePlayer(name: partnerName, photoAssetID: partnerPhotoAssetID, sharedName: partnerSharedName)
        )
    }
}

/// A person as the avatars show them.
nonisolated struct GamePlayer: Equatable, Sendable {
    var name: String
    var photoAssetID: UUID?
    /// The person's own name, never a nickname, for a picture that leaves the app,
    /// such as a shared drawing. Nil when it is not known.
    var sharedName: String?
}
