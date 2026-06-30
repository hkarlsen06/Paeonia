import Foundation

nonisolated struct GetMemoriesRequest: Encodable {
    let updatedAfter: Date?
    let cursorMemoryID: UUID?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case updatedAfter = "p_updated_after"
        case cursorMemoryID = "p_cursor_memory_id"
        case limit = "p_limit"
    }
}

nonisolated struct CreateMemoryRequest: Encodable {
    let memoryID: UUID
    let title: String
    let memoryDate: String
    let noteBody: String?
    let mediaAssetIDs: [UUID]
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: CreateMemoryOperationPayload, operation: SyncClientOperation) {
        memoryID = payload.memoryID
        title = payload.title
        memoryDate = payload.memoryDate
        noteBody = payload.noteBody
        mediaAssetIDs = payload.mediaAssetIDs
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case memoryID = "p_memory_id"
        case title = "p_title"
        case memoryDate = "p_memory_date"
        case noteBody = "p_note_body"
        case mediaAssetIDs = "p_media_asset_ids"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(memoryID, forKey: .memoryID)
        try container.encode(title, forKey: .title)
        try container.encode(memoryDate, forKey: .memoryDate)
        try container.encode(noteBody, forKey: .noteBody)
        try container.encode(mediaAssetIDs, forKey: .mediaAssetIDs)
        try container.encode(clientOperationID, forKey: .clientOperationID)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(clientSequence, forKey: .clientSequence)
        try container.encode(localCreatedAt, forKey: .localCreatedAt)
    }
}

nonisolated struct UpdateMemoryRequest: Encodable {
    let memoryID: UUID
    let expectedRevision: Int
    let title: String
    let memoryDate: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: UpdateMemoryOperationPayload, operation: SyncClientOperation) {
        memoryID = payload.memoryID
        expectedRevision = payload.expectedRevision
        title = payload.title
        memoryDate = payload.memoryDate
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case memoryID = "p_memory_id"
        case expectedRevision = "p_expected_revision"
        case title = "p_title"
        case memoryDate = "p_memory_date"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated struct HideMemoryRequest: Encodable {
    let memoryID: UUID
    let expectedRevision: Int
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: HideMemoryOperationPayload, operation: SyncClientOperation) {
        memoryID = payload.memoryID
        expectedRevision = payload.expectedRevision
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case memoryID = "p_memory_id"
        case expectedRevision = "p_expected_revision"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated struct UpsertMemoryNoteRequest: Encodable {
    let memoryID: UUID
    let expectedRevision: Int?
    let body: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: UpsertMemoryNoteOperationPayload, operation: SyncClientOperation) {
        memoryID = payload.memoryID
        expectedRevision = payload.expectedRevision
        body = payload.body
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case memoryID = "p_memory_id"
        case expectedRevision = "p_expected_revision"
        case body = "p_body"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(memoryID, forKey: .memoryID)
        try container.encode(expectedRevision, forKey: .expectedRevision)
        try container.encode(body, forKey: .body)
        try container.encode(clientOperationID, forKey: .clientOperationID)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(clientSequence, forKey: .clientSequence)
        try container.encode(localCreatedAt, forKey: .localCreatedAt)
    }
}

nonisolated struct AttachMemoryMediaRequest: Encodable {
    let memoryID: UUID
    let mediaAssetIDs: [UUID]
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: AttachMemoryMediaOperationPayload, operation: SyncClientOperation) {
        memoryID = payload.memoryID
        mediaAssetIDs = payload.mediaAssetIDs
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case memoryID = "p_memory_id"
        case mediaAssetIDs = "p_media_asset_ids"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated struct RemoveMemoryMediaRequest: Encodable {
    let memoryMediaID: UUID
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: RemoveMemoryMediaOperationPayload, operation: SyncClientOperation) {
        memoryMediaID = payload.memoryMediaID
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case memoryMediaID = "p_memory_media_id"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated struct CreateMemoryThreadMessageRequest: Encodable {
    let memoryID: UUID
    let body: String
    let mediaAssetIDs: [UUID]
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: CreateMemoryThreadMessageOperationPayload, operation: SyncClientOperation) {
        memoryID = payload.memoryID
        body = payload.body
        mediaAssetIDs = payload.mediaAssetIDs
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case memoryID = "p_memory_id"
        case body = "p_body"
        case mediaAssetIDs = "p_media_asset_ids"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}
