import Foundation

struct CreateChatThreadOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .createChatThreadWithMessage

    private let gateway: any ThreadChatGateway
    private let cache: any ThreadChatCaching
    private let mediaUploadService: (any DailyAnswerMediaUploading)?
    private let imageCache: (any DailyAnswerMediaImageCacheWriting)?

    init(
        gateway: any ThreadChatGateway,
        cache: any ThreadChatCaching,
        mediaUploadService: (any DailyAnswerMediaUploading)? = nil,
        imageCache: (any DailyAnswerMediaImageCacheWriting)? = nil
    ) {
        self.gateway = gateway
        self.cache = cache
        self.mediaUploadService = mediaUploadService
        self.imageCache = imageCache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData else {
            return .terminalFailure("Missing daily question thread payload")
        }
        let payload = try JSONDecoder().decodeQueuedPayload(
            CreateChatThreadPayload.self,
            from: data
        )
        guard isInCurrentCouple(payload.coupleID, context: context) else {
            await markChatMessageFailed(operation, cache: cache)
            return .terminalFailure("The chat belongs to an earlier relationship")
        }
        let uploads = try await ThreadChatSendAttachments.upload(
            operation, of: payload, with: mediaUploadService, imageCache: imageCache, context: context
        )
        guard case let .ready(mediaAssetIDs) = uploads else {
            try await failMessagesWaitingForThread(of: payload.subject, operation, context: context)
            return await stopSend(operation, after: uploads, cache: cache)
        }
        let response: ThreadChatMessageResponse
        do {
            response = try await gateway.createThreadWithMessage(
                payload,
                mediaAssetIDs: mediaAssetIDs,
                operation: operation.operation
            )
        } catch {
            guard isPermanentChatFailure(error) else { throw error }
            if try await isWaitingForItsMemory(payload.subject, operation, context: context) {
                return .retry(after: nil)
            }
            await markChatMessageFailed(operation, cache: cache)
            await imageCache?.evict(mediaAssetIDs: mediaAssetIDs)
            try await failMessagesWaitingForThread(of: payload.subject, operation, context: context)
            return .terminalFailure("The chat is no longer available")
        }
        await confirmSent(operation, response: response, mediaAssetIDs: mediaAssetIDs, of: payload, in: cache)
        return .succeeded
    }

    nonisolated var showsGivenUpWrites: Bool { true }

    func gaveUp(on operation: PendingSyncOperationSnapshot, context _: SyncContext) async {
        await markChatMessageFailed(operation, cache: cache)
        await ThreadChatSendAttachments.evictFinishedUploads(
            of: operation, as: CreateChatThreadPayload.self, with: mediaUploadService, from: imageCache
        )
    }

    // swiftlint:disable:next async_without_await
    func didRecordSuccess(of operation: PendingSyncOperationSnapshot) async {
        ThreadChatSendAttachments.deleteFiles(of: operation, as: CreateChatThreadPayload.self)
    }

    nonisolated func timeLimit(for operation: PendingSyncOperationSnapshot) -> Duration? {
        ThreadChatSendAttachments.timeLimit(of: operation, as: CreateChatThreadPayload.self)
    }

    func isTakenBack(_ operation: PendingSyncOperationSnapshot, context: SyncContext) async -> Bool {
        await ThreadChatSendAttachments.isTakenBack(operation, context: context)
    }

    /// A comment on a memory this phone saved but has not sent yet. The server does not have the
    /// memory, so the comment waits for it, and moves with it if it joins the partner's memory.
    private func isWaitingForItsMemory(
        _ subject: ThreadChatSubject,
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Bool {
        guard case let .memory(memoryID) = subject else { return false }
        return try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: operation.ownerUserID, kind: .createMemory)
            .contains { $0.requestData.flatMap(MemoryPendingOperationRefresh.memoryID(in:)) == memoryID }
    }

    /// Messages queued while this thread was being created wait for its id. The
    /// thread will never exist now, so they would wait forever. Show them as failed,
    /// so the person can send them again.
    private func failMessagesWaitingForThread(
        of subject: ThreadChatSubject,
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws {
        let store = context.pendingOperationStore
        let sends = try await store.inFlightOperations(ownerUserID: operation.ownerUserID, kind: .sendThreadMessage)
        for waiting in sends {
            guard let data = waiting.requestData,
                  let payload = try? JSONDecoder().decode(
                    SendChatMessagePayload.self,
                    from: data
                  ),
                  payload.subject == subject,
                  payload.threadID == nil
            else { continue }
            await markChatMessageFailed(waiting, cache: cache)
            try await store.markTerminalFailure(
                clientOperationID: waiting.operation.id,
                errorDescription: "The chat this message waited for was refused",
                at: Date()
            )
        }
    }
}

struct SendChatMessageOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .sendThreadMessage

    private let gateway: any ThreadChatGateway
    private let cache: any ThreadChatCaching
    private let mediaUploadService: (any DailyAnswerMediaUploading)?
    private let imageCache: (any DailyAnswerMediaImageCacheWriting)?

    init(
        gateway: any ThreadChatGateway,
        cache: any ThreadChatCaching,
        mediaUploadService: (any DailyAnswerMediaUploading)? = nil,
        imageCache: (any DailyAnswerMediaImageCacheWriting)? = nil
    ) {
        self.gateway = gateway
        self.cache = cache
        self.mediaUploadService = mediaUploadService
        self.imageCache = imageCache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData else {
            return .terminalFailure("Missing thread message payload")
        }
        let payload = try JSONDecoder().decodeQueuedPayload(
            SendChatMessagePayload.self,
            from: data
        )
        guard isInCurrentCouple(payload.coupleID, context: context) else {
            await markChatMessageFailed(operation, cache: cache)
            return .terminalFailure("The chat belongs to an earlier relationship")
        }
        let cachedThreadID = await cache.summaries(ownerUserID: operation.ownerUserID)
            .first(where: { $0.subject == payload.subject && $0.coupleID == payload.coupleID })?.threadID
        guard let threadID = payload.threadID ?? cachedThreadID else {
            return .retry(after: nil)
        }

        let uploads = try await ThreadChatSendAttachments.upload(
            operation, of: payload, with: mediaUploadService, imageCache: imageCache, context: context
        )
        guard case let .ready(mediaAssetIDs) = uploads else {
            return await stopSend(operation, after: uploads, cache: cache)
        }
        let response: ThreadChatMessageResponse
        do {
            response = try await gateway.sendMessage(
                threadID: threadID,
                body: payload.body,
                mediaAssetIDs: mediaAssetIDs,
                replyTo: payload.replyTo,
                operation: operation.operation
            )
        } catch {
            guard isPermanentChatFailure(error) else { throw error }
            await markChatMessageFailed(operation, cache: cache)
            await imageCache?.evict(mediaAssetIDs: mediaAssetIDs)
            return .terminalFailure("Thread message was rejected")
        }
        await confirmSent(operation, response: response, mediaAssetIDs: mediaAssetIDs, of: payload, in: cache)
        return .succeeded
    }

    nonisolated var showsGivenUpWrites: Bool { true }

    func gaveUp(on operation: PendingSyncOperationSnapshot, context _: SyncContext) async {
        await markChatMessageFailed(operation, cache: cache)
        await ThreadChatSendAttachments.evictFinishedUploads(
            of: operation, as: SendChatMessagePayload.self, with: mediaUploadService, from: imageCache
        )
    }

    // swiftlint:disable:next async_without_await
    func didRecordSuccess(of operation: PendingSyncOperationSnapshot) async {
        ThreadChatSendAttachments.deleteFiles(of: operation, as: SendChatMessagePayload.self)
    }

    nonisolated func timeLimit(for operation: PendingSyncOperationSnapshot) -> Duration? {
        ThreadChatSendAttachments.timeLimit(of: operation, as: SendChatMessagePayload.self)
    }

    func isTakenBack(_ operation: PendingSyncOperationSnapshot, context: SyncContext) async -> Bool {
        await ThreadChatSendAttachments.isTakenBack(operation, context: context)
    }
}

/// Replaces the message shown while sending with the one the server confirmed.
private func confirmSent(
    _ operation: PendingSyncOperationSnapshot,
    response: ThreadChatMessageResponse,
    mediaAssetIDs: [UUID],
    of payload: some ChatMessagePayload,
    in cache: any ThreadChatCaching
) async {
    await cache.confirm(
        ThreadChatConfirmedSend(
            subject: payload.subject,
            coupleID: payload.coupleID,
            clientOperationID: operation.operation.id,
            threadID: response.threadID,
            messageID: response.messageID,
            body: payload.body,
            senderUserID: operation.ownerUserID,
            createdAt: operation.operation.localCreatedAt,
            mediaAssetIDs: mediaAssetIDs,
            mediaType: payload.voice != nil ? "voice" : payload.attachments?.items.first?.kind.serverMediaType
        ),
        ownerUserID: operation.ownerUserID
    )
    LocalStoreChanges.post(.threadChat, ownerUserID: operation.ownerUserID)
}

/// A message belongs to the couple it was written in. Once the user is in another couple, it
/// is refused here instead of being sent to the new one. While no couple is active, such as
/// a lapsed subscription, the server decides.
private nonisolated func isInCurrentCouple(_ coupleID: UUID, context: SyncContext) -> Bool {
    context.session.activeCoupleID.map { $0 == coupleID } ?? true
}

/// Ends a send whose attachments cannot go. A missing file shows the message as not sent.
/// A taken-back message is already gone from the chat.
private func stopSend(
    _ operation: PendingSyncOperationSnapshot,
    after uploads: ThreadChatSendAttachments.Outcome,
    cache: any ThreadChatCaching
) async -> PendingSyncOperationSendResult {
    switch uploads {
    case .ready, .takenBack:
        return .terminalFailure("Taken back before it reached the server")
    case .missingFile:
        await markChatMessageFailed(operation, cache: cache)
        return .terminalFailure("An attachment is no longer on this phone")
    }
}

/// Server rejections that sending again cannot fix. The Convex client puts the
/// server's message in the error's description. Everything else, such as a lost
/// connection, stays retryable.
private nonisolated func isPermanentChatFailure(_ error: any Error) -> Bool {
    let description = String(describing: error).lowercased()
    return [
        "you must answer this daily question",
        "daily question thread requires both partners",
        "daily question was not found",
        // The memory or the story was deleted while the message waited.
        "active entitled memory access is required",
        "active entitled story access is required",
        "active entitled thread access is required",
        "message sender must be an active visible thread member",
        "thread message body is too long",
        "reply target must be in the same thread",
        "reply target is not available"
    ].contains { description.contains($0) }
}

/// Shows the message as failed in the open chat. The drain records the operation
/// as finished after the handler returns.
private func markChatMessageFailed(
    _ operation: PendingSyncOperationSnapshot,
    cache: any ThreadChatCaching
) async {
    await cache.markFailed(
        ownerUserID: operation.ownerUserID,
        clientOperationID: operation.operation.id
    )
    LocalStoreChanges.post(.threadChat, ownerUserID: operation.ownerUserID)
}
