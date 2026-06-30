import Foundation

nonisolated enum MemoryModerationStatus: Codable, Equatable, Sendable {
    case pendingReview
    case visible
    case hidden
    case removed
    case rejected
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "pending_review":
            self = .pendingReview
        case "visible":
            self = .visible
        case "hidden":
            self = .hidden
        case "removed":
            self = .removed
        case "rejected":
            self = .rejected
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .pendingReview:
            "pending_review"
        case .visible:
            "visible"
        case .hidden:
            "hidden"
        case .removed:
            "removed"
        case .rejected:
            "rejected"
        case let .unknown(rawValue):
            rawValue
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct MemoryNoteSnapshot: Codable, Equatable, Sendable {
    let noteID: UUID?
    let userID: UUID?
    let body: String?
    let revision: Int?
    let updatedAt: Date?
    let deletedAt: Date?
    let moderationStatus: MemoryModerationStatus?

    init(
        noteID: UUID?,
        userID: UUID?,
        body: String?,
        revision: Int?,
        updatedAt: Date?,
        deletedAt: Date?,
        moderationStatus: MemoryModerationStatus?
    ) {
        self.noteID = noteID
        self.userID = userID
        self.body = body
        self.revision = revision
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.moderationStatus = moderationStatus
    }

    var isVisible: Bool {
        deletedAt == nil && moderationStatus == .visible
    }
}

nonisolated struct MemoryMediaSnapshot: Codable, Equatable, Sendable {
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

    init(
        memoryMediaID: UUID,
        mediaAssetID: UUID,
        ownerUserID: UUID,
        sortOrder: Int,
        deletedAt: Date? = nil,
        moderationStatus: MemoryModerationStatus = .visible,
        assetDeletedAt: Date? = nil,
        assetModerationStatus: MemoryModerationStatus = .visible,
        assetStorageDeleteStatus: String = "none",
        updatedAt: Date
    ) {
        self.memoryMediaID = memoryMediaID
        self.mediaAssetID = mediaAssetID
        self.ownerUserID = ownerUserID
        self.sortOrder = sortOrder
        self.deletedAt = deletedAt
        self.moderationStatus = moderationStatus
        self.assetDeletedAt = assetDeletedAt
        self.assetModerationStatus = assetModerationStatus
        self.assetStorageDeleteStatus = assetStorageDeleteStatus
        self.updatedAt = updatedAt
    }

    var isVisible: Bool {
        deletedAt == nil
            && moderationStatus == .visible
            && assetDeletedAt == nil
            && assetModerationStatus == .visible
            && assetStorageDeleteStatus == "none"
    }
}

nonisolated struct MemorySnapshot: Codable, Equatable, Sendable {
    let ownerUserID: UUID
    let memoryID: UUID
    let coupleID: UUID
    let title: String?
    /// ISO `yyyy-MM-dd` couple-local date from the backend `date` column.
    let memoryDate: String
    let createdByUserID: UUID
    let lastEditedByUserID: UUID
    let revision: Int
    let moderationStatus: MemoryModerationStatus
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let syncUpdatedAt: Date
    let ownNote: MemoryNoteSnapshot?
    let partnerNote: MemoryNoteSnapshot?
    let visibleMemoryMediaIDs: [UUID]
    let visibleMediaAssetIDs: [UUID]
    let media: [MemoryMediaSnapshot]
    let threadID: UUID?

    init(
        ownerUserID: UUID,
        memoryID: UUID,
        coupleID: UUID,
        title: String?,
        memoryDate: String,
        createdByUserID: UUID,
        lastEditedByUserID: UUID,
        revision: Int,
        moderationStatus: MemoryModerationStatus,
        deletedAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        syncUpdatedAt: Date,
        ownNote: MemoryNoteSnapshot?,
        partnerNote: MemoryNoteSnapshot?,
        visibleMemoryMediaIDs: [UUID],
        visibleMediaAssetIDs: [UUID],
        media: [MemoryMediaSnapshot],
        threadID: UUID?
    ) {
        self.ownerUserID = ownerUserID
        self.memoryID = memoryID
        self.coupleID = coupleID
        self.title = title
        self.memoryDate = memoryDate
        self.createdByUserID = createdByUserID
        self.lastEditedByUserID = lastEditedByUserID
        self.revision = revision
        self.moderationStatus = moderationStatus
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncUpdatedAt = syncUpdatedAt
        self.ownNote = ownNote
        self.partnerNote = partnerNote
        self.visibleMemoryMediaIDs = visibleMemoryMediaIDs
        self.visibleMediaAssetIDs = visibleMediaAssetIDs
        self.media = media
        self.threadID = threadID
    }

    var isVisible: Bool {
        deletedAt == nil && moderationStatus == .visible
    }
}

nonisolated struct MemoryRecord: Codable, Equatable, Sendable {
    var snapshot: MemorySnapshot
    var syncStatus: SyncRecordStatus
    var pendingOperationID: UUID?
    var conflictReason: String?
    var localUpdatedAt: Date

    init(
        snapshot: MemorySnapshot,
        syncStatus: SyncRecordStatus = .clean,
        pendingOperationID: UUID? = nil,
        conflictReason: String? = nil,
        localUpdatedAt: Date = Date()
    ) {
        self.snapshot = snapshot
        self.syncStatus = syncStatus
        self.pendingOperationID = pendingOperationID
        self.conflictReason = conflictReason
        self.localUpdatedAt = localUpdatedAt
    }
}
