import Foundation

/// The two partners as the streak sheet shows them. `partnerName` is the name this
/// person sees, nickname included.
struct StreakPeople: Equatable {
    var currentName: String
    var currentPhotoAssetID: UUID?
    var partnerName: String
    var partnerPhotoAssetID: UUID?
}

extension StreakPeople {
    init(_ participants: DailyChallengeParticipants) {
        self.init(
            currentName: participants.currentDisplayName?.trimmedNonEmpty
                ?? String(localized: .pairingCelebrationYouName),
            currentPhotoAssetID: participants.currentProfilePhotoAssetID,
            partnerName: participants.partnerName,
            partnerPhotoAssetID: participants.partnerProfilePhotoAssetID
        )
    }
}
