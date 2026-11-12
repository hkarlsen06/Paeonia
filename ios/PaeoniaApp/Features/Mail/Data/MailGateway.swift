import Foundation

/// The letter backend functions (`backend/convex/letters.ts`). Sending needs a connection,
/// because the photo goes up first, like a story's.
nonisolated protocol MailGateway: Sendable {
    /// Uploads the photo, if any, and sends the letter. Returns it as stored, or nil when it
    /// was deleted before a retry of the same send arrived.
    func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter?
    /// Opens a letter this person received. Returns it with its note and photo.
    func open(id: UUID) async throws -> Letter
    /// Deletes one of this person's letters for both partners. A sealed one never arrives.
    func delete(id: UUID, operation: SyncClientOperation) async throws
    /// The page of `list` after `before`.
    func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage
    /// What the composer's delivery step offers at `now`.
    func deliveryOptions(at now: Date) async throws -> MailDeliveryOptions
}

nonisolated struct LiveMailGateway: MailGateway {
    let client: PaeoniaConvexClient
    let uploader: any MemoryMediaUploading

    static func live() throws -> LiveMailGateway {
        let client = try PaeoniaConvexClientProvider.shared.client()
        return LiveMailGateway(client: client, uploader: LiveMemoryMediaUploadService(client: client))
    }

    func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
        var mediaAssetID: UUID?
        if let photo {
            mediaAssetID = try await uploader.uploadMedia(
                photo,
                memoryMediaID: letter.id,
                coupleID: coupleID,
                reserveOperation: letter.operations.reserve,
                finalizeOperation: letter.operations.finalize
            ).mediaAssetID
        }
        return try await client.mutation(
            "letters:send_letter",
            args: SendLetterRequest(letter: letter, mediaAssetID: mediaAssetID)
        )
    }

    func open(id: UUID) async throws -> Letter {
        try await client.mutation("letters:open_letter", args: ["p_letter_id": id.uuidString])
    }

    func delete(id: UUID, operation: SyncClientOperation) async throws {
        try await client.mutation(
            "letters:delete_letter",
            args: DeleteLetterRequest(id: id, operation: ClientOperationFields(operation))
        )
    }

    func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage {
        try await client.query(
            "letters:get_older_letters",
            args: OlderLettersRequest(list: list, before: before, limit: limit)
        )
    }

    func deliveryOptions(at now: Date) async throws -> MailDeliveryOptions {
        try await client.query(
            "letters:get_letter_delivery_options",
            args: DeliveryOptionsRequest(now: now)
        )
    }
}

nonisolated private struct OlderLettersRequest: Encodable {
    let list: MailboxTab
    let before: LetterCursor
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case list = "p_list"
        case beforeAt = "p_before_at"
        case beforeID = "p_before_id"
        case limit = "p_limit"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(list, forKey: .list)
        try container.encode(before.at, forKey: .beforeAt)
        try container.encode(before.id, forKey: .beforeID)
        try container.encode(limit, forKey: .limit)
    }
}

nonisolated private struct DeliveryOptionsRequest: Encodable {
    let now: Date

    enum CodingKeys: String, CodingKey {
        case now = "p_now"
    }
}

nonisolated private struct SendLetterRequest: Encodable {
    let letter: LetterSend
    let mediaAssetID: UUID?

    enum CodingKeys: String, CodingKey {
        case id = "p_letter_id"
        case templateKey = "p_template_key"
        case body = "p_body"
        case mediaAssetID = "p_media_asset_id"
        case deliveryKind = "p_delivery_kind"
        case deliverAt = "p_deliver_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(letter.id, forKey: .id)
        try container.encode(letter.content.templateKey, forKey: .templateKey)
        try container.encode(letter.content.trimmedBody, forKey: .body)
        try container.encodeIfPresent(mediaAssetID, forKey: .mediaAssetID)
        try container.encode(letter.content.delivery.kind, forKey: .deliveryKind)
        if case let .at(date) = letter.content.delivery {
            try container.encode(date, forKey: .deliverAt)
        }
        try ClientOperationFields(letter.operations.send).encode(to: encoder)
    }
}

nonisolated private struct DeleteLetterRequest: Encodable {
    let id: UUID
    let operation: ClientOperationFields

    enum CodingKeys: String, CodingKey {
        case id = "p_letter_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try operation.encode(to: encoder)
    }
}
