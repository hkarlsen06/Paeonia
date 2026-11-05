import Foundation

extension DailyChallengeViewModel {
    /// Asking for today's question starts the shared day, just like opening it in the app.
    func todayQuestionForSiri(
        couple: SiriCouple, authorize: @MainActor () async throws -> Bool
    ) async throws -> DailyChallengeQuestion {
        guard try await authorize(), currentUserID == couple.ownerUserID else {
            throw SiriFailure(.siriAccessSignedOut)
        }
        try Task.checkCancellation()
        if snapshot.endingCurrentDay(ifEndedBy: now()).todayQuestion == nil {
            await startToday()
        }
        guard try await authorize(), currentUserID == couple.ownerUserID else {
            throw SiriFailure(.siriAccessSignedOut)
        }
        try Task.checkCancellation()
        guard let question = snapshot.todayQuestion,
              question.coupleID == couple.coupleID,
              question.startsAt <= now(), question.endsAt > now() else {
            if case .startFailed(.offline) = notice {
                throw SiriFailure(.dailyChallengeStartFailedMessage)
            }
            throw SiriFailure(.siriDailyLoadFailed)
        }
        return question
    }

    /// Uses the composer's durable queue. The exact daily instance must still be current.
    func submitSiriText(
        _ text: String, instanceID: UUID, couple: SiriCouple,
        authorize: @MainActor () async throws -> Bool
    ) async throws {
        let queued = try await pendingOperationStore.inFlightOperations(
            ownerUserID: couple.ownerUserID, kind: .submitDailyAnswer
        )
        let hasQueuedAnswer = queued.contains { operation in
            guard let data = operation.requestData,
                  let payload = try? JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
            else { return true }
            return payload.instanceID == instanceID
        }
        guard try await authorize() else { throw SiriFailure(.siriAccessSignedOut) }
        guard currentUserID == couple.ownerUserID,
              let question = snapshot.todayQuestion,
              question.id == instanceID, question.coupleID == couple.coupleID,
              question.isCurrentDay, question.status != .shuffled,
              question.startsAt <= now(), question.endsAt > now(),
              submittingQuestionID == nil, shufflingQuestionID == nil
        else { throw SiriFailure(.siriDailyUnavailable) }
        guard !question.hasOwnAnswer, !hasQueuedAnswer, sendingAnswers[instanceID] == nil else {
            throw SiriFailure(.siriDailyAnswered)
        }
        guard !hasDraftContent(for: instanceID),
              draftStore.drafts(for: couple.ownerUserID)[instanceID]?.hasContent != true else {
            throw SiriFailure(.siriDailyDraft)
        }
        guard question.composableAnswerKinds.contains(.text), !question.answerKinds.contains(.eitherOr) else {
            throw SiriFailure(.siriDailyNeedsApp)
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, DailyAnswerDraft.measuredLength(of: body) <= question.maxAnswerTextLength else {
            throw SiriFailure(.siriDailyInvalidText)
        }
        setComposeKind(.text, for: instanceID)
        setDraftText(body, for: instanceID)
        flushDraftPersistence()
        await submitAnswer(for: question)
        guard sendingAnswers[instanceID]?.text == body else {
            throw SiriFailure(.siriDailySaveFailed)
        }
    }
}
