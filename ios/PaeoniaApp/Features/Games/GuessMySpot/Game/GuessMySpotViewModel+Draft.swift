import Foundation

extension GuessMySpotViewModel {
    @discardableResult
    func persistCurrentDraft() -> Bool {
        guard let draft, let owner = currentUserID, let couple = state?.coupleID ?? participants.coupleID,
              let ticket = draftStorageTicket else { return false }
        let stored = GuessMySpotStoredDraft(
            roundID: draft.roundID, photo: draft.photo, spot: draft.spot, place: draft.place,
            refusedRoundID: draft.refusedRoundID, accessibilityText: draft.accessibilityText
        )
        do {
            let saved = try dependencies.guessMySpotPhotos.saveDraft(stored, ownerUserID: owner,
                                                                    coupleID: couple, ticket: ticket)
            if !saved { notice = .couldNotSaveMove }
            return saved
        } catch {
            notice = .couldNotSaveMove
            return false
        }
    }

    @discardableResult
    func discardStoredDraft(_ draft: GuessMySpotDraft, keepingPhoto: Bool) -> Bool {
        guard let owner = currentUserID, let couple = state?.coupleID ?? participants.coupleID else { return false }
        do {
            try dependencies.guessMySpotPhotos.discardDraft(
                roundID: draft.roundID, ownerUserID: owner, coupleID: couple, keepingPhoto: keepingPhoto
            )
            return true
        } catch {
            notice = .couldNotSaveMove
            return false
        }
    }

    func retryDraftRestore() async {
        restoredDraftScope = nil
        await restoreStoredDraftIfNeeded()
        if draft == nil { await showRefusedMoves() }
    }

    func restoreStoredDraftIfNeeded() async {
        guard phase == .send, draft == nil, !isPreparingPhoto, !isRestoringDraft,
              let owner = currentUserID, let couple = state?.coupleID ?? participants.coupleID,
              let ticket = draftStorageTicket else { return }
        let scope = "\(owner):\(couple)"
        guard restoredDraftScope != scope else { return }
        isRestoringDraft = true
        defer { isRestoringDraft = false }
        let revision = draftRevision
        do {
            guard let stored = try dependencies.guessMySpotPhotos.draft(ownerUserID: owner, coupleID: couple) else {
                restoredDraftScope = scope
                return
            }
            if pending.sends.contains(where: { $0.roundID == stored.roundID })
                || state?.currentRound?.id == stored.roundID || state?.previousRound?.id == stored.roundID {
                try dependencies.guessMySpotPhotos.discardDraft(
                    roundID: stored.roundID, ownerUserID: owner, coupleID: couple, keepingPhoto: true
                )
                restoredDraftScope = scope
                return
            }
            async let preview = GuessMySpotPhotoPreview.jpeg(from: stored.photo.jpeg)
            let image = await decodeDraftPhoto(stored.photo.jpeg)
            let previewData = await preview
            guard draft == nil, !isPreparingPhoto,
                  draftLoadIsCurrent(owner: owner, couple: couple, revision: revision, ticket: ticket) else { return }
            guard let image else { draftReadFailed = true; return }
            draft = GuessMySpotDraft(
                roundID: stored.roundID, photo: stored.photo, image: image, spot: stored.spot,
                place: stored.place, refusedRoundID: stored.refusedRoundID, preview: previewData,
                accessibilityText: stored.accessibilityText
            )
            restoredDraftScope = scope
            draftReadFailed = false
            sendLivePreview()
            if stored.place == nil { namePlaceSoon() }
        } catch {
            draftReadFailed = true
        }
    }

    /// A delayed decode cannot replace a newer pick/edit or recreate content after a purge.
    func draftLoadIsCurrent(owner: UUID, couple: UUID, revision: Int, ticket: GuessMySpotDraftTicket) -> Bool {
        !Task.isCancelled && phase == .send && draftRevision == revision
            && draftIdentityIsCurrent(owner: owner, couple: couple, ticket: ticket)
    }

    func draftIdentityIsCurrent(owner: UUID, couple: UUID, ticket: GuessMySpotDraftTicket) -> Bool {
        currentUserID == owner && (state?.coupleID ?? participants.coupleID) == couple
            && draftStorageTicket == ticket && dependencies.guessMySpotPhotos.draftTicket(ownerUserID: owner) == ticket
    }
}
