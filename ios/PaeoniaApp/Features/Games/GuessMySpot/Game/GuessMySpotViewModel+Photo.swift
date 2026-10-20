import Foundation
import UIKit

// The photos: reading a picked one into a draft, and loading the photo of the
// round on screen.
extension GuessMySpotViewModel {
    /// The longest side the screens decode a photo at.
    static let displayPixelSize = 2_048

    // MARK: - Picking

    /// A photo tapped in the picker. It is read and stripped off the main actor,
    /// then the check opens with its spot, or with none.
    func pick(_ data: Data) async {
        guard phase == .send, !isPreparingPhoto else { return }
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        // Looked up while the photo is read, so a photo without a location opens near home.
        let homeArea = dependencies.guessMySpotHomeArea
        let owner = currentUserID
        let couple = state?.coupleID ?? participants.coupleID
        async let area: GuessMySpotArea? = if let owner {
            await homeArea.homeArea(ownerUserID: owner, coupleID: couple)
        } else {
            nil
        }
        guard let prepared = await GuessMySpotPhotoReader.prepareAsync(data),
              let image = await MemoryImageDecoding.downsample(prepared.jpeg, maxPixelSize: Self.displayPixelSize),
              phase == .send
        else {
            pickFailed = true
            return
        }
        draftStartArea = prepared.spot == nil ? await area : nil
        draft = GuessMySpotDraft(
            roundID: UUID(),
            photo: prepared,
            image: image,
            spot: prepared.spot
        )
        namePlaceSoon()
    }

    /// Puts a refused send back on the check. The photo stays in the store under the
    /// refused round until the draft is sent or replaced, and goes out with a new round id.
    func restoreDraft(from send: GuessMySpotSendPayload, ownerUserID: UUID) async {
        guard let jpeg = dependencies.guessMySpotPhotos.photo(ownerUserID: ownerUserID, roundID: send.roundID) else {
            await cache.forgetRefusedMove(roundID: send.roundID, ownerUserID: ownerUserID)
            return
        }
        guard let image = await MemoryImageDecoding.downsample(jpeg, maxPixelSize: Self.displayPixelSize),
              phase == .send, draft == nil
        else { return }
        draft = GuessMySpotDraft(
            roundID: UUID(),
            photo: GuessMySpotPreparedPhoto(
                jpeg: jpeg,
                width: send.width,
                height: send.height,
                spot: send.details.spot,
                takenOn: send.details.takenOn
            ),
            image: image,
            spot: send.details.spot,
            place: send.details.placeName.map {
                GuessMySpotPlace(name: $0, city: send.details.placeCity, countryCode: send.details.placeCountryCode)
            },
            refusedRoundID: send.roundID
        )
    }

    /// The refused send a draft put back is done with: sent again or replaced.
    func forgetRefusal(of draft: GuessMySpotDraft) async {
        guard let roundID = draft.refusedRoundID, let userID = currentUserID else { return }
        await cache.forgetRefusedMove(roundID: roundID, ownerUserID: userID)
        dependencies.guessMySpotPhotos.remove(ownerUserID: userID, roundID: roundID)
    }

    // MARK: - The round's photo

    /// Loads the photo of the round on screen when the round changes.
    func loadRoundPhotoIfNeeded() {
        let roundID = round?.id
        guard roundID != photoRoundID else { return }
        photoRoundID = roundID
        photoTask?.cancel()
        roundPhoto = nil
        roundPhotoFailed = false
        guard let round else { return }
        photoTask = Task { [weak self] in
            await self?.loadPhoto(of: round)
        }
    }

    /// "Try again" when the photo could not be fetched.
    func retryRoundPhoto() {
        guard let round, roundPhotoFailed else { return }
        roundPhotoFailed = false
        photoTask?.cancel()
        photoTask = Task { [weak self] in
            await self?.loadPhoto(of: round)
        }
    }

    private func loadPhoto(of round: RemoteGuessMySpotRound) async {
        let image = await photo(of: round)
        guard !Task.isCancelled, photoRoundID == round.id else { return }
        if let image {
            roundPhoto = image
        } else {
            roundPhotoFailed = true
        }
    }

    /// A photo this person sent and that is still on its way is on this phone.
    /// Every other photo comes through the shared media cache.
    func photo(of round: RemoteGuessMySpotRound) async -> UIImage? {
        var data: Data?
        if round.senderUserID == currentUserID, let userID = currentUserID {
            data = dependencies.guessMySpotPhotos.photo(ownerUserID: userID, roundID: round.id)
        }
        if data == nil {
            data = await dependencies.memoryPhotos?.imageData(for: round.photoMediaAssetID)
        }
        guard let data else { return nil }
        return await MemoryImageDecoding.downsample(data, maxPixelSize: Self.displayPixelSize)
    }
}
