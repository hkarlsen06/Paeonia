import Foundation

nonisolated enum PaeoniaSyncServiceDefaults {
    nonisolated struct Stores {
        let stateStore: any SyncStatePersisting
        let pendingOperationStore: any PendingSyncOperationPersisting
        let accessSnapshotStore: any AccessSyncSnapshotPersisting
        let relationshipEventStore: any RelationshipSyncEventPersisting
        let locationVisibilityStore: any LocationVisibilitySnapshotPersisting
        let ownLocationStore: any OwnLocationSnapshotPersisting
        let memoryStore: any MemoryRecordPersisting
        let privacyRecordStore: any LocalPrivacyRecordPurging
    }

    static func makeStores() -> Stores {
        guard let localStore = PaeoniaLocalStore.shared else {
            preconditionFailure("Unable to create persistent sync store")
        }

        return Stores(
            stateStore: SwiftDataSyncStateRepository(container: localStore.container),
            pendingOperationStore: SwiftDataPendingSyncOperationRepository(container: localStore.container),
            accessSnapshotStore: SwiftDataAccessSyncSnapshotRepository(container: localStore.container),
            relationshipEventStore: SwiftDataRelationshipSyncEventRepository(container: localStore.container),
            locationVisibilityStore: SwiftDataLocationVisibilityRepository(container: localStore.container),
            ownLocationStore: SwiftDataOwnLocationSnapshotRepository(container: localStore.container),
            memoryStore: SwiftDataMemoryRecordRepository(container: localStore.container),
            privacyRecordStore: SwiftDataLocalPrivacyRecordStore(container: localStore.container)
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

        var defaultHandlers = locationHandlers(
            client: client,
            visibilityStore: locationVisibilityStore,
            ownLocationStore: ownLocationStore
        )
        defaultHandlers += dailyHandlers(client: client)
        defaultHandlers += memoryHandlers(
            client: client,
            accessSnapshotStore: accessSnapshotStore,
            memoryStore: memoryStore
        )
        defaultHandlers += heartsAndDatesHandlers(client: client)
        defaultHandlers += GamesPendingOperationRegistry.handlers(client: client)

        return [
            PendingSyncOperationDrainStream(
                handlers: mergedHandlers(
                    customHandlers: pendingOperationHandlers,
                    defaultHandlers: defaultHandlers
                )
            ),
        ]
    }

    private static func locationHandlers(
        client: PaeoniaConvexClient,
        visibilityStore: any LocationVisibilitySnapshotPersisting,
        ownLocationStore: any OwnLocationSnapshotPersisting
    ) -> [any PendingSyncOperationHandling] {
        let locationGateway = LiveLocationGateway(client: client)
        return [
            LocationSharingPendingOperationHandler(
                gateway: locationGateway,
                visibilityStore: visibilityStore
            ),
            LatestLocationPendingOperationHandler(
                gateway: locationGateway,
                ownLocationStore: ownLocationStore
            ),
        ]
    }

    private static func dailyHandlers(client: PaeoniaConvexClient) -> [any PendingSyncOperationHandling] {
        let dailyQuestionChatGateway = LiveDailyQuestionChatGateway(client: client)
        let chatMediaUploader = LiveDailyAnswerMediaUploadService(
            client: client,
            reservedParentKind: "thread_message_media"
        )
        return [
            DailySubmitAnswerPendingOperationHandler(
                mediaUploadService: LiveDailyAnswerMediaUploadService(client: client),
                gateway: LiveDailyChallengeGateway(client: client),
                mediaDraftStore: FileDailyAnswerMediaDraftStore.live()
            ),
            CreateDailyChatThreadOperationHandler(
                gateway: dailyQuestionChatGateway,
                cache: FileDailyQuestionChatCache.shared,
                mediaUploadService: chatMediaUploader,
                imageCache: DailyAnswerMediaImageService.shared
            ),
            SendDailyChatMessageOperationHandler(
                gateway: dailyQuestionChatGateway,
                cache: FileDailyQuestionChatCache.shared,
                mediaUploadService: chatMediaUploader,
                imageCache: DailyAnswerMediaImageService.shared
            ),
        ]
    }

    private static func memoryHandlers(
        client: PaeoniaConvexClient,
        accessSnapshotStore: any AccessSyncSnapshotPersisting,
        memoryStore: any MemoryRecordPersisting
    ) -> [any PendingSyncOperationHandling] {
        let memoryGateway = LiveMemoryGateway(client: client)
        return [
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
    }

    private static func heartsAndDatesHandlers(client: PaeoniaConvexClient) -> [any PendingSyncOperationHandling] {
        let heartsGateway = LiveHeartsGateway(client: client)
        let coupleDatesGateway = LiveCoupleDatesGateway(client: client)
        return [
            SendHeartsPendingOperationHandler(gateway: heartsGateway),
            MarkHeartsSeenPendingOperationHandler(gateway: heartsGateway),
            SaveCountdownPendingOperationHandler(gateway: coupleDatesGateway, cache: FileCoupleDatesCache.shared),
            DeleteCountdownPendingOperationHandler(gateway: coupleDatesGateway, cache: FileCoupleDatesCache.shared),
            SetBirthdayPendingOperationHandler(gateway: coupleDatesGateway, cache: FileCoupleDatesCache.shared),
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
