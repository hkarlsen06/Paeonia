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
    /// The title and date this edit started from. When the partner changed the memory
    /// in the meantime, the sync handler keeps their change for any field this edit
    /// left alone. Nil in operations queued before these fields existed; those resend
    /// both fields as they are.
    var baseTitle: String?
    var baseMemoryDate: String?

    init(
        memoryID: UUID,
        expectedRevision: Int,
        title: String,
        memoryDate: String,
        baseTitle: String? = nil,
        baseMemoryDate: String? = nil
    ) {
        self.memoryID = memoryID
        self.expectedRevision = expectedRevision
        self.title = title
        self.memoryDate = memoryDate
        self.baseTitle = baseTitle
        self.baseMemoryDate = baseMemoryDate
    }
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
