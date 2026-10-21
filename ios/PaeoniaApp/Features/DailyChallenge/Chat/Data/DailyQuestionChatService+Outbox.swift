import Foundation

extension DailyQuestionChatService {
    func pendingMessages(ownerUserID: UUID, coupleID: UUID, questionID: UUID) async -> [DailyQuestionChatMessage] {
        await loadPendingMessages(ownerUserID: ownerUserID, coupleID: coupleID, questionID: questionID)
    }

    /// `coupleID` nil matches every couple. Merging server results into the cache only
    /// links a message to its operation, so it needs no couple.
    func loadPendingMessages(
        ownerUserID: UUID,
        coupleID: UUID?,
        questionID: UUID
    ) async -> [DailyQuestionChatMessage] {
        async let creates = pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        async let sends = pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .sendThreadMessage
        )

        let createMessages = (try? await creates) ?? []
        let sendMessages = (try? await sends) ?? []
        return (createMessages + sendMessages)
            .compactMap { pendingMessage($0, coupleID: coupleID, questionID: questionID) }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func hasPendingThreadCreation(ownerUserID: UUID, coupleID: UUID, questionID: UUID) async -> Bool {
        let operations = (try? await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )) ?? []
        guard !operations.isEmpty else { return false }
        // The handler marks a rejected message failed before the drain records the
        // operation as finished. That operation is no longer creating the thread.
        let cached = await cache.messages(ownerUserID: ownerUserID, questionID: questionID)
        let failedOperationIDs = Set(cached.filter(\.sendFailed).compactMap(\.clientOperationID))
        return operations.contains { operation in
            guard !failedOperationIDs.contains(operation.operation.id),
                  let data = operation.requestData,
                  let payload = try? JSONDecoder().decode(
                    CreateDailyChatThreadPayload.self,
                    from: data
                  ) else { return false }
            return payload.questionID == questionID && payload.coupleID == coupleID
        }
    }

    private func pendingMessage(
        _ operation: PendingSyncOperationSnapshot,
        coupleID: UUID?,
        questionID: UUID
    ) -> DailyQuestionChatMessage? {
        guard
            let data = operation.requestData,
            let content = PendingChatContent(operation, data: data, coupleID: coupleID, questionID: questionID)
        else { return nil }

        return DailyQuestionChatMessage(
            id: content.voice?.messageID ?? content.photos?.messageID ?? operation.operation.id,
            threadID: content.threadID,
            questionID: questionID,
            senderUserID: operation.ownerUserID,
            body: content.body,
            createdAt: operation.operation.localCreatedAt,
            clientOperationID: operation.operation.id,
            isSending: true,
            isHeldOnPhone: operation.hasFailedAttempt,
            voice: content.voice?.pendingVoice,
            photos: content.photos?.pendingPhotos,
            replyTo: content.replyTo
        )
    }

    // swiftlint:disable:next function_parameter_count
    func queueMessage(
        ownerUserID: UUID,
        coupleID: UUID,
        questionID: UUID,
        threadID: UUID?,
        body: String,
        photos: DailyQuestionChatPhotosPayload?,
        createThread: Bool,
        replyTo: DailyChatItemID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage {
        try await enqueue(
            OutgoingChatMessage(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                questionID: questionID,
                threadID: threadID,
                body: body,
                photos: photos,
                createThread: createThread,
                replyTo: replyTo,
                operation: operation
            )
        )
    }

    // swiftlint:disable:next function_parameter_count
    func queueVoiceMessage(
        ownerUserID: UUID,
        coupleID: UUID,
        questionID: UUID,
        threadID: UUID?,
        voice: DailyQuestionChatVoicePayload,
        createThread: Bool,
        replyTo: DailyChatItemID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage {
        try await enqueue(
            OutgoingChatMessage(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                questionID: questionID,
                threadID: threadID,
                body: "",
                voice: voice,
                createThread: createThread,
                replyTo: replyTo,
                operation: operation
            )
        )
    }

    private func enqueue(_ message: OutgoingChatMessage) async throws -> DailyQuestionChatMessage {
        let requestData = try message.requestData(encoder: encoder)
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: message.ownerUserID,
                operation: message.operation,
                operationKind: message.operationKind,
                idempotencyScope: "daily-question-chat:\(message.questionID.uuidString.lowercased())",
                requestData: requestData
            )
        )

        let sending = message.sendingCopy
        await cache.append(sending, ownerUserID: message.ownerUserID)
        return sending
    }
}

/// One chat message on its way into the outbox, with the text, photos or voice it carries.
private nonisolated struct OutgoingChatMessage {
    let ownerUserID: UUID
    let coupleID: UUID
    let questionID: UUID
    let threadID: UUID?
    let body: String
    var voice: DailyQuestionChatVoicePayload?
    var photos: DailyQuestionChatPhotosPayload?
    let createThread: Bool
    let replyTo: DailyChatItemID?
    let operation: SyncClientOperation

    var operationKind: SyncPendingOperationKind {
        createThread ? .createDailyQuestionThreadWithMessage : .sendThreadMessage
    }

    func requestData(encoder: JSONEncoder) throws -> Data {
        if createThread {
            return try encoder.encode(
                CreateDailyChatThreadPayload(
                    questionID: questionID,
                    coupleID: coupleID,
                    body: body,
                    voice: voice,
                    photos: photos,
                    replyToAnswerID: replyTo?.answerID
                )
            )
        }
        return try encoder.encode(
            SendDailyChatMessagePayload(
                questionID: questionID,
                coupleID: coupleID,
                threadID: threadID,
                body: body,
                voice: voice,
                photos: photos,
                replyTo: replyTo
            )
        )
    }

    /// The copy shown in the chat while the message is still sending.
    var sendingCopy: DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: voice?.messageID ?? photos?.messageID ?? operation.id,
            threadID: threadID,
            questionID: questionID,
            senderUserID: ownerUserID,
            body: body,
            createdAt: operation.localCreatedAt,
            clientOperationID: operation.id,
            isSending: true,
            voice: voice?.pendingVoice,
            photos: photos?.pendingPhotos,
            // The first message creates the thread, so it can only reply to an answer.
            replyTo: createThread ? replyTo?.answerID.map(DailyChatItemID.answer) : replyTo
        )
    }
}

/// What a queued chat operation says about the message it will send.
private nonisolated struct PendingChatContent {
    let body: String
    let threadID: UUID?
    let voice: DailyQuestionChatVoicePayload?
    let photos: DailyQuestionChatPhotosPayload?
    var replyTo: DailyChatItemID?

    /// Nil when the operation is not a chat message, or belongs to another question or couple.
    /// A nil `coupleID` matches every couple.
    init?(_ operation: PendingSyncOperationSnapshot, data: Data, coupleID: UUID?, questionID: UUID) {
        switch operation.operationKind {
        case .createDailyQuestionThreadWithMessage:
            guard let payload = try? JSONDecoder().decode(CreateDailyChatThreadPayload.self, from: data),
                  payload.questionID == questionID, coupleID == nil || payload.coupleID == coupleID
            else { return nil }
            body = payload.body
            threadID = nil
            voice = payload.voice
            photos = payload.photos
            replyTo = payload.replyToAnswerID.map(DailyChatItemID.answer)
        case .sendThreadMessage:
            guard let payload = try? JSONDecoder().decode(SendDailyChatMessagePayload.self, from: data),
                  payload.questionID == questionID, coupleID == nil || payload.coupleID == coupleID
            else { return nil }
            body = payload.body
            threadID = payload.threadID
            voice = payload.voice
            photos = payload.photos
            replyTo = payload.replyTo
        default:
            return nil
        }
    }
}
