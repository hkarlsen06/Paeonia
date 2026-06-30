import Foundation

nonisolated struct MemoryRemoteRow: Codable, Equatable, Sendable {
    let memoryID: UUID
    let coupleID: UUID
    let title: String?
    let memoryDate: String
    let createdByUserID: UUID
    let lastEditedByUserID: UUID
    let revision: Int
    let moderationStatus: MemoryModerationStatus
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let syncUpdatedAt: Date
    let ownNoteID: UUID?
    let ownNoteBody: String?
    let ownNoteRevision: Int?
    let ownNoteUpdatedAt: Date?
    let ownNoteDeletedAt: Date?
    let ownNoteModerationStatus: MemoryModerationStatus?
    let partnerNoteID: UUID?
    let partnerNoteUserID: UUID?
    let partnerNoteBody: String?
    let partnerNoteRevision: Int?
    let partnerNoteUpdatedAt: Date?
    let partnerNoteDeletedAt: Date?
    let partnerNoteModerationStatus: MemoryModerationStatus?
    let memoryMediaIDs: [UUID]
    let mediaAssetIDs: [UUID]
    let memoryMediaStates: [MemoryMediaStateRow]
    let threadID: UUID?

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case coupleID = "couple_id"
        case title
        case memoryDate = "memory_date"
        case createdByUserID = "created_by_user_id"
        case lastEditedByUserID = "last_edited_by_user_id"
        case revision
        case moderationStatus = "moderation_status"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncUpdatedAt = "sync_updated_at"
        case ownNoteID = "own_note_id"
        case ownNoteBody = "own_note_body"
        case ownNoteRevision = "own_note_revision"
        case ownNoteUpdatedAt = "own_note_updated_at"
        case ownNoteDeletedAt = "own_note_deleted_at"
        case ownNoteModerationStatus = "own_note_moderation_status"
        case partnerNoteID = "partner_note_id"
        case partnerNoteUserID = "partner_note_user_id"
        case partnerNoteBody = "partner_note_body"
        case partnerNoteRevision = "partner_note_revision"
        case partnerNoteUpdatedAt = "partner_note_updated_at"
        case partnerNoteDeletedAt = "partner_note_deleted_at"
        case partnerNoteModerationStatus = "partner_note_moderation_status"
        case memoryMediaIDs = "memory_media_ids"
        case mediaAssetIDs = "media_asset_ids"
        case memoryMediaStates = "memory_media_states"
        case threadID = "thread_id"
    }

    func snapshot(ownerUserID: UUID) -> MemorySnapshot {
        MemorySnapshot(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            coupleID: coupleID,
            title: title,
            memoryDate: memoryDate,
            createdByUserID: createdByUserID,
            lastEditedByUserID: lastEditedByUserID,
            revision: revision,
            moderationStatus: moderationStatus,
            deletedAt: deletedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncUpdatedAt: syncUpdatedAt,
            ownNote: note(
                noteID: ownNoteID,
                userID: ownerUserID,
                body: ownNoteBody,
                revision: ownNoteRevision,
                updatedAt: ownNoteUpdatedAt,
                deletedAt: ownNoteDeletedAt,
                moderationStatus: ownNoteModerationStatus
            ),
            partnerNote: note(
                noteID: partnerNoteID,
                userID: partnerNoteUserID,
                body: partnerNoteBody,
                revision: partnerNoteRevision,
                updatedAt: partnerNoteUpdatedAt,
                deletedAt: partnerNoteDeletedAt,
                moderationStatus: partnerNoteModerationStatus
            ),
            visibleMemoryMediaIDs: memoryMediaIDs,
            visibleMediaAssetIDs: mediaAssetIDs,
            media: memoryMediaStates.map(\.snapshot),
            threadID: threadID
        )
    }

    private func note(
        noteID: UUID?,
        userID: UUID?,
        body: String?,
        revision: Int?,
        updatedAt: Date?,
        deletedAt: Date?,
        moderationStatus: MemoryModerationStatus?
    ) -> MemoryNoteSnapshot? {
        guard noteID != nil || body != nil || revision != nil || updatedAt != nil else {
            return nil
        }

        return MemoryNoteSnapshot(
            noteID: noteID,
            userID: userID,
            body: body,
            revision: revision,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            moderationStatus: moderationStatus
        )
    }
}

nonisolated struct MemoryMediaStateRow: Codable, Equatable, Sendable {
    let memoryMediaID: UUID
    let mediaAssetID: UUID
    let ownerUserID: UUID
    let sortOrder: Int
    let deletedAt: Date?
    let moderationStatus: MemoryModerationStatus
    let assetDeletedAt: Date?
    let assetModerationStatus: MemoryModerationStatus
    let assetStorageDeleteStatus: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case memoryMediaID = "memory_media_id"
        case mediaAssetID = "media_asset_id"
        case ownerUserID = "owner_user_id"
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
        case moderationStatus = "moderation_status"
        case assetDeletedAt = "asset_deleted_at"
        case assetModerationStatus = "asset_moderation_status"
        case assetStorageDeleteStatus = "asset_storage_delete_status"
        case updatedAt = "updated_at"
    }

    var snapshot: MemoryMediaSnapshot {
        MemoryMediaSnapshot(
            memoryMediaID: memoryMediaID,
            mediaAssetID: mediaAssetID,
            ownerUserID: ownerUserID,
            sortOrder: sortOrder,
            deletedAt: deletedAt,
            moderationStatus: moderationStatus,
            assetDeletedAt: assetDeletedAt,
            assetModerationStatus: assetModerationStatus,
            assetStorageDeleteStatus: assetStorageDeleteStatus,
            updatedAt: updatedAt
        )
    }
}

nonisolated struct MemoryRevisionResponse: Decodable, Equatable, Sendable {
    let memoryID: UUID
    let revision: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case revision
        case updatedAt = "updated_at"
    }
}

nonisolated struct MemoryNoteRevisionResponse: Decodable, Equatable, Sendable {
    let noteID: UUID
    let revision: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case revision
        case updatedAt = "updated_at"
    }
}

nonisolated struct MemoryThreadMessageResponse: Decodable, Equatable, Sendable {
    let threadID: UUID
    let messageID: UUID

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case messageID = "message_id"
    }
}
