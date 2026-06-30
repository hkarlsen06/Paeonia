import Foundation

nonisolated enum PaeoniaSyncServiceDefaults {
    typealias Stores = (
        stateStore: any SyncStatePersisting,
        pendingOperationStore: any PendingSyncOperationPersisting,
        accessSnapshotStore: any AccessSyncSnapshotPersisting,
        relationshipEventStore: any RelationshipSyncEventPersisting,
        locationVisibilityStore: any LocationVisibilitySnapshotPersisting,
        ownLocationStore: any OwnLocationSnapshotPersisting,
        memoryStore: any MemoryRecordPersisting
    )

    static func makeStores() -> Stores {
        do {
            let localStore = try PaeoniaLocalStore()
            return (
                SwiftDataSyncStateRepository(container: localStore.container),
                SwiftDataPendingSyncOperationRepository(container: localStore.container),
                SwiftDataAccessSyncSnapshotRepository(container: localStore.container),
                SwiftDataRelationshipSyncEventRepository(container: localStore.container),
                SwiftDataLocationVisibilitySnapshotRepository(container: localStore.container),
                SwiftDataOwnLocationSnapshotRepository(container: localStore.container),
                SwiftDataMemoryRecordRepository(container: localStore.container)
            )
        } catch {
            preconditionFailure("Unable to create persistent sync store: \(error)")
        }
    }

    static func makeStreams(
        accessSnapshotStore: any AccessSyncSnapshotPersisting,
        relationshipEventStore: any RelationshipSyncEventPersisting,
        locationVisibilityStore: any LocationVisibilitySnapshotPersisting,
        ownLocationStore: any OwnLocationSnapshotPersisting,
        memoryStore: any MemoryRecordPersisting,
        pendingOperationHandlers: [any PendingSyncOperationHandling] = []
    ) -> [any SyncStream] {
        guard let client = try? PaeoniaSupabaseClientProvider.shared.client() else {
            return []
        }

        let accessGateway = LiveSupabaseAccessGateway(client: client)
        let locationGateway = LiveSupabaseLocationGateway(client: client)
        let memoryGateway = LiveSupabaseMemoryGateway(client: client)
        let locationHandlers: [any PendingSyncOperationHandling] = [
            LocationSharingPreferencePendingOperationHandler(
                gateway: locationGateway,
                visibilityStore: locationVisibilityStore
            ),
            LatestPartnerLocationPendingOperationHandler(
                gateway: locationGateway,
                ownLocationStore: ownLocationStore
            ),
            DailySubmitAnswerPendingOperationHandler(
                mediaUploadService: LiveDailyAnswerMediaUploadService(client: client),
                gateway: LiveSupabaseDailyChallengeGateway(client: client),
                mediaDraftStore: FileDailyAnswerMediaDraftStore.live()
            ),
            CreateMemoryPendingOperationHandler(
                gateway: memoryGateway,
                memoryStore: memoryStore
            ),
            UpdateMemoryPendingOperationHandler(
                gateway: memoryGateway,
                memoryStore: memoryStore
            ),
            HideMemoryPendingOperationHandler(
                gateway: memoryGateway,
                memoryStore: memoryStore
            ),
            UpsertMemoryNotePendingOperationHandler(
                gateway: memoryGateway,
                memoryStore: memoryStore
            ),
            AttachMemoryMediaPendingOperationHandler(
                gateway: memoryGateway,
                memoryStore: memoryStore
            ),
            RemoveMemoryMediaPendingOperationHandler(
                gateway: memoryGateway,
                memoryStore: memoryStore
            ),
            CreateMemoryThreadMessagePendingOperationHandler(
                gateway: memoryGateway,
                memoryStore: memoryStore
            ),
        ]

        return [
            AccessSyncStream(
                gateway: accessGateway,
                snapshotStore: accessSnapshotStore
            ),
            RelationshipSyncEventsStream(
                gateway: accessGateway,
                eventStore: relationshipEventStore
            ),
            PendingSyncOperationDrainStream(
                handlers: mergedHandlers(
                    customHandlers: pendingOperationHandlers,
                    defaultHandlers: locationHandlers
                )
            ),
            MemorySyncStream(
                gateway: memoryGateway,
                memoryStore: memoryStore
            ),
            LocationVisibilitySyncStream(
                gateway: locationGateway,
                visibilityStore: locationVisibilityStore
            ),
        ]
    }

    private static func mergedHandlers(
        customHandlers: [any PendingSyncOperationHandling],
        defaultHandlers: [any PendingSyncOperationHandling]
    ) -> [any PendingSyncOperationHandling] {
        let customKinds = Set(customHandlers.map(\.operationKind))
        return customHandlers + defaultHandlers.filter { !customKinds.contains($0.operationKind) }
    }
}
