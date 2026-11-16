import Foundation

/// What the send handlers read from either kind of queued chat message.
nonisolated protocol ChatMessagePayload {
    var subject: ThreadChatSubject { get }
    var coupleID: UUID { get }
    var body: String { get }
    var voice: ThreadChatVoicePayload? { get }
    var attachments: ThreadChatAttachmentsPayload? { get }
}

extension CreateChatThreadPayload: ChatMessagePayload {}
extension SendChatMessagePayload: ChatMessagePayload {}

/// The uploads of a queued chat message: its photos, GIFs, videos and voice recording.
enum ThreadChatSendAttachments {
    enum Outcome {
        case ready(mediaAssetIDs: [UUID])
        /// An attachment's file is gone from this phone, so the message shows as not sent.
        case missingFile
        /// The person took the message back, and an upload never finished, so the server
        /// cannot have it. Its files and the cached copies of its finished uploads are gone.
        case takenBack
    }

    /// Uploads the attachments in order and returns their asset ids. A taken-back message
    /// only replays its reservations, which send no bytes, so a big video that never got
    /// through does not start again. The fixed operations make a retry pick up the same
    /// uploads. Upload errors throw, so the operation retries later. A message that stops
    /// here drops the cached copies of its finished uploads, which nothing shows any more.
    static func upload(
        _ operation: PendingSyncOperationSnapshot,
        of payload: some ChatMessagePayload,
        with uploader: (any DailyAnswerMediaUploading)?,
        imageCache: (any DailyAnswerMediaImageCacheWriting)?,
        context: SyncContext
    ) async throws -> Outcome {
        if await isTakenBack(operation, context: context) {
            let finished = try await finishedUploads(of: payload, with: uploader)
            // Also when every upload finished: the send then goes, and its delete follows it.
            await imageCache?.evict(mediaAssetIDs: finished.compactMap { $0 })
            if !finished.contains(nil) {
                return .ready(mediaAssetIDs: finished.compactMap { $0 })
            }
            ThreadChatMediaFiles.delete(payload.attachments?.pendingAttachments ?? [])
            return .takenBack
        }
        do {
            return .ready(mediaAssetIDs: try await uploadAll(of: payload, with: uploader, imageCache: imageCache))
        } catch is MissingFile {
            await evictFinishedUploads(of: payload, with: uploader, from: imageCache)
            return .missingFile
        }
    }

    /// Drops the cached copies of the uploads that finished for a message that will not reach
    /// the partner. Sending it again uploads under new ids, so nothing shows these. Keeps them
    /// when the server cannot say which finished.
    static func evictFinishedUploads<Payload: ChatMessagePayload & Decodable>(
        of operation: PendingSyncOperationSnapshot,
        as _: Payload.Type,
        with uploader: (any DailyAnswerMediaUploading)?,
        from imageCache: (any DailyAnswerMediaImageCacheWriting)?
    ) async {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        await evictFinishedUploads(of: payload, with: uploader, from: imageCache)
    }

    private static func evictFinishedUploads(
        of payload: some ChatMessagePayload,
        with uploader: (any DailyAnswerMediaUploading)?,
        from imageCache: (any DailyAnswerMediaImageCacheWriting)?
    ) async {
        guard let imageCache, let finished = try? await finishedUploads(of: payload, with: uploader) else { return }
        await imageCache.evict(mediaAssetIDs: finished.compactMap { $0 })
    }

    /// The person deleted the message after its send was tried (`DeleteChatMessagePayload.Target.sentBy`).
    static func isTakenBack(_ operation: PendingSyncOperationSnapshot, context: SyncContext) async -> Bool {
        let deletes = (try? await context.pendingOperationStore.inFlightOperations(
            ownerUserID: operation.ownerUserID,
            kind: .deleteThreadMessage
        )) ?? []
        return deletes.contains { delete in
            guard let data = delete.requestData,
                  let payload = try? JSONDecoder().decode(DeleteChatMessagePayload.self, from: data)
            else { return false }
            return payload.target == .sentBy(operationID: operation.operation.id)
        }
    }

    /// A send's time grows with the bytes it uploads, so a long video can finish on a slow
    /// connection.
    nonisolated static func timeLimit<Payload: ChatMessagePayload & Decodable>(
        of operation: PendingSyncOperationSnapshot,
        as _: Payload.Type
    ) -> Duration? {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        var byteCount = Int64(payload.voice?.data.count ?? 0)
        for item in payload.attachments?.items ?? [] {
            switch item.local {
            case let .bytes(bytes):
                byteCount += Int64(bytes.count)
            case let .file(name):
                let path = ThreadChatMediaFiles.url(named: name).path
                byteCount += ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?
                    .int64Value ?? 0
            }
        }
        return UploadTimeLimit.forUploading(byteCount)
    }

    /// A sent GIF's or video's file goes once the send queue saved the send. The caches
    /// already hold their copies.
    nonisolated static func deleteFiles<Payload: ChatMessagePayload & Decodable>(
        of operation: PendingSyncOperationSnapshot,
        as _: Payload.Type
    ) {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        ThreadChatMediaFiles.delete(payload.attachments?.pendingAttachments ?? [])
    }

    /// An attachment this phone no longer has, such as a video whose file was removed.
    private struct MissingFile: Error {}

    private static func uploadAll(
        of payload: some ChatMessagePayload,
        with uploader: (any DailyAnswerMediaUploading)?,
        imageCache: (any DailyAnswerMediaImageCacheWriting)?
    ) async throws -> [UUID] {
        guard payload.voice != nil || payload.attachments != nil else { return [] }
        guard let uploader else { throw ThreadChatServiceError.unavailable }
        // Read before the uploads, so a purge while they run keeps their files out of the caches.
        let generations = (
            video: await VideoFileCache.shared?.privacyGeneration ?? 0, image: PaeoniaImageMemoryCache.generation
        )
        var assetIDs: [UUID] = []
        for item in payload.attachments?.items ?? [] {
            let media = try uploadMedia(for: item)
            let assetID = try await uploader.uploadMedia(
                media,
                answerID: payload.attachments?.messageID ?? UUID(),
                coupleID: payload.coupleID,
                reserveOperation: item.reserveOperation,
                finalizeOperation: item.finalizeOperation
            )
            assetIDs.append(assetID)
            await cacheSentCopy(of: item, media: media, as: assetID, imageCache: imageCache, generations: generations)
        }
        if let voice = payload.voice {
            assetIDs.append(try await uploader.uploadMedia(
                voiceMedia(voice),
                answerID: voice.messageID,
                coupleID: payload.coupleID,
                reserveOperation: voice.reserveOperation,
                finalizeOperation: voice.finalizeOperation
            ))
        }
        return assetIDs
    }

    /// The sender's own copy then shows from this phone, with no download or flash when the
    /// server's copy of the message replaces the local one. A purge since `generations` were
    /// read keeps it out of every cache.
    private static func cacheSentCopy(
        of item: ThreadChatAttachmentsPayload.Item,
        media: DailyAnswerUploadMedia,
        as assetID: UUID,
        imageCache: (any DailyAnswerMediaImageCacheWriting)?,
        generations: (video: UInt64, image: PurgeableImageCache.Generation)
    ) async {
        let videoCache = VideoFileCache.shared
        guard (await videoCache?.privacyGeneration ?? 0) == generations.video else { return }
        switch (item.kind, item.local) {
        case let (.video, .file(name)):
            await videoCache?.store(
                ThreadChatMediaFiles.url(named: name), for: assetID, privacyGeneration: generations.video
            )
            await ThreadChatAttachmentLayout.cacheSentPoster(
                ofVideoNamed: name, for: assetID, generation: generations.image
            )
        case (.photo, _), (.gif, _), (.video, .bytes):
            await imageCache?.cacheImageData(media.data, for: assetID)
            if item.kind == .photo {
                _ = await ThreadChatAttachmentLayout.decodeAndCache(
                    media.data, key: "chat-\(assetID.uuidString)", generation: generations.image
                )
            }
        }
    }

    /// The asset ids of the uploads that finished on an earlier try, in the order `uploadAll`
    /// returns them, then nil for the first that did not. The uploads run in order, so none
    /// after it can have started, and asking about them would reserve uploads for nothing.
    /// Sends no bytes. The server can only have the message when they all finished.
    private static func finishedUploads(
        of payload: some ChatMessagePayload,
        with uploader: (any DailyAnswerMediaUploading)?
    ) async throws -> [UUID?] {
        guard payload.voice != nil || payload.attachments != nil else { return [] }
        guard let uploader else { throw ThreadChatServiceError.unavailable }
        var assetIDs: [UUID?] = []
        for item in payload.attachments?.items ?? [] {
            let assetID = try await uploader.finishedUpload(
                of: try uploadMedia(for: item, readsFile: false),
                answerID: payload.attachments?.messageID ?? UUID(),
                coupleID: payload.coupleID,
                reserveOperation: item.reserveOperation
            )
            assetIDs.append(assetID)
            if assetID == nil { return assetIDs }
        }
        if let voice = payload.voice {
            assetIDs.append(try await uploader.finishedUpload(
                of: voiceMedia(voice),
                answerID: voice.messageID,
                coupleID: payload.coupleID,
                reserveOperation: voice.reserveOperation
            ))
        }
        return assetIDs
    }

    private nonisolated static func voiceMedia(_ voice: ThreadChatVoicePayload) -> DailyAnswerUploadMedia {
        DailyAnswerUploadMedia(
            data: voice.data,
            purpose: .voice,
            mimeType: ThreadChatVoiceRecording.mimeType,
            fileExtension: ThreadChatVoiceRecording.fileExtension,
            durationMs: voice.durationMs,
            accessibilityText: voice.transcript
        )
    }

    /// What the server is told about one attachment. A GIF's or a video's bytes are mapped
    /// from its file. With `readsFile` false they stay empty, for a reservation, which sends none.
    private nonisolated static func uploadMedia(
        for item: ThreadChatAttachmentsPayload.Item,
        readsFile: Bool = true
    ) throws -> DailyAnswerUploadMedia {
        let data: Data
        switch (item.kind, item.local) {
        case let (.photo, .bytes(bytes)):
            data = bytes
        case let (.gif, .file(name)), let (.video, .file(name)):
            let url = ThreadChatMediaFiles.url(named: name)
            if !readsFile {
                data = Data()
            } else if FileManager.default.fileExists(atPath: url.path) {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } else {
                throw MissingFile()
            }
        case (.photo, .file), (.gif, .bytes), (.video, .bytes):
            throw MissingFile()
        }
        let (mimeType, fileExtension) = switch item.kind {
        case .photo: ("image/jpeg", "jpg")
        case .gif: ("image/gif", "gif")
        case .video: (MediaUpload.videoMimeType, MediaUpload.videoFileExtension)
        }
        return DailyAnswerUploadMedia(
            data: data,
            purpose: .threadPhoto,
            mimeType: mimeType,
            fileExtension: fileExtension,
            width: item.width,
            height: item.height,
            durationMs: item.kind == .video ? item.durationMs ?? 0 : nil,
            accessibilityText: item.accessibilityText
        )
    }
}
