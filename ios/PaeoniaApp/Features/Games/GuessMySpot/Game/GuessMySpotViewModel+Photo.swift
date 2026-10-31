import Foundation
import UIKit

// The photos: reading a picked one into a draft, and loading the photo of the
// round on screen.
extension GuessMySpotViewModel {
    /// The longest side the screens decode a photo at.
    static let displayPixelSize = 2_048

    func photoDescriptionTarget(for round: RemoteGuessMySpotRound) -> MediaAlternativeTarget? {
        guard round.senderUserID == currentUserID,
              state?.currentRound?.id == round.id || state?.previousRound?.id == round.id else { return nil }
        return .guessMySpot(roundID: round.id)
    }

    // MARK: - Picking

    /// A photo tapped in the picker. It is read and stripped off the main actor,
    /// then the check opens with its spot, or with none.
    func pick(_ data: Data) async {
        guard phase == .send, !isPreparingPhoto, let owner = currentUserID,
              let couple = state?.coupleID ?? participants.coupleID,
              let storageTicket = draftStorageTicket else { return }
        draftRevision += 1
        let revision = draftRevision
        isPreparingPhoto = true
        draftReadFailed = false
        defer { if draftRevision == revision { isPreparingPhoto = false } }
        let homeArea = dependencies.guessMySpotHomeArea
        async let area = homeArea.homeArea(ownerUserID: owner, coupleID: couple)
        let prepared = await GuessMySpotPhotoReader.prepareAsync(data)
        guard draftLoadIsCurrent(owner: owner, couple: couple, revision: revision, ticket: storageTicket)
        else { return }
        guard let prepared else { pickFailed = true; return }
        async let preview = GuessMySpotPhotoPreview.jpeg(from: prepared.jpeg)
        let image = await decodeDraftPhoto(prepared.jpeg)
        let startingArea = prepared.spot == nil ? await area : nil
        let previewData = await preview
        guard draftLoadIsCurrent(owner: owner, couple: couple, revision: revision, ticket: storageTicket)
        else { return }
        guard let image else { pickFailed = true; return }
        draftStartArea = startingArea
        draft = GuessMySpotDraft(
            roundID: UUID(), photo: prepared, image: image, spot: prepared.spot, preview: previewData
        )
        persistCurrentDraft()
        sendLivePreview()
        namePlaceSoon()
    }

    /// Puts a refused send back on the check. The photo stays in the store under the
    /// refused round until the draft is sent or replaced, and goes out with a new round id.
    func restoreDraft(from send: GuessMySpotSendPayload, ownerUserID: UUID) async {
        guard let jpeg = dependencies.guessMySpotPhotos.photo(ownerUserID: ownerUserID, roundID: send.roundID) else {
            // Keep the authored text and send details if the file is temporarily unavailable.
            draftReadFailed = true
            return
        }
        guard let couple = state?.coupleID ?? participants.coupleID, let ticket = draftStorageTicket else { return }
        let revision = draftRevision
        async let preview = GuessMySpotPhotoPreview.jpeg(from: jpeg)
        let image = await decodeDraftPhoto(jpeg)
        let previewData = await preview
        guard let image, draft == nil,
              draftLoadIsCurrent(owner: ownerUserID, couple: couple, revision: revision, ticket: ticket)
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
            refusedRoundID: send.roundID,
            preview: previewData,
            accessibilityText: send.details.accessibilityText ?? ""
        )
        persistCurrentDraft()
        sendLivePreview()
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
