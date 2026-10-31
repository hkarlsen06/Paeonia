import Foundation

nonisolated struct GuessMySpotStoredDraft: Equatable, Sendable {
    let roundID: UUID
    let photo: GuessMySpotPreparedPhoto
    let spot: GuessMySpotCoordinate?
    let place: GuessMySpotPlace?
    let refusedRoundID: UUID?
    let accessibilityText: String
}

nonisolated struct GuessMySpotDraftTicket: Equatable, Sendable {
    let generation: Int
    let privacy: LocalPrivacyWriteGuard.Token
}

/// The JPEG is immutable for a round and stored once beside this small record.
/// Typing or moving the pin rewrites only the private metadata, not the image.
nonisolated struct GuessMySpotDraftMetadata: Codable {
    let roundID: UUID
    let width: Int
    let height: Int
    let originalSpot: GuessMySpotCoordinate?
    let takenOn: String?
    let spot: GuessMySpotCoordinate?
    let place: GuessMySpotPlace?
    let refusedRoundID: UUID?
    let accessibilityText: String

    init(_ draft: GuessMySpotStoredDraft) {
        roundID = draft.roundID
        width = draft.photo.width
        height = draft.photo.height
        originalSpot = draft.photo.spot
        takenOn = draft.photo.takenOn
        spot = draft.spot
        place = draft.place
        refusedRoundID = draft.refusedRoundID
        accessibilityText = draft.accessibilityText
    }

    func draft(jpeg: Data) -> GuessMySpotStoredDraft {
        GuessMySpotStoredDraft(
            roundID: roundID,
            photo: GuessMySpotPreparedPhoto(
                jpeg: jpeg, width: width, height: height, spot: originalSpot, takenOn: takenOn
            ),
            spot: spot, place: place, refusedRoundID: refusedRoundID, accessibilityText: accessibilityText
        )
    }
}
