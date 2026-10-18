import Foundation
import SwiftData
@testable import PaeoniaApp

extension LocalPrivacyPurgeTests {
    func seedAllRecords(ownerUserID: UUID, in context: ModelContext) throws {
        let coupleID = UUID()
        let now = Date(timeIntervalSince1970: 100)
        insertSyncRecords(ownerUserID: ownerUserID, coupleID: coupleID, now: now, in: context)
        try insertRelationshipEvent(ownerUserID: ownerUserID, coupleID: coupleID, now: now, in: context)
        insertLocationRecords(ownerUserID: ownerUserID, coupleID: coupleID, now: now, in: context)
        insertMemoryRecord(ownerUserID: ownerUserID, coupleID: coupleID, now: now, in: context)
        try context.save()
    }

    private func insertSyncRecords(ownerUserID: UUID, coupleID: UUID, now: Date, in context: ModelContext) {
        context.insert(
            LocalSyncState(
                ownerUserID: ownerUserID,
                scopeKind: .user,
                streamKey: .profile
            )
        )
        context.insert(
            LocalSyncState(
                ownerUserID: ownerUserID,
                scopeKind: .couple,
                scopeID: coupleID,
                streamKey: .memories
            )
        )
        let operation = SyncClientOperation(
            clientID: ownerUserID,
            clientSequence: 1,
            localCreatedAt: now
        )
        context.insert(
            LocalPendingSyncOperation(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "daily:\(coupleID.uuidString)",
                requestData: Data("private answer".utf8)
            )
        )
        context.insert(LocalAccessSyncSnapshot(ownerUserID: ownerUserID, refreshedAt: now))
    }

    private func insertRelationshipEvent(
        ownerUserID: UUID,
        coupleID: UUID,
        now: Date,
        in context: ModelContext
    ) throws {
        let relationshipEvent = RemoteRelationshipSyncEvent(
            id: UUID(),
            userID: ownerUserID,
            coupleID: coupleID,
            initiatedByUserID: nil,
            eventKind: "relationship_ended",
            reason: "left_relationship",
            occurredAt: now,
            relationshipStatus: "ended",
            memberStatus: "ended_notice_pending",
            endedAt: now,
            deleteAfter: now.addingTimeInterval(2_592_000),
            localPurgeScope: ["relationship_content": "hide"],
            createdAt: now,
            updatedAt: now
        )
        context.insert(
            LocalRelationshipSyncEvent(
                event: relationshipEvent,
                localPurgeScopeData: try JSONEncoder().encode(relationshipEvent.localPurgeScope)
            )
        )
    }

    private func insertLocationRecords(ownerUserID: UUID, coupleID: UUID, now: Date, in context: ModelContext) {
        let location = LocationPoint(
            latitude: 59.91,
            longitude: 10.75,
            capturedAt: now
        )
        context.insert(
            LocalLocationVisibilitySnapshot(
                snapshot: LocationVisibilitySnapshot(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID,
                    viewerUserID: ownerUserID,
                    partnerUserID: UUID(),
                    visibilityState: .visible,
                    viewerSharingEnabled: true,
                    partnerSharingEnabled: true,
                    partnerLocation: location,
                    partnerLocationIsStale: false,
                    updatedAt: now,
                    refreshedAt: now
                )
            )
        )
        context.insert(
            LocalOwnLocationSnapshot(
                snapshot: OwnLocationSnapshot(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID,
                    location: location,
                    source: .foregroundOpen,
                    pendingOperationID: nil,
                    updatedAt: now
                )
            )
        )
    }

    private func insertMemoryRecord(ownerUserID: UUID, coupleID: UUID, now: Date, in context: ModelContext) {
        let memory = MemoryRecord(
            snapshot: MemorySnapshot(
                ownerUserID: ownerUserID,
                memoryID: UUID(),
                coupleID: coupleID,
                title: "Private memory",
                memoryDate: "2026-07-10",
                place: nil,
                createdByUserID: ownerUserID,
                lastEditedByUserID: ownerUserID,
                revision: 1,
                moderationStatus: .visible,
                deletedAt: nil,
                createdAt: now,
                updatedAt: now,
                syncUpdatedAt: now,
                ownNote: nil,
                partnerNote: nil,
                visibleMemoryMediaIDs: [],
                visibleMediaAssetIDs: [],
                media: [],
                threadID: nil
            )
        )
        let emptyArrayData = Data("[]".utf8)
        context.insert(
            LocalMemoryRecord(
                record: memory,
                ownNoteData: nil,
                partnerNoteData: nil,
                visibleMemoryMediaIDsData: emptyArrayData,
                visibleMediaAssetIDsData: emptyArrayData,
                mediaData: emptyArrayData,
                placeData: nil
            )
        )
    }

    func counts(
        ownerUserID: UUID,
        container: ModelContainer
    ) throws -> RecordCounts {
        let context = ModelContext(container)
        return try RecordCounts(
            syncStates: context.fetchCount(
                FetchDescriptor<LocalSyncState>(
                    predicate: #Predicate { value in value.ownerUserID == ownerUserID }
                )
            ),
            pendingOperations: context.fetchCount(
                FetchDescriptor<LocalPendingSyncOperation>(
                    predicate: #Predicate { value in value.ownerUserID == ownerUserID }
                )
            ),
            accessSnapshots: context.fetchCount(
                FetchDescriptor<LocalAccessSyncSnapshot>(
                    predicate: #Predicate { value in value.ownerUserID == ownerUserID }
                )
            ),
            relationshipEvents: context.fetchCount(
                FetchDescriptor<LocalRelationshipSyncEvent>(
                    predicate: #Predicate { value in value.ownerUserID == ownerUserID }
                )
            ),
            locationSnapshots: context.fetchCount(
                FetchDescriptor<LocalLocationVisibilitySnapshot>(
                    predicate: #Predicate { value in value.ownerUserID == ownerUserID }
                )
            ),
            ownLocationSnapshots: context.fetchCount(
                FetchDescriptor<LocalOwnLocationSnapshot>(
                    predicate: #Predicate { value in value.ownerUserID == ownerUserID }
                )
            ),
            memories: context.fetchCount(
                FetchDescriptor<LocalMemoryRecord>(
                    predicate: #Predicate { value in value.ownerUserID == ownerUserID }
                )
            )
        )
    }
}

struct RecordCounts: Equatable {
    let syncStates: Int
    let pendingOperations: Int
    let accessSnapshots: Int
    let relationshipEvents: Int
    let locationSnapshots: Int
    let ownLocationSnapshots: Int
    let memories: Int

    static let empty = RecordCounts(
        syncStates: 0,
        pendingOperations: 0,
        accessSnapshots: 0,
        relationshipEvents: 0,
        locationSnapshots: 0,
        ownLocationSnapshots: 0,
        memories: 0
    )

    static let fullySeeded = RecordCounts(
        syncStates: 2,
        pendingOperations: 1,
        accessSnapshots: 1,
        relationshipEvents: 1,
        locationSnapshots: 1,
        ownLocationSnapshots: 1,
        memories: 1
    )

    /// Hiding the relationship keeps the owner's content but drops shared location rows.
    static let afterHide = RecordCounts(
        syncStates: 1,
        pendingOperations: 1,
        accessSnapshots: 1,
        relationshipEvents: 1,
        locationSnapshots: 0,
        ownLocationSnapshots: 0,
        memories: 1
    )

    /// Losing the relationship for good clears content but keeps the access snapshot.
    static let afterContentPurge = RecordCounts(
        syncStates: 1,
        pendingOperations: 0,
        accessSnapshots: 1,
        relationshipEvents: 0,
        locationSnapshots: 0,
        ownLocationSnapshots: 0,
        memories: 0
    )

    static let afterFullPurge = RecordCounts(
        syncStates: 1,
        pendingOperations: 0,
        accessSnapshots: 0,
        relationshipEvents: 0,
        locationSnapshots: 0,
        ownLocationSnapshots: 0,
        memories: 0
    )
}
