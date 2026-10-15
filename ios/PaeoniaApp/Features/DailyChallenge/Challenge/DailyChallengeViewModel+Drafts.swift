import Foundation
#if DEBUG
import OSLog
#endif

extension DailyChallengeViewModel {
    /// Whether anything is typed, picked, or staged for a question, whether or not it
    /// can be sent yet. Skipping throws the draft away, so Skip stays off while this
    /// is true, even when the text is too long to send.
    func hasDraftContent(for questionID: UUID) -> Bool {
        answerDrafts[questionID]?.hasContent == true || isPreparingPhoto(for: questionID)
    }

    /// Whether the draft text is past the length the backend accepts. The composer
    /// shows a counter and keeps Send off until it's shortened.
    func isDraftTextTooLong(for questionID: UUID) -> Bool {
        DailyAnswerDraft.measuredLength(of: draftText(for: questionID)) > DailyAnswerDraft.maxTextLength
    }

    /// The trimmed draft text for a question, or nil when it's empty.
    func nonEmptyDraftText(for questionID: UUID) -> String? {
        let text = draftText(for: questionID).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Whether the current draft is complete enough to send — drives the flow's
    /// primary button and keeps Skip out of reach once an answer is in progress. A
    /// combined question needs only one of its parts filled in.
    func hasDraftToSubmit(for question: DailyChallengeQuestion) -> Bool {
        // While a picked photo is still being prepared, sending would leave it out.
        !isDraftTextTooLong(for: question.id)
            && !isPreparingPhoto(for: question.id)
            && draftHasRequiredParts(for: question)
    }

    /// Whether the draft holds what the question needs, ignoring length and photo
    /// preparation (see `hasDraftToSubmit`).
    private func draftHasRequiredParts(for question: DailyChallengeQuestion) -> Bool {
        let hasText = nonEmptyDraftText(for: question.id) != nil
        let hasMedia = answerDrafts[question.id]?.media != nil
        let hasChoice = partnerChoiceSelection(for: question.id) != nil

        if question.usesCombinedCompose {
            switch question.combinedSecondaryKind {
            case .photo: return hasText || hasMedia
            case .partnerChoice: return hasText || hasChoice
            default: return hasText
            }
        }

        switch composeKind(for: question) {
        case .photo, .voice: return hasMedia
        case .partnerChoice: return hasChoice
        case .text: return hasText
        default: return false
        }
    }

    /// The kind the user is composing with for a question, honouring an explicit
    /// choice when the question accepts more than one kind, otherwise its default.
    func composeKind(for question: DailyChallengeQuestion) -> DailyChallengeAnswerKind? {
        if let selected = answerDrafts[question.id]?.selectedKind,
           question.composableAnswerKinds.contains(selected) {
            return selected
        }
        return question.defaultComposableKind
    }

    func setComposeKind(_ kind: DailyChallengeAnswerKind, for questionID: UUID) {
        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.selectedKind = kind
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    func draftText(for questionID: UUID) -> String {
        answerDrafts[questionID]?.text ?? ""
    }

    func setDraftText(_ text: String, for questionID: UUID) {
        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.text = text
        answerDrafts[questionID] = draft
        scheduleDraftSave(for: questionID)
    }

    /// Typing changes the text on every keystroke, and saving rewrites the whole
    /// draft blob, so the save waits for a pause. `flushDraftPersistence()` saves
    /// right away when the screen closes or the app leaves the foreground.
    private func scheduleDraftSave(for questionID: UUID) {
        pendingDraftSaves[questionID]?.cancel()
        pendingDraftSaves[questionID] = Task { [weak self] in
            try? await Task.sleep(for: Self.draftSaveDelay)
            guard !Task.isCancelled else { return }
            self?.flushDraft(for: questionID)
        }
    }

    /// Saves every draft whose text is still waiting for its delayed save.
    func flushDraftPersistence() {
        for questionID in Array(pendingDraftSaves.keys) {
            flushDraft(for: questionID)
        }
    }

    private func flushDraft(for questionID: UUID) {
        guard pendingDraftSaves[questionID] != nil, let draft = answerDrafts[questionID] else {
            pendingDraftSaves[questionID] = nil
            return
        }
        persist(draft, for: questionID)
    }

    func partnerChoiceSelection(for questionID: UUID) -> UUID? {
        answerDrafts[questionID]?.partnerChoiceUserID
    }

    func setPartnerChoice(_ userID: UUID?, for questionID: UUID) {
        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.partnerChoiceUserID = userID
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    /// The bytes of a staged-but-not-yet-sent photo or voice note, for the composer's
    /// preview.
    func stagedMediaData(for questionID: UUID) -> Data? {
        guard answerDrafts[questionID]?.media != nil else { return nil }
        return mediaDraftStore.stagedMediaData(instanceID: questionID)
    }

    /// The recorded length of a staged voice note, for the composer's preview.
    func stagedVoiceDurationMs(for questionID: UUID) -> Int? {
        answerDrafts[questionID]?.media?.durationMs
    }

    /// Whether a picked photo is still being prepared for this question.
    func isPreparingPhoto(for questionID: UUID) -> Bool {
        photoStagingTokens[questionID] != nil
    }

    /// Compresses and stages a picked photo so it persists across reopen and is ready
    /// to upload. Selecting a photo also makes photo the chosen kind. Compressing a
    /// large photo takes a moment, so it runs off the main thread while the composer
    /// shows a spinner.
    func stagePhoto(_ imageData: Data, for questionID: UUID) async {
        let token = UUID()
        photoStagingTokens[questionID] = token
        let compressed = await Task.detached(priority: .userInitiated) {
            ImageCompressor.compress(imageData)
        }.value
        // A newer pick, a removal, a skip, or a different signed-in user replaced this
        // one while it was compressing.
        guard photoStagingTokens[questionID] == token else { return }
        photoStagingTokens[questionID] = nil

        guard let compressed else {
            #if DEBUG
            logger.error("Compressing the picked photo returned nil; cannot stage it")
            #endif
            notice = .photoFailed
            return
        }

        do {
            try mediaDraftStore.writeStagedMedia(compressed.data, instanceID: questionID)
        } catch {
            logFailure("Staging a photo on the device failed", error)
            notice = .photoFailed
            return
        }

        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.selectedKind = .photo
        draft.media = DailyAnswerMediaDraft(
            purpose: .photo,
            mimeType: compressed.mediaType,
            fileExtension: compressed.fileExtension,
            width: compressed.width,
            height: compressed.height,
            durationMs: nil
        )
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    /// The photo picker couldn't hand over the chosen photo (for example an iCloud
    /// photo that failed to download).
    func photoPickFailed() {
        notice = .photoFailed
    }

    /// Stages a recorded voice note so it persists across reopen and is ready to
    /// upload. Reads the recording's bytes off the temporary file.
    func stageVoice(url: URL, durationMs: Int, for questionID: UUID) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logFailure("Reading the recorded voice note off disk failed", error)
            notice = .voiceFailed
            return
        }

        do {
            try mediaDraftStore.writeStagedMedia(data, instanceID: questionID)
        } catch {
            logFailure("Staging a voice note on the device failed", error)
            notice = .voiceFailed
            return
        }
        try? FileManager.default.removeItem(at: url)

        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.selectedKind = .voice
        draft.media = DailyAnswerMediaDraft(
            purpose: .voice,
            mimeType: "audio/mp4",
            fileExtension: "m4a",
            width: nil,
            height: nil,
            durationMs: durationMs
        )
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    /// Discards a staged photo or voice note (the bytes and the draft reference),
    /// keeping the chosen kind so the composer stays on that kind.
    func removeStagedMedia(for questionID: UUID) {
        photoStagingTokens[questionID] = nil
        mediaDraftStore.removeStagedMedia(instanceID: questionID)
        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.media = nil
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    private func persist(_ draft: DailyAnswerDraft, for questionID: UUID) {
        // This write carries the current text, so a delayed save is not needed.
        pendingDraftSaves[questionID]?.cancel()
        pendingDraftSaves[questionID] = nil
        guard let currentUserID else { return }
        draftStore.setDraft(draft, for: questionID, userID: currentUserID)
    }

    func clearDraft(for questionID: UUID) {
        pendingDraftSaves[questionID]?.cancel()
        pendingDraftSaves[questionID] = nil
        answerDrafts[questionID] = nil
        if let currentUserID {
            draftStore.clearDraft(for: questionID, userID: currentUserID)
        }
    }

    /// The outbox puts an answer back into the drafts when the server refuses it for
    /// good, so nothing the user wrote is lost. Picks those up without touching drafts
    /// the user is editing now, and says the answer didn't go through.
    func restoreReturnedDrafts(for userID: UUID) {
        var returnedAny = false
        for (instanceID, draft) in draftStore.drafts(for: userID) where answerDrafts[instanceID] == nil {
            answerDrafts[instanceID] = draft
            returnedAny = true
        }
        if returnedAny {
            notice = .submitFailed
        }
    }
}
