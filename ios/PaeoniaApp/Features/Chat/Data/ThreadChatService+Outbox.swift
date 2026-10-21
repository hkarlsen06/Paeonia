import Foundation

extension ThreadChatService {
    /// The messages the chat shows as sending. A message the user took back while its send was
    /// being retried is left out, though its send stays in the queue until the delete follows it.
    func pendingMessages(ownerUserID: UUID, coupleID: UUID, subjectID: UUID) async -> [ThreadChatMessage] {
        let takenBack = await pendingDeletions(ownerUserID: ownerUserID).bySendOperationID
        return await loadPendingMessages(ownerUserID: ownerUserID, coupleID: coupleID, subjectID: subjectID)
            .filter { message in message.clientOperationID.map { takenBack[$0] == nil } ?? true }
    }

    /// `coupleID` nil matches every couple. Merging server results into the cache only
    /// links a message to its operation, so it needs no couple.
    func loadPendingMessages(
        ownerUserID: UUID,
        coupleID: UUID?,
        subjectID: UUID
    ) async -> [ThreadChatMessage] {
        async let creates = pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .createChatThreadWithMessage
        )
        async let sends = pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .sendThreadMessage
        )

        let createMessages = (try? await creates) ?? []
        let sendMessages = (try? await sends) ?? []
        return (createMessages + sendMessages)
            .compactMap { pendingMessage($0, coupleID: coupleID, subjectID: subjectID) }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func hasPendingThreadCreation(ownerUserID: UUID, coupleID: UUID, subjectID: UUID) async -> Bool {
        let operations = (try? await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .createChatThreadWithMessage
        )) ?? []
        guard !operations.isEmpty else { return false }
        // The handler marks a rejected message failed before the drain records the
        // operation as finished. That operation is no longer creating the thread.
        let cached = await cache.messages(ownerUserID: ownerUserID, subjectID: subjectID)
        let failedOperationIDs = Set(cached.filter(\.sendFailed).compactMap(\.clientOperationID))
        return operations.contains { operation in
            guard !failedOperationIDs.contains(operation.operation.id),
                  let data = operation.requestData,
                  let payload = try? JSONDecoder().decode(
                    CreateChatThreadPayload.self,
                    from: data
                  ) else { return false }
            return payload.subject.id == subjectID && payload.coupleID == coupleID
        }
    }

    private func pendingMessage(
        _ operation: PendingSyncOperationSnapshot,
        coupleID: UUID?,
        subjectID: UUID
    ) -> ThreadChatMessage? {
        guard
            let data = operation.requestData,
            let content = PendingChatContent(operation, data: data, coupleID: coupleID, subjectID: subjectID)
        else { return nil }

        return ThreadChatMessage(
            id: content.voice?.messageID ?? content.photos?.messageID ?? operation.operation.id,
            threadID: content.threadID,
            subjectID: subjectID,
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
        subject: ThreadChatSubject,
        threadID: UUID?,
        body: String,
        photos: ThreadChatPhotosPayload?,
        createThread: Bool,
        replyTo: ThreadChatItemID?,
        operation: SyncClientOperation
    ) async throws -> ThreadChatMessage {
        try await enqueue(
            OutgoingChatMessage(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                subject: subject,
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
        subject: ThreadChatSubject,
        threadID: UUID?,
        voice: ThreadChatVoicePayload,
        createThread: Bool,
        replyTo: ThreadChatItemID?,
        operation: SyncClientOperation
    ) async throws -> ThreadChatMessage {
        try await enqueue(
            OutgoingChatMessage(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                subject: subject,
                threadID: threadID,
                body: "",
                voice: voice,
                createThread: createThread,
                replyTo: replyTo,
                operation: operation
            )
        )
    }

    private func enqueue(_ message: OutgoingChatMessage) async throws -> ThreadChatMessage {
        let requestData = try message.requestData(encoder: encoder)
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: message.ownerUserID,
                operation: message.operation,
                operationKind: message.operationKind,
                idempotencyScope: "thread-chat:\(message.subject.id.uuidString.lowercased())",
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
    let subject: ThreadChatSubject
    let threadID: UUID?
    let body: String
    var voice: ThreadChatVoicePayload?
    var photos: ThreadChatPhotosPayload?
    let createThread: Bool
    let replyTo: ThreadChatItemID?
    let operation: SyncClientOperation

    var operationKind: SyncPendingOperationKind {
        createThread ? .createChatThreadWithMessage : .sendThreadMessage
    }

    func requestData(encoder: JSONEncoder) throws -> Data {
        if createThread {
            return try encoder.encode(
                CreateChatThreadPayload(
                    subject: subject,
                    coupleID: coupleID,
                    body: body,
                    voice: voice,
                    photos: photos,
                    replyToAnswerID: replyTo?.answerID
                )
            )
        }
        return try encoder.encode(
            SendChatMessagePayload(
                subject: subject,
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
    var sendingCopy: ThreadChatMessage {
        ThreadChatMessage(
            id: voice?.messageID ?? photos?.messageID ?? operation.id,
            threadID: threadID,
            subjectID: subject.id,
            senderUserID: ownerUserID,
            body: body,
            createdAt: operation.localCreatedAt,
            clientOperationID: operation.id,
            isSending: true,
            voice: voice?.pendingVoice,
            photos: photos?.pendingPhotos,
            // The first message creates the thread, so it can only reply to an answer.
            replyTo: createThread ? replyTo?.answerID.map(ThreadChatItemID.answer) : replyTo
        )
    }
}

/// What a queued chat operation says about the message it will send.
private nonisolated struct PendingChatContent {
    let body: String
    let threadID: UUID?
    let voice: ThreadChatVoicePayload?
    let photos: ThreadChatPhotosPayload?
    var replyTo: ThreadChatItemID?

    /// Nil when the operation is not a chat message, or belongs to another question or couple.
    /// A nil `coupleID` matches every couple.
    init?(_ operation: PendingSyncOperationSnapshot, data: Data, coupleID: UUID?, subjectID: UUID) {
        switch operation.operationKind {
        case .createChatThreadWithMessage:
            guard let payload = try? JSONDecoder().decode(CreateChatThreadPayload.self, from: data),
                  payload.subject.id == subjectID, coupleID == nil || payload.coupleID == coupleID
            else { return nil }
            body = payload.body
            threadID = nil
            voice = payload.voice
            photos = payload.photos
            replyTo = payload.replyToAnswerID.map(ThreadChatItemID.answer)
        case .sendThreadMessage:
            guard let payload = try? JSONDecoder().decode(SendChatMessagePayload.self, from: data),
                  payload.subject.id == subjectID, coupleID == nil || payload.coupleID == coupleID
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
