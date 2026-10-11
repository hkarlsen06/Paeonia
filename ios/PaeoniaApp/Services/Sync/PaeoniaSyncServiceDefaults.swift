import Foundation

nonisolated enum PaeoniaSyncServiceDefaults {
    typealias Stores = (
        stateStore: any SyncStatePersisting,
        pendingOperationStore: any PendingSyncOperationPersisting,
        accessSnapshotStore: any AccessSyncSnapshotPersisting,
        relationshipEventStore: any RelationshipSyncEventPersisting,
        locationVisibilityStore: any LocationVisibilitySnapshotPersisting,
        ownLocationStore: any OwnLocationSnapshotPersisting,
        memoryStore: any MemoryRecordPersisting,
        privacyRecordStore: any LocalPrivacyRecordPurging
    )

    static func makeStores() -> Stores {
        guard let localStore = PaeoniaLocalStore.shared else {
            preconditionFailure("Unable to create persistent sync store")
        }

        return (
            SwiftDataSyncStateRepository(container: localStore.container),
            SwiftDataPendingSyncOperationRepository(container: localStore.container),
            SwiftDataAccessSyncSnapshotRepository(container: localStore.container),
            SwiftDataRelationshipSyncEventRepository(container: localStore.container),
            SwiftDataLocationVisibilitySnapshotRepository(container: localStore.container),
            SwiftDataOwnLocationSnapshotRepository(container: localStore.container),
            SwiftDataMemoryRecordRepository(container: localStore.container),
            SwiftDataLocalPrivacyRecordStore(container: localStore.container)
        )
    }

    static func makeStreams(
        accessSnapshotStore: any AccessSyncSnapshotPersisting,
        locationVisibilityStore: any LocationVisibilitySnapshotPersisting,
        ownLocationStore: any OwnLocationSnapshotPersisting,
        memoryStore: any MemoryRecordPersisting,
        pendingOperationHandlers: [any PendingSyncOperationHandling] = []
    ) -> [any SyncStream] {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return []
        }

        let locationGateway = LiveLocationGateway(client: client)
        let memoryGateway = LiveMemoryGateway(client: client)
        let dailyQuestionChatGateway = LiveDailyQuestionChatGateway(client: client)
        let chatMediaUploader = LiveDailyAnswerMediaUploadService(
            client: client,
            reservedParentKind: "thread_message_media"
        )
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
                gateway: LiveDailyChallengeGateway(client: client),
                mediaDraftStore: FileDailyAnswerMediaDraftStore.live()
            ),
            CreateDailyQuestionThreadMessagePendingOperationHandler(
                gateway: dailyQuestionChatGateway,
                cache: FileDailyQuestionChatCache.shared,
                mediaUploadService: chatMediaUploader,
                imageCache: DailyAnswerMediaImageService.shared
            ),
            SendDailyQuestionThreadMessagePendingOperationHandler(
                gateway: dailyQuestionChatGateway,
                cache: FileDailyQuestionChatCache.shared,
                mediaUploadService: chatMediaUploader,
                imageCache: DailyAnswerMediaImageService.shared
            ),
            RelationshipDatePendingOperationHandler(
                gateway: LiveRelationshipStartedOnGateway(client: client),
                accessSnapshotStore: accessSnapshotStore
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
            PendingSyncOperationDrainStream(
                handlers: mergedHandlers(
                    customHandlers: pendingOperationHandlers,
                    defaultHandlers: locationHandlers
                )
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
