import Foundation

extension DailyChallengeViewModel {
    /// Queued answers are already durable locally, so the answering flow should
    /// not wait for sync before moving on to the next question.
    private func syncQueuedAnswerInBackground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await localChangeSyncHandler?()
            await reload()
        }
    }

    /// Sends the user's answer for a question, resolving the kind(s) from the draft.
    /// Every kind is saved on the device first and sent in the background, so a
    /// network blip never loses what the user wrote. Questions that allow a photo or
    /// partner pick *alongside* text send whatever the user filled in, together.
    func submitAnswer(for question: DailyChallengeQuestion) async {
        guard submittingQuestionID == nil, let currentUserID else { return }
        // The composer's counter already shows this; the backend would reject it.
        guard !isDraftTextTooLong(for: question.id) else { return }
        // The couple's day ended while this was open (offline, or before the live
        // update arrived). The server only takes your own answers made during their
        // day, so a queued one would never send.
        if question.origin == .own, !question.isTopicQuestion, question.endsAt <= now() {
            endCurrentDayIfNeeded()
            notice = .dayEnded
            Task { await reload() }
            return
        }

        guard let outgoing = resolveOutgoingAnswer(for: question) else {
            notice = .emptyAnswer
            return
        }

        await enqueueAnswer(outgoing, for: question, currentUserID: currentUserID)
    }

    private typealias OutgoingAnswer = (
        content: DailySubmitAnswerOperationPayload.Content,
        sending: SendingAnswer
    )

    /// Resolves the draft into the answer to queue and its "saved, sending" preview,
    /// or nil when there's nothing to send. Combined questions fold text together with
    /// a photo or partner pick; everything else stays single-kind.
    private func resolveOutgoingAnswer(for question: DailyChallengeQuestion) -> OutgoingAnswer? {
        let text = nonEmptyDraftText(for: question.id)
        if question.usesCombinedCompose {
            return resolveCombinedAnswer(for: question, text: text)
        }
        return resolveSingleKindAnswer(for: question, text: text)
    }

    private func resolveCombinedAnswer(for question: DailyChallengeQuestion, text: String?) -> OutgoingAnswer? {
        switch question.combinedSecondaryKind {
        case .photo:
            if let media = stagedMediaParts(for: question) {
                if let text {
                    return (.textAndMedia(text, media.payload), SendingAnswer(text: text, media: media.sending))
                }
                return (.media(media.payload), SendingAnswer(media: media.sending))
            }
            return textOnly(text)
        case .partnerChoice:
            if let choice = partnerChoiceSelection(for: question.id) {
                if let text {
                    return (
                        .textAndPartnerChoice(text, choice),
                        SendingAnswer(text: text, partnerChoiceUserID: choice)
                    )
                }
                return (.partnerChoice(choice), SendingAnswer(partnerChoiceUserID: choice))
            }
            return textOnly(text)
        case .eitherOr:
            return resolvePick(for: question, why: text)
        default:
            return nil
        }
    }

    /// A pick-one-of-two answer, with its why line when one is written.
    private func resolvePick(for question: DailyChallengeQuestion, why text: String?) -> OutgoingAnswer? {
        guard let option = optionChoiceSelection(for: question.id) else { return nil }
        if let text {
            return (.textAndOptionChoice(text, option), SendingAnswer(text: text, optionChoice: option))
        }
        return (.optionChoice(option), SendingAnswer(optionChoice: option))
    }

    private func resolveSingleKindAnswer(for question: DailyChallengeQuestion, text: String?) -> OutgoingAnswer? {
        switch composeKind(for: question) {
        case .photo, .voice:
            guard let media = stagedMediaParts(for: question) else { return nil }
            return (.media(media.payload), SendingAnswer(media: media.sending))
        case .partnerChoice:
            guard let choice = partnerChoiceSelection(for: question.id) else { return nil }
            return (.partnerChoice(choice), SendingAnswer(partnerChoiceUserID: choice))
        case .eitherOr:
            return resolvePick(for: question, why: nil)
        case .text:
            return textOnly(text)
        default:
            return nil
        }
    }

    /// A text-only outgoing answer, or nil when there's no text.
    private func textOnly(_ text: String?) -> OutgoingAnswer? {
        guard let text else { return nil }
        return (.text(text), SendingAnswer(text: text))
    }

    /// Builds the queue and preview parts for a staged photo/voice draft, with fresh
    /// reserve/finalize operations fixed in the payload so retries stay idempotent.
    private func stagedMediaParts(
        for question: DailyChallengeQuestion
    ) -> (payload: DailySubmitAnswerOperationPayload.Media, sending: SendingAnswer.Media)? {
        guard
            let media = answerDrafts[question.id]?.media,
            let stagedData = mediaDraftStore.stagedMediaData(instanceID: question.id)
        else { return nil }

        let payload = DailySubmitAnswerOperationPayload.Media(
            draft: media,
            coupleID: question.coupleID,
            reserveOperation: operationProvider.makeOperation(),
            finalizeOperation: operationProvider.makeOperation(),
            stagedData: stagedData
        )
        return (payload, SendingAnswer.Media(draft: media, stagedData: stagedData))
    }

    /// Saves the resolved answer on the device and queues it for sending, then nudges
    /// the sync engine to send it now if we're online (it retries in the background
    /// otherwise). Local-first: a transient failure never surfaces an error — the
    /// queued answer is sent when it can be. Staged media bytes stay on disk for the
    /// upload; the handler clears them once it lands.
    private func enqueueAnswer(
        _ outgoing: OutgoingAnswer,
        for question: DailyChallengeQuestion,
        currentUserID: UUID
    ) async {
        submittingQuestionID = question.id
        let operationPayload = DailySubmitAnswerOperationPayload(
            instanceID: question.id,
            answerID: UUID(),
            content: outgoing.content,
            topicQuestionID: question.isTopicQuestion ? question.questionID : nil
        )

        do {
            try await pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: currentUserID,
                    operation: operationProvider.makeOperation(),
                    operationKind: .submitDailyAnswer,
                    idempotencyScope: "daily-answer:\(question.id.uuidString.lowercased())",
                    requestData: try encoder.encode(operationPayload)
                )
            )
        } catch {
            logFailure("Saving an answer to send failed", error)
            notice = .submitFailed
            submittingQuestionID = nil
            return
        }

        // Shown as sending right away; the queued operation now carries the answer, so
        // the editable draft can go (staged media stays on disk for the upload).
        sendingAnswers[question.id] = outgoing.sending
        sendingGeneration += 1
        hasSentAnswer = true
        clearDraft(for: question.id)
        submittingQuestionID = nil
        syncQueuedAnswerInBackground()
    }

    /// Saves an edit to an answer the user already sent. Only allowed while the
    /// answer is still private; the backend rejects it once the partner has
    /// answered, which surfaces as a clear, non-retryable notice.
    func editTextAnswer(for question: DailyChallengeQuestion) async {
        guard
            question.editableAnswerKind == .text,
            submittingQuestionID == nil,
            shufflingSlotNumber == nil,
            !isDraftTextTooLong(for: question.id)
        else { return }

        let answerText = draftText(for: question.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answerText.isEmpty else {
            notice = .emptyAnswer
            return
        }

        submittingQuestionID = question.id
        do {
            _ = try await service.editTextAnswer(
                instanceID: question.id,
                text: answerText,
                operation: operationProvider.makeOperation()
            )
            // Keep the draft equal to the saved text so the field reflects it and
            // Save disables again until the next change.
            setDraftText(answerText, for: question.id)
            await reload()
        } catch is DailyChallengeEditLockedError {
            notice = .editLocked
            await reload()
        } catch {
            if !error.isCancellation {
                logFailure("Saving a text answer edit failed", error)
                notice = .editFailed
            }
        }
        submittingQuestionID = nil
    }

    /// Saves a changed partner-choice answer. Like the text edit, this is only
    /// allowed while the answer is still private; the backend locks it once the
    /// partner has answered, which surfaces as a clear, non-retryable notice.
    func editPartnerChoiceAnswer(for question: DailyChallengeQuestion) async {
        guard
            question.editableAnswerKind == .partnerChoice,
            submittingQuestionID == nil,
            shufflingSlotNumber == nil
        else { return }

        guard let selection = partnerChoiceSelection(for: question.id) else {
            notice = .emptyAnswer
            return
        }

        submittingQuestionID = question.id
        do {
            _ = try await service.editPartnerChoice(
                instanceID: question.id,
                selectedUserID: selection,
                operation: operationProvider.makeOperation()
            )
            // Keep the draft equal to the saved choice so Save disables again until
            // the next change.
            setPartnerChoice(selection, for: question.id)
            await reload()
        } catch is DailyChallengeEditLockedError {
            notice = .editLocked
            await reload()
        } catch {
            if !error.isCancellation {
                logFailure("Saving a partner-choice answer edit failed", error)
                notice = .editFailed
            }
        }
        submittingQuestionID = nil
    }

    /// Swaps one of the user's own, still-unanswered questions for a fresh one.
    /// The backend caps the number of swaps per day; when that cap is hit we show
    /// a calm, plain-language notice instead of a generic error.
    func shuffle(_ question: DailyChallengeQuestion) async {
        guard
            !question.isTopicQuestion,
            question.origin == .own,
            !question.hasOwnAnswer,
            !isSending(question.id),
            submittingQuestionID == nil,
            shufflingSlotNumber == nil,
            let currentUserID
        else { return }

        cancelInFlightReload()
        shufflingSlotNumber = question.slotNumber
        do {
            let result = try await service.shuffleQuestion(
                currentUserID: currentUserID,
                slotNumber: question.slotNumber,
                operation: operationProvider.makeOperation()
            )
            apply(result)
            hasResolvedTodayState = true
            // The skipped question is gone for good, so its private photo or voice
            // note shouldn't stay on the phone either.
            photoStagingTokens[question.id] = nil
            mediaDraftStore.removeStagedMedia(instanceID: question.id)
            clearDraft(for: question.id)
        } catch is DailyChallengeShuffleLimitError {
            notice = .shuffleLimitReached
        } catch {
            if !error.isCancellation {
                logFailure("Skipping (shuffling) a question failed", error)
                notice = .shuffleFailed(PaeoniaFailure(error))
            }
        }
        shufflingSlotNumber = nil
    }

    func isShuffling(_ question: DailyChallengeQuestion) -> Bool {
        shufflingSlotNumber == question.slotNumber
    }
}
