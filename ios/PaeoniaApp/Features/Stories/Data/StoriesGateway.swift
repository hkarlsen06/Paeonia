import Foundation

/// The story backend functions (`backend/convex/stories.ts`). Posting needs a connection,
/// because the photo goes up first, like a memory photo.
nonisolated protocol StoriesGateway: Sendable {
    /// Uploads the photo and posts the story. Returns the story as stored, or nil when it
    /// was deleted before a retry of the same post arrived.
    func post(
        id: UUID,
        photo: MemoryUploadMedia,
        caption: String?,
        coupleID: UUID,
        operations: StoryPostOperations
    ) async throws -> Story?
    /// Deletes one of this person's stories for both partners.
    func delete(id: UUID, operation: SyncClientOperation) async throws
    /// Tells the server the partner's story was opened. The server keeps the first time.
    func markSeen(id: UUID) async throws
    /// Sets this person's note, or removes it when `text` is nil. Returns the note as stored.
    func setNote(_ text: String?, operation: SyncClientOperation) async throws -> StoryNote?
}

/// The client operations of one post. A retry after a failure reuses them, so the
/// server sees the same reservation and the same post again.
nonisolated struct StoryPostOperations: Sendable {
    let reserve: SyncClientOperation
    let finalize: SyncClientOperation
    let post: SyncClientOperation
}

nonisolated struct LiveStoriesGateway: StoriesGateway {
    let client: PaeoniaConvexClient
    let uploader: any MemoryMediaUploading

    static func live() throws -> LiveStoriesGateway {
        let client = try PaeoniaConvexClientProvider.shared.client()
        return LiveStoriesGateway(client: client, uploader: LiveMemoryMediaUploadService(client: client))
    }

    func post(
        id: UUID,
        photo: MemoryUploadMedia,
        caption: String?,
        coupleID: UUID,
        operations: StoryPostOperations
    ) async throws -> Story? {
        let upload = try await uploader.uploadMedia(
            photo,
            memoryMediaID: id,
            coupleID: coupleID,
            reserveOperation: operations.reserve,
            finalizeOperation: operations.finalize
        )
        return try await client.mutation(
            "stories:post_story",
            args: PostStoryRequest(
                id: id,
                mediaAssetID: upload.mediaAssetID,
                caption: caption,
                operation: GameClientOperationFields(operations.post)
            )
        )
    }

    func delete(id: UUID, operation: SyncClientOperation) async throws {
        try await client.mutation(
            "stories:delete_story",
            args: DeleteStoryRequest(id: id, operation: GameClientOperationFields(operation))
        )
    }

    func markSeen(id: UUID) async throws {
        try await client.mutation("stories:mark_story_seen", args: ["p_story_id": id.uuidString])
    }

    func setNote(_ text: String?, operation: SyncClientOperation) async throws -> StoryNote? {
        try await client.mutation(
            "stories:set_note",
            args: SetNoteRequest(text: text, operation: GameClientOperationFields(operation))
        )
    }
}

nonisolated private struct SetNoteRequest: Encodable {
    let text: String?
    let operation: GameClientOperationFields

    enum CodingKeys: String, CodingKey {
        case text = "p_text"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // `null` removes the note, so it is sent rather than left out.
        try container.encode(text, forKey: .text)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct PostStoryRequest: Encodable {
    let id: UUID
    let mediaAssetID: UUID
    let caption: String?
    let operation: GameClientOperationFields

    enum CodingKeys: String, CodingKey {
        case id = "p_story_id"
        case mediaAssetID = "p_media_asset_id"
        case caption = "p_caption"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mediaAssetID, forKey: .mediaAssetID)
        try container.encodeIfPresent(caption, forKey: .caption)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct DeleteStoryRequest: Encodable {
    let id: UUID
    let operation: GameClientOperationFields

    enum CodingKeys: String, CodingKey {
        case id = "p_story_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try operation.encode(to: encoder)
    }
}
