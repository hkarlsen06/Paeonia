import Foundation

nonisolated struct CreateMemoryOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let coupleID: UUID
    let title: String
    let memoryDate: String
    let noteBody: String?
    let mediaAssetIDs: [UUID]
    let optimisticMedia: [MemoryMediaSnapshot]
}

nonisolated struct UpdateMemoryOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let expectedRevision: Int
    let title: String
    let memoryDate: String
}

nonisolated struct HideMemoryOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let expectedRevision: Int
}

nonisolated struct UpsertMemoryNoteOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let expectedRevision: Int?
    let body: String
}

nonisolated struct AttachMemoryMediaOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let mediaAssetIDs: [UUID]
    let optimisticMedia: [MemoryMediaSnapshot]
}

nonisolated struct RemoveMemoryMediaOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let memoryMediaID: UUID
}

nonisolated struct CreateMemoryThreadMessageOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let body: String
    let mediaAssetIDs: [UUID]
}
