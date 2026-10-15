import Foundation

struct CreateDailyChatThreadOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .createDailyQuestionThreadWithMessage

    private let gateway: any DailyQuestionChatGateway
    private let cache: any DailyQuestionChatCaching
    private let mediaUploadService: (any DailyAnswerMediaUploading)?
    private let imageCache: (any DailyAnswerMediaImageCacheWriting)?

    init(
        gateway: any DailyQuestionChatGateway,
        cache: any DailyQuestionChatCaching,
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
        let payload = try JSONDecoder().decode(
            CreateDailyChatThreadPayload.self,
            from: data
        )
        guard isInCurrentCouple(payload.coupleID, context: context) else {
            await markChatMessageFailed(operation, cache: cache)
            return .terminalFailure("The chat belongs to an earlier relationship")
        }
        let mediaAssetIDs = try await uploadAttachments(of: payload, with: mediaUploadService, imageCache: imageCache)
        let response: DailyQuestionThreadMessageResponse
        do {
            response = try await gateway.createThreadWithMessage(
                payload,
                mediaAssetIDs: mediaAssetIDs,
                operation: operation.operation
            )
        } catch {
            guard isPermanentChatFailure(error) else { throw error }
            await markChatMessageFailed(operation, cache: cache)
            try await failMessagesWaitingForThread(of: payload.questionID, operation, context: context)
            return .terminalFailure("Daily question chat is no longer available")
        }
        await confirmSent(operation, response: response, of: payload, in: cache)
        return .succeeded
    }

    /// Messages queued while this thread was being created wait for its id. The
    /// thread will never exist now, so they would wait forever. Show them as failed,
    /// so the person can send them again.
    private func failMessagesWaitingForThread(
        of questionID: UUID,
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws {
        let store = context.pendingOperationStore
        let sends = try await store.inFlightOperations(ownerUserID: operation.ownerUserID, kind: .sendThreadMessage)
        for waiting in sends {
            guard let data = waiting.requestData,
                  let payload = try? JSONDecoder().decode(
                    SendDailyChatMessagePayload.self,
                    from: data
                  ),
                  payload.questionID == questionID,
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

struct SendDailyChatMessageOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .sendThreadMessage

    private let gateway: any DailyQuestionChatGateway
    private let cache: any DailyQuestionChatCaching
    private let mediaUploadService: (any DailyAnswerMediaUploading)?
    private let imageCache: (any DailyAnswerMediaImageCacheWriting)?

    init(
        gateway: any DailyQuestionChatGateway,
        cache: any DailyQuestionChatCaching,
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
        let payload = try JSONDecoder().decode(
            SendDailyChatMessagePayload.self,
            from: data
        )
        guard isInCurrentCouple(payload.coupleID, context: context) else {
            await markChatMessageFailed(operation, cache: cache)
            return .terminalFailure("The chat belongs to an earlier relationship")
        }
        let cachedThreadID = await cache.summaries(ownerUserID: operation.ownerUserID)
            .first(where: { $0.questionID == payload.questionID && $0.coupleID == payload.coupleID })?.threadID
        guard let threadID = payload.threadID ?? cachedThreadID else {
            return .retry(after: nil)
        }

        let mediaAssetIDs = try await uploadAttachments(of: payload, with: mediaUploadService, imageCache: imageCache)
        let response: DailyQuestionThreadMessageResponse
        do {
            response = try await gateway.sendMessage(
                threadID: threadID,
                body: payload.body,
                mediaAssetIDs: mediaAssetIDs,
                replyToMessageID: payload.replyToMessageID,
                operation: operation.operation
            )
        } catch {
            guard isPermanentChatFailure(error) else { throw error }
            await markChatMessageFailed(operation, cache: cache)
            return .terminalFailure("Thread message was rejected")
        }
        await confirmSent(operation, response: response, of: payload, in: cache)
        return .succeeded
    }
}

/// What the handlers read from either kind of queued chat message.
private nonisolated protocol ChatMessagePayload {
    var questionID: UUID { get }
    var coupleID: UUID { get }
    var body: String { get }
    var voice: DailyQuestionChatVoicePayload? { get }
    var photos: DailyQuestionChatPhotosPayload? { get }
}

extension CreateDailyChatThreadPayload: ChatMessagePayload {}
extension SendDailyChatMessagePayload: ChatMessagePayload {}

/// Replaces the message shown while sending with the one the server confirmed.
private func confirmSent(
    _ operation: PendingSyncOperationSnapshot,
    response: DailyQuestionThreadMessageResponse,
    of payload: some ChatMessagePayload,
    in cache: any DailyQuestionChatCaching
) async {
    await cache.confirm(
        ownerUserID: operation.ownerUserID,
        questionID: payload.questionID,
        coupleID: payload.coupleID,
        clientOperationID: operation.operation.id,
        threadID: response.threadID,
        messageID: response.messageID,
        body: payload.body,
        senderUserID: operation.ownerUserID,
        createdAt: operation.operation.localCreatedAt
    )
    LocalStoreChanges.post(.dailyChat, ownerUserID: operation.ownerUserID)
}

/// A message belongs to the couple it was written in. Once the user is in another couple, it
/// is refused here instead of being sent to the new one. While no couple is active, such as
/// a lapsed subscription, the server decides.
private nonisolated func isInCurrentCouple(_ coupleID: UUID, context: SyncContext) -> Bool {
    context.session.activeCoupleID.map { $0 == coupleID } ?? true
}

/// Uploads a message's photos, or its voice recording, and returns the media asset ids
/// in order. The fixed operations make a retry pick up the same uploads. Upload
/// errors throw, so the operation retries later.
private func uploadAttachments(
    of payload: some ChatMessagePayload,
    with uploader: (any DailyAnswerMediaUploading)?,
    imageCache: (any DailyAnswerMediaImageCacheWriting)?
) async throws -> [UUID] {
    guard payload.voice != nil || payload.photos != nil else { return [] }
    guard let uploader else { throw DailyQuestionChatServiceError.unavailable }
    var assetIDs: [UUID] = []
    for photo in payload.photos?.items ?? [] {
        let assetID = try await uploader.uploadMedia(
            DailyAnswerUploadMedia(
                data: photo.data,
                purpose: .threadPhoto,
                mimeType: "image/jpeg",
                fileExtension: "jpg",
                width: photo.width,
                height: photo.height
            ),
            answerID: payload.photos?.messageID ?? UUID(),
            coupleID: payload.coupleID,
            reserveOperation: photo.reserveOperation,
            finalizeOperation: photo.finalizeOperation
        )
        assetIDs.append(assetID)
        // The sender's own photo then shows from this phone, with no download or flash
        // when the server's copy of the message replaces the local one.
        await imageCache?.cacheImageData(photo.data, for: assetID)
        _ = await DailyChatPhotoLayout.decodeAndCache(photo.data, key: "chat-\(assetID.uuidString)")
    }
    if let voice = payload.voice {
        assetIDs.append(try await uploader.uploadMedia(
            DailyAnswerUploadMedia(
                data: voice.data,
                purpose: .voice,
                mimeType: DailyChatVoiceRecording.mimeType,
                fileExtension: DailyChatVoiceRecording.fileExtension,
                durationMs: voice.durationMs
            ),
            answerID: voice.messageID,
            coupleID: payload.coupleID,
            reserveOperation: voice.reserveOperation,
            finalizeOperation: voice.finalizeOperation
        ))
    }
    return assetIDs
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
    cache: any DailyQuestionChatCaching
) async {
    await cache.markFailed(
        ownerUserID: operation.ownerUserID,
        clientOperationID: operation.operation.id
    )
    LocalStoreChanges.post(.dailyChat, ownerUserID: operation.ownerUserID)
}
