import Foundation

extension MemoriesViewModel {
    /// Replaces the new-memory form contents and saves them for the signed-in user. An
    /// empty draft removes the saved one, which is how Cancel discards a draft.
    ///
    /// Typing saves after a short pause, because each save rewrites the stored draft.
    /// Adding or removing a photo, and emptying the draft, save right away.
    func updateDraft(_ newDraft: MemoryDraft) {
        guard newDraft != draft else { return }
        let changesPhotosOrEmpties = newDraft.photos != draft.photos || newDraft.isEmpty
        draft = newDraft
        if changesPhotosOrEmpties {
            saveDraftNow()
        } else {
            scheduleDraftSave()
        }
    }

    /// Saves typed text that is still waiting for its delayed save. Call when the form
    /// closes or the app leaves the foreground.
    func flushDraft() {
        guard pendingDraftSave != nil else { return }
        saveDraftNow()
    }

    private func scheduleDraftSave() {
        pendingDraftSave?.cancel()
        pendingDraftSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveDraftNow()
        }
    }

    private func saveDraftNow() {
        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        guard let currentUserID else { return }
        draftStore.setDraft(draft, for: currentUserID)
    }
}

extension MemoriesViewModel {
    func addPhotos(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        guard !edit.newPhotos.isEmpty else { return .unchanged }
        let coupleID = latest.snapshot.coupleID
        guard let uploaded = await photoUploads.upload(
            MemoryDraftPhoto.photos(edit.newPhotos, descriptions: edit.photoDescriptions),
            coupleID: coupleID,
            ownerUserID: userID,
            startingSortOrder: (latest.snapshot.media.map(\.sortOrder).max() ?? 0) + 1
        ) else {
            notice = .photoUploadFailed
            return .failed
        }
        let attached = await perform("Attaching photos to a memory failed", notice: .photoUploadFailed) {
            _ = try await self.memoryService.attachMemoryMedia(
                ownerUserID: userID,
                memoryID: latest.snapshot.memoryID,
                optimisticMedia: uploaded,
                operation: self.operationProvider.makeOperation()
            )
        }
        guard attached else { return .failed }
        photoUploads.reset()
        return .saved
    }
}
