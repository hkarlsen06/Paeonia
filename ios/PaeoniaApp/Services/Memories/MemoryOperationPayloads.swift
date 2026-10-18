import Foundation

nonisolated struct CreateMemoryOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let coupleID: UUID
    let title: String
    let memoryDate: String
    let noteBody: String?
    let mediaAssetIDs: [UUID]
    let optimisticMedia: [MemoryMediaSnapshot]
    let place: MemoryPlace?
}

nonisolated struct UpdateMemoryOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let expectedRevision: Int
    let title: String
    let memoryDate: String
    /// The title and date this edit started from. When the partner changed the memory
    /// in the meantime, the sync handler keeps their change for any field this edit
    /// left alone. A nil title means the memory had none.
    let baseTitle: String?
    let baseMemoryDate: String
}

/// Sets or clears (nil) the memory's place. The server keeps the newest one.
nonisolated struct SetMemoryPlaceOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let place: MemoryPlace?
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

// swiftlint:disable:next type_name
nonisolated struct CreateMemoryThreadMessageOperationPayload: Codable, Equatable, Sendable {
    let memoryID: UUID
    let body: String
    let mediaAssetIDs: [UUID]
}
