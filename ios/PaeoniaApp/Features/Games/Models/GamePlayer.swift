import Foundation

extension GameParticipants {
    /// Both people as the avatars show them.
    var players: (me: GamePlayer, partner: GamePlayer) {
        (
            GamePlayer(name: currentName, photoAssetID: currentPhotoAssetID),
            GamePlayer(name: partnerName, photoAssetID: partnerPhotoAssetID)
        )
    }
}

/// A person as the avatars show them.
nonisolated struct GamePlayer: Equatable, Sendable {
    var name: String
    var photoAssetID: UUID?
}
