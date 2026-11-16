import Foundation

extension MemoriesViewModel {
    /// Replaces the new-memory form contents and saves them for the signed-in user. An
    /// empty draft removes the saved one, which is how Cancel discards a draft.
    ///
    /// Typing saves after a short pause, because each save rewrites the stored draft.
    /// Adding or removing a photo or video, and emptying the draft, save right away.
    func updateDraft(_ newDraft: MemoryDraft) {
        guard newDraft != draft else { return }
        let changesMediaOrEmpties = newDraft.media != draft.media || newDraft.isEmpty
        draft = newDraft
        draftNeedsSaving = true
        if changesMediaOrEmpties {
            saveDraftNow()
        } else {
            scheduleDraftSave()
        }
    }

    /// Siri brought photos from another app for a new memory. They join the new-memory draft,
    /// which keeps whatever the person had started, and the Memories screen opens the form.
    /// Before the tab has loaded `userID`'s draft, the photos go into the stored draft, which
    /// the tab then loads.
    func startNewMemory(adding photos: [Data], for userID: UUID?) {
        guard let userID else { return }
        let added = MemoryDraftMedia.photos(photos)
        if currentUserID == userID, draftFailure == .read {
            pendingImportedPhotos[userID, default: []] += added
        } else if currentUserID == userID {
            var next = draft
            next.media += added
            updateDraft(next)
        } else {
            do {
                var stored = try draftStore.draft(for: userID) ?? MemoryDraft()
                stored.media += added
                try draftStore.setDraft(stored, for: userID)
            } catch {
                // Keep the incoming images in this model and surface the failure.
                // Configuration for this user must not replace them with an older draft.
                pendingImportedPhotos[userID, default: []] += added
                notice = .draftSaveFailed
            }
        }
        isNewMemoryRequested = true
    }

    /// Saves typed text that is still waiting for its delayed save. Call when the form
    /// closes or the app leaves the foreground.
    func flushDraft() {
        guard draftNeedsSaving else { return }
        saveDraftNow()
    }

    func restoreDraft() {
        draft = MemoryDraft()
        draftNeedsSaving = false
        draftFailure = nil
        guard let currentUserID else { return }
        do {
            draft = try draftStore.draft(for: currentUserID) ?? MemoryDraft()
            if let imported = pendingImportedPhotos.removeValue(forKey: currentUserID) {
                draft.media += imported
                draftNeedsSaving = true
                saveDraftNow()
            }
        } catch {
            draftFailure = .read
            logFailure("Restoring a memory draft failed", error)
        }
    }

    func discardDraft() {
        guard let currentUserID else { return }
        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        draftStore.clearDraft(for: currentUserID)
        MemoryDraftMedia.deleteVideoFiles(of: draft.media)
        draft = MemoryDraft()
        draftFailure = nil
        draftNeedsSaving = false
        pendingImportedPhotos[currentUserID] = nil
    }

    private func scheduleDraftSave() {
        pendingDraftSave?.cancel()
        pendingDraftSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveDraftNow()
        }
    }

    func saveDraftNow() {
        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        guard let currentUserID else { return }
        guard draftFailure != .read else { return }
        do {
            try draftStore.setDraft(draft, for: currentUserID)
            draftNeedsSaving = false
            draftFailure = nil
        } catch {
            draftNeedsSaving = true
            draftFailure = .write
            notice = .draftSaveFailed
            logFailure("Saving a memory draft failed", error)
        }
    }
}

extension MemoriesViewModel {
    func addMedia(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        guard !edit.newMedia.isEmpty else { return .unchanged }
        let coupleID = latest.snapshot.coupleID
        guard let uploaded = await mediaUploads.upload(
            edit.newMedia,
            coupleID: coupleID,
            ownerUserID: userID,
            startingSortOrder: (latest.snapshot.media.map(\.sortOrder).max() ?? 0) + 1,
            attachedMediaAssetIDs: Set(latest.snapshot.visibleMediaAssetIDs)
        ) else {
            notice = .photoUploadFailed
            return .failed
        }
        let visibleIDs = Set(latest.snapshot.media.filter(\.isVisible).map(\.memoryMediaID))
        let remaining = uploaded.filter { !visibleIDs.contains($0.memoryMediaID) }
        guard !remaining.isEmpty else {
            finishUploads(of: edit.newMedia)
            return .unchanged
        }
        let attached = await perform(
            "Attaching photos to a memory failed", notice: .photoUploadFailed, memoryID: latest.snapshot.memoryID
        ) {
            _ = try await self.memoryService.attachMemoryMedia(
                ownerUserID: userID,
                memoryID: latest.snapshot.memoryID,
                optimisticMedia: remaining,
                operation: self.operationProvider.makeOperation()
            )
        }
        guard attached else { return .failed }
        finishUploads(of: edit.newMedia)
        return .saved
    }

    /// Forgets the sent uploads and deletes the sent videos' files. Before the memory has them,
    /// a retry may still need both.
    func finishUploads(of media: [MemoryDraftMedia]) {
        mediaUploads.reset()
        MemoryDraftMedia.deleteVideoFiles(of: media)
    }
}
