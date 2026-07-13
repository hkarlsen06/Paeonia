import Foundation
import SwiftData
import Testing
@testable import PaeoniaApp

struct LocalPrivacyPurgeTests {
    @Test func departingUserPurgeDeletesOnlyTheDepartingOwnersRecords() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let departingUserID = UUID()
        let remainingUserID = UUID()
        let context = ModelContext(store.container)
        try seedAllRecords(ownerUserID: departingUserID, in: context)
        try seedAllRecords(ownerUserID: remainingUserID, in: context)

        let purger = SwiftDataLocalPrivacyRecordStore(container: store.container)
        try await purger.purgeDepartingUser(ownerUserID: departingUserID)
        try await purger.purgeDepartingUser(ownerUserID: departingUserID)

        #expect(try counts(ownerUserID: departingUserID, container: store.container) == .empty)
        #expect(
            try counts(ownerUserID: remainingUserID, container: store.container)
                == .fullySeeded
        )
    }

    @Test func temporaryHidePreservesOwnedContentButPermanentLossPurgesIt() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let ownerUserID = UUID()
        let context = ModelContext(store.container)
        try seedAllRecords(ownerUserID: ownerUserID, in: context)
        let purger = SwiftDataLocalPrivacyRecordStore(container: store.container)

        try await purger.hideRelationshipAccess(ownerUserID: ownerUserID)
        try await purger.hideRelationshipAccess(ownerUserID: ownerUserID)

        #expect(
            try counts(ownerUserID: ownerUserID, container: store.container)
                == RecordCounts(
                    syncStates: 1,
                    pendingOperations: 1,
                    accessSnapshots: 1,
                    relationshipEvents: 1,
                    locationSnapshots: 0,
                    ownLocationSnapshots: 0,
                    memories: 1
                )
        )

        try await purger.purgeRelationshipContent(
            ownerUserID: ownerUserID,
            clearAccessSnapshot: false
        )
        try await purger.purgeRelationshipContent(
            ownerUserID: ownerUserID,
            clearAccessSnapshot: false
        )

        #expect(
            try counts(ownerUserID: ownerUserID, container: store.container)
                == RecordCounts(
                    syncStates: 1,
                    pendingOperations: 0,
                    accessSnapshots: 1,
                    relationshipEvents: 0,
                    locationSnapshots: 0,
                    ownLocationSnapshots: 0,
                    memories: 0
                )
        )

        try await purger.purgeRelationshipContent(
            ownerUserID: ownerUserID,
            clearAccessSnapshot: true
        )

        #expect(
            try counts(ownerUserID: ownerUserID, container: store.container)
                == RecordCounts(
                    syncStates: 1,
                    pendingOperations: 0,
                    accessSnapshots: 0,
                    relationshipEvents: 0,
                    locationSnapshots: 0,
                    ownLocationSnapshots: 0,
                    memories: 0
                )
        )
    }

    @Test func privateFilesStillPurgeWhenRecordDeletionFailsAndRetryIsIdempotent() async {
        let ownerUserID = UUID()
        let filePurger = RecordingPrivateContentPurger()
        let purger = LocalPrivacyPurgeService(
            recordStore: FailingLocalPrivacyRecordStore(),
            privateContentPurger: filePurger
        )

        await purger.purge(ownerUserID: ownerUserID, scope: .departingUser)
        await purger.purge(ownerUserID: ownerUserID, scope: .departingUser)

        #expect(
            await filePurger.calls == [
                PrivacyFilePurgeCall(ownerUserID: ownerUserID, scope: .departingUser),
                PrivacyFilePurgeCall(ownerUserID: ownerUserID, scope: .departingUser)
            ]
        )
    }

    private func seedAllRecords(ownerUserID: UUID, in context: ModelContext) throws {
        let coupleID = UUID()
        let now = Date(timeIntervalSince1970: 100)
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

        let relationshipEvent = SupabaseRelationshipSyncEvent(
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

        let memory = MemoryRecord(
            snapshot: MemorySnapshot(
                ownerUserID: ownerUserID,
                memoryID: UUID(),
                coupleID: coupleID,
                title: "Private memory",
                memoryDate: "2026-07-10",
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
                mediaData: emptyArrayData
            )
        )

        try context.save()
    }

    private func counts(
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

private enum LocalPrivacyTestError: Error {
    case simulatedFailure
}

private actor FailingLocalPrivacyRecordStore: LocalPrivacyRecordPurging {
    func purgeDepartingUser(ownerUserID _: UUID) throws {
        throw LocalPrivacyTestError.simulatedFailure
    }

    func hideRelationshipAccess(ownerUserID _: UUID) throws {
        throw LocalPrivacyTestError.simulatedFailure
    }

    func purgeRelationshipContent(
        ownerUserID _: UUID,
        clearAccessSnapshot _: Bool
    ) throws {
        throw LocalPrivacyTestError.simulatedFailure
    }
}

private struct PrivacyFilePurgeCall: Equatable, Sendable {
    let ownerUserID: UUID
    let scope: LocalPrivacyPurgeScope
}

private actor RecordingPrivateContentPurger: LocalPrivateContentPurging {
    private(set) var calls: [PrivacyFilePurgeCall] = []

    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) {
        calls.append(PrivacyFilePurgeCall(ownerUserID: ownerUserID, scope: scope))
    }
}

private struct RecordCounts: Equatable {
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
}
