import Foundation
import SwiftData

@Model
final class LocalMemoryRecord {
    @Attribute(.unique) var storageKey: String
    var ownerUserID: UUID
    var memoryID: UUID
    var coupleID: UUID
    var title: String?
    var memoryDate: String
    var createdByUserID: UUID
    var lastEditedByUserID: UUID
    var revision: Int
    var moderationStatusRawValue: String
    var deletedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var syncUpdatedAt: Date
    var ownNoteData: Data?
    var partnerNoteData: Data?
    var visibleMemoryMediaIDsData: Data
    var visibleMediaAssetIDsData: Data
    var mediaData: Data
    var threadID: UUID?
    var syncStatusRawValue: String
    var pendingOperationID: UUID?
    var conflictReason: String?
    var localUpdatedAt: Date

    init(
        record: MemoryRecord,
        ownNoteData: Data?,
        partnerNoteData: Data?,
        visibleMemoryMediaIDsData: Data,
        visibleMediaAssetIDsData: Data,
        mediaData: Data
    ) {
        let snapshot = record.snapshot
        storageKey = Self.storageKey(ownerUserID: snapshot.ownerUserID, memoryID: snapshot.memoryID)
        ownerUserID = snapshot.ownerUserID
        memoryID = snapshot.memoryID
        coupleID = snapshot.coupleID
        title = snapshot.title
        memoryDate = snapshot.memoryDate
        createdByUserID = snapshot.createdByUserID
        lastEditedByUserID = snapshot.lastEditedByUserID
        revision = snapshot.revision
        moderationStatusRawValue = snapshot.moderationStatus.rawValue
        deletedAt = snapshot.deletedAt
        createdAt = snapshot.createdAt
        updatedAt = snapshot.updatedAt
        syncUpdatedAt = snapshot.syncUpdatedAt
        self.ownNoteData = ownNoteData
        self.partnerNoteData = partnerNoteData
        self.visibleMemoryMediaIDsData = visibleMemoryMediaIDsData
        self.visibleMediaAssetIDsData = visibleMediaAssetIDsData
        self.mediaData = mediaData
        threadID = snapshot.threadID
        syncStatusRawValue = record.syncStatus.rawValue
        pendingOperationID = record.pendingOperationID
        conflictReason = record.conflictReason
        localUpdatedAt = record.localUpdatedAt
    }

    func update(
        from record: MemoryRecord,
        ownNoteData: Data?,
        partnerNoteData: Data?,
        visibleMemoryMediaIDsData: Data,
        visibleMediaAssetIDsData: Data,
        mediaData: Data
    ) {
        let snapshot = record.snapshot
        ownerUserID = snapshot.ownerUserID
        memoryID = snapshot.memoryID
        coupleID = snapshot.coupleID
        title = snapshot.title
        memoryDate = snapshot.memoryDate
        createdByUserID = snapshot.createdByUserID
        lastEditedByUserID = snapshot.lastEditedByUserID
        revision = snapshot.revision
        moderationStatusRawValue = snapshot.moderationStatus.rawValue
        deletedAt = snapshot.deletedAt
        createdAt = snapshot.createdAt
        updatedAt = snapshot.updatedAt
        syncUpdatedAt = snapshot.syncUpdatedAt
        self.ownNoteData = ownNoteData
        self.partnerNoteData = partnerNoteData
        self.visibleMemoryMediaIDsData = visibleMemoryMediaIDsData
        self.visibleMediaAssetIDsData = visibleMediaAssetIDsData
        self.mediaData = mediaData
        threadID = snapshot.threadID
        syncStatusRawValue = record.syncStatus.rawValue
        pendingOperationID = record.pendingOperationID
        conflictReason = record.conflictReason
        localUpdatedAt = record.localUpdatedAt
    }

    static func storageKey(ownerUserID: UUID, memoryID: UUID) -> String {
        "\(ownerUserID.uuidString.lowercased()):\(memoryID.uuidString.lowercased())"
    }
}
