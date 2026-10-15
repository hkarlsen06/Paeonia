import Foundation

extension DailyChallengeViewModel {
    /// A still-sending answer, reconstructed from the queued operation so the "saved,
    /// sending" preview survives relaunch and clears once the send lands. Any
    /// combination can be present (e.g. a photo with a caption).
    struct SendingAnswer: Equatable {
        var text: String?
        var partnerChoiceUserID: UUID?
        var media: Media?
        /// A try to send it failed, so it may stay on this phone a while.
        var isHeldOnPhone = false

        struct Media: Equatable {
            let draft: DailyAnswerMediaDraft
            let stagedData: Data?
        }
    }

    /// Whether a question's answer is saved on the device and waiting to finish
    /// sending in the background. Once the snapshot carries the sent answer it reads
    /// from that instead, so a live update that lands the answer replaces the "saved,
    /// sending" preview right away rather than at the next full reload.
    func isSending(_ instanceID: UUID) -> Bool {
        guard sendingAnswers[instanceID] != nil else { return false }
        return snapshot.questions.first(where: { $0.id == instanceID })?.hasOwnAnswer != true
    }

    /// The text of a still-sending answer (a standalone text answer or the caption on
    /// a combined photo/choice answer). Nil when there's no text or it isn't sending.
    func sendingText(for instanceID: UUID) -> String? {
        sendingAnswers[instanceID]?.text
    }

    /// The chosen person's name for a still-sending partner-choice answer. Nil
    /// otherwise.
    func sendingPartnerChoiceName(for instanceID: UUID) -> String? {
        guard let userID = sendingAnswers[instanceID]?.partnerChoiceUserID else { return nil }
        return participants.name(for: userID)
    }

    /// The staged media bytes for a still-sending media answer, for its "saved,
    /// sending" preview. Reads the staged file first, then queued fallback bytes.
    /// Nil for answers without media.
    func sendingMediaData(for instanceID: UUID) -> Data? {
        guard let media = sendingAnswers[instanceID]?.media else { return nil }
        return mediaDraftStore.stagedMediaData(instanceID: instanceID) ?? media.stagedData
    }

    /// Everything a still-sending answer carries, for its "saved, sending" preview.
    /// Nil once it has landed and reads from the revealed answer instead.
    func sendingPreview(for question: DailyChallengeQuestion) -> DailySendingPreview? {
        guard isSending(question.id) else { return nil }
        return DailySendingPreview(
            mediaKind: question.mediaAnswerKind,
            mediaData: sendingMediaData(for: question.id),
            voiceDurationMs: sendingVoiceDurationMs(for: question.id),
            partnerChoiceName: sendingPartnerChoiceName(for: question.id),
            text: sendingText(for: question.id),
            isHeldOnPhone: isHeldOnPhone(question.id)
        )
    }

    /// A still-sending answer failed to send at least once. Only then does the
    /// screen say it is saved on this phone, so a normal send never flashes that line.
    func isHeldOnPhone(_ instanceID: UUID) -> Bool {
        isSending(instanceID) && sendingAnswers[instanceID]?.isHeldOnPhone == true
    }

    /// The recorded length of a still-sending voice note, so its playback scrubber
    /// shows a duration before the local file finishes loading. Nil for photos.
    func sendingVoiceDurationMs(for instanceID: UUID) -> Int? {
        guard let media = sendingAnswers[instanceID]?.media, media.draft.purpose == .voice else { return nil }
        return media.draft.durationMs
    }

    /// Recomputes which questions still have a queued/in-flight answer, from the
    /// persisted operations — so the "sending" state survives relaunch and clears once
    /// the send finishes.
    func refreshSendingState() async {
        guard let currentUserID else {
            sendingAnswers = [:]
            return
        }

        let generation = sendingGeneration
        // A failed read keeps what we have. Treating it as "nothing is sending" would
        // make a queued answer look lost, with its composer empty.
        guard let operations = try? await pendingOperationStore.inFlightOperations(
            ownerUserID: currentUserID,
            kind: .submitDailyAnswer
        ) else { return }
        // A send queued while this read was in flight may be missing from it. Keep the
        // local entry; the reload that follows that send refreshes this again.
        guard generation == sendingGeneration, self.currentUserID == currentUserID else { return }

        sendingAnswers = Dictionary(
            operations.compactMap { operation -> (UUID, SendingAnswer)? in
                guard let data = operation.requestData,
                      let payload = try? JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
                else { return nil }
                var answer = Self.sendingAnswer(from: payload.content)
                answer.isHeldOnPhone = operation.hasFailedAttempt
                return (payload.instanceID, answer)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func sendingAnswer(
        from content: DailySubmitAnswerOperationPayload.Content
    ) -> SendingAnswer {
        switch content {
        case let .text(body):
            return SendingAnswer(text: body)
        case let .partnerChoice(userID):
            return SendingAnswer(partnerChoiceUserID: userID)
        case let .media(media):
            return SendingAnswer(media: .init(draft: media.draft, stagedData: media.stagedData))
        case let .textAndMedia(body, media):
            return SendingAnswer(text: body, media: .init(draft: media.draft, stagedData: media.stagedData))
        case let .textAndPartnerChoice(body, userID):
            return SendingAnswer(text: body, partnerChoiceUserID: userID)
        }
    }
}
