import Foundation

nonisolated enum LocalPrivacyPurgeScope: Codable, Equatable, Sendable {
    case departingUser
    case relationshipAccessHidden
    case relationshipContentPurged(clearAccessSnapshot: Bool)
}

nonisolated protocol LocalPrivacyPurging: Sendable {
    @discardableResult
    func purge(
        ownerUserID: UUID,
        scope: LocalPrivacyPurgeScope
    ) async -> LocalPrivacyPurgeResult

    @discardableResult
    func retryPendingPurges() async -> LocalPrivacyPurgeRetryResult
}

extension LocalPrivacyPurging {
    @discardableResult
    // swiftlint:disable:next async_without_await
    func retryPendingPurges() async -> LocalPrivacyPurgeRetryResult {
        .completed
    }
}

nonisolated protocol LocalPrivateContentPurging: Sendable {
    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) async
    /// Deletes the private media files on disk. A failure leaves the purge request
    /// queued, so the next retry deletes them again.
    func removePrivateFiles() async throws
}

actor LocalPrivacyPurgeService: LocalPrivacyPurging {
    private let recordStore: any LocalPrivacyRecordPurging
    private let privateContentPurger: any LocalPrivateContentPurging
    private let entityIndex: any SiriEntityIndexClearing
    private let retryStore: any LocalPrivacyPurgeRetryStoring
    private let retryDelay: Duration
    private let automaticallyRetry: Bool
    private var scheduledRetry: Task<Void, Never>?
    private var volatileRetryRequests: [UUID: LocalPrivacyPurgeRequest] = [:]

    init(
        recordStore: any LocalPrivacyRecordPurging,
        privateContentPurger: any LocalPrivateContentPurging = LiveLocalPrivateContentPurger(),
        entityIndex: any SiriEntityIndexClearing = SiriEntityIndexer.shared,
        retryStore: any LocalPrivacyPurgeRetryStoring = UserDefaultsLocalPrivacyPurgeRetryStore.shared,
        retryDelay: Duration = .seconds(30),
        automaticallyRetry: Bool = true
    ) {
        self.recordStore = recordStore
        self.privateContentPurger = privateContentPurger
        self.entityIndex = entityIndex
        self.retryStore = retryStore
        self.retryDelay = retryDelay
        self.automaticallyRetry = automaticallyRetry
    }

    @discardableResult
    func purge(
        ownerUserID: UUID,
        scope: LocalPrivacyPurgeScope
    ) async -> LocalPrivacyPurgeResult {
        LocalPrivacyWriteGuard.shared.invalidate(ownerUserID: ownerUserID)
        await MediaAlternativeCacheWrites.shared.clear(ownerUserID: ownerUserID)
        var request = LocalPrivacyPurgeRequest(ownerUserID: ownerUserID, scope: scope)
        if let volatileRequest = volatileRetryRequests[ownerUserID] {
            request = volatileRequest.merging(request)
        }
        let requestWasPersisted: Bool
        do {
            try await retryStore.enqueue(request)
            volatileRetryRequests[ownerUserID] = nil
            requestWasPersisted = true
        } catch {
            requestWasPersisted = false
        }

        await privateContentPurger.purge(ownerUserID: ownerUserID, scope: scope)

        guard requestWasPersisted else {
            do {
                try await purgeRetryably(for: request)
                return .completed
            } catch {
                volatileRetryRequests[ownerUserID] = request
                scheduleRetryIfNeeded()
                return .recordsFailedWithoutDurableRetry
            }
        }

        _ = await retryPendingPurges()
        do {
            let pendingRequest = try await retryStore.request(for: ownerUserID)
            return pendingRequest == nil ? .completed : .recordsPendingRetry
        } catch {
            scheduleRetryIfNeeded()
            return .recordsPendingRetry
        }
    }

    @discardableResult
    func retryPendingPurges() async -> LocalPrivacyPurgeRetryResult {
        var hasFailure = false
        for request in Array(volatileRetryRequests.values) {
            do {
                try await purgeRetryably(for: request)
                volatileRetryRequests[request.ownerUserID] = nil
            } catch {
                hasFailure = true
            }
        }

        let pendingRequests: [LocalPrivacyPurgeRequest]
        do {
            pendingRequests = try await retryStore.pendingRequests()
        } catch {
            scheduleRetryIfNeeded()
            return .recordsPendingRetry
        }

        for request in pendingRequests {
            do {
                try await purgeRetryably(for: request)
                try await retryStore.remove(request)
            } catch {
                hasFailure = true
            }
        }

        let stillHasPendingRequests: Bool
        do {
            let remainingRequests = try await retryStore.pendingRequests()
            stillHasPendingRequests = !remainingRequests.isEmpty
        } catch {
            stillHasPendingRequests = true
        }

        if hasFailure || stillHasPendingRequests {
            scheduleRetryIfNeeded()
            return .recordsPendingRetry
        }
        return .completed
    }

    private func purgeRetryably(for request: LocalPrivacyPurgeRequest) async throws {
        var fileFailure: (any Error)?
        do {
            try await privateContentPurger.removePrivateFiles()
        } catch {
            fileFailure = error
        }
        switch request.scope {
        case .departingUser:
            try await recordStore.purgeDepartingUser(ownerUserID: request.ownerUserID)
        case .relationshipAccessHidden:
            try await recordStore.hideRelationshipAccess(ownerUserID: request.ownerUserID)
        case let .relationshipContentPurged(clearAccessSnapshot):
            try await recordStore.purgeRelationshipContent(
                ownerUserID: request.ownerUserID,
                clearAccessSnapshot: clearAccessSnapshot
            )
        }
        // Every scope hides the couple's content, so Spotlight and Siri forget all of it. A
        // failure keeps the request queued, and the retry removes both again.
        await MainActor.run {
            SiriAppContext.shared.messageDraft = nil
            SiriAppContext.shared.dailyChallenge = nil
        }
        try await entityIndex.removeAllEntities()
        if let fileFailure { throw fileFailure }
    }

    private func scheduleRetryIfNeeded() {
        guard automaticallyRetry, scheduledRetry == nil else {
            return
        }
        scheduledRetry = Task { [weak self, retryDelay] in
            try? await Task.sleep(for: retryDelay)
            guard !Task.isCancelled else {
                return
            }
            await self?.runScheduledRetry()
        }
    }

    private func runScheduledRetry() async {
        scheduledRetry = nil
        _ = await retryPendingPurges()
    }
}

actor NoOpLocalPrivacyPurger: LocalPrivacyPurging {
    func purge(
        ownerUserID: UUID,
        scope: LocalPrivacyPurgeScope
    ) -> LocalPrivacyPurgeResult {
        .completed
    }
}

actor LiveLocalPrivateContentPurger: LocalPrivateContentPurging {
    private let widgetSync: any WidgetCanvasSyncing
    private let widgetCanvas: any WidgetCanvasManaging
    private let partnerAvatar: (any PartnerAvatarSharing)?
    private let dailyAnswerMediaCache: (any DailyAnswerMediaCacheClearing)?
    private let memoryMediaCache: (any MemoryMediaImageCacheClearing)?
    private let profilePhotoCache: (any ProfilePhotoImageCacheClearing)?
    private let dailyAnswerMediaDraftStore: any DailyAnswerMediaDraftStoring
    private let dailyChallengeSnapshotCache: any DailyChallengeSnapshotCaching
    private let threadChatCache: any ThreadChatCaching
    private let gamesCache: any GamesCaching
    private let storyChainCache: any StoryChainCaching
    private let exquisiteCorpseCache: any ExquisiteCorpseCaching
    private let boardGamesCache: any BoardGamesCaching
    private let gameDrawingStore: any GameDrawingStoring
    private let mindMeldCache: any MindMeldCaching
    private let consensioCache: any ConsensioCaching
    private let guessMySpotCache: any GuessMySpotCaching
    private let guessMySpotPhotos: any GuessMySpotPhotoStoring
    private let lookBackCache: any LookBackCaching
    private let heartsCache: any HeartsCaching
    private let coupleDatesCache: any CoupleDatesCaching
    private let visitsCache: any VisitsCaching
    private let favoritesCache: any FavoritesCaching
    private let storiesCache: any StoriesCaching
    private let mailCache: any MailCaching
    private let reactionsCache: any ReactionsCaching
    private let topicsCache: any TopicsCaching
    private let profilePhotoDiskCache: any ProfilePhotoImageCaching
    private let temporaryDirectory: URL

    init(
        widgetSync: any WidgetCanvasSyncing = WidgetCanvasSyncServiceFactory.shared,
        widgetCanvas: any WidgetCanvasManaging = WidgetCanvasService.shared,
        partnerAvatar: (any PartnerAvatarSharing)? = PartnerAvatarSharingServiceFactory.shared,
        dailyAnswerMediaCache: (any DailyAnswerMediaCacheClearing)? = DailyAnswerMediaImageService.shared,
        memoryMediaCache: (any MemoryMediaImageCacheClearing)? = MemoryMediaImageService.shared,
        profilePhotoCache: (any ProfilePhotoImageCacheClearing)? = ProfilePhotoImageService.shared,
        dailyAnswerMediaDraftStore: any DailyAnswerMediaDraftStoring = FileDailyAnswerMediaDraftStore.live(),
        dailyChallengeSnapshotCache: any DailyChallengeSnapshotCaching = FileDailyChallengeSnapshotCache.live(),
        threadChatCache: any ThreadChatCaching = FileThreadChatCache.shared,
        gamesCache: any GamesCaching = FileGamesCache.shared,
        storyChainCache: any StoryChainCaching = FileStoryChainCache.shared,
        exquisiteCorpseCache: any ExquisiteCorpseCaching = FileExquisiteCorpseCache.shared,
        boardGamesCache: any BoardGamesCaching = FileBoardGamesCache.shared,
        gameDrawingStore: any GameDrawingStoring = FileGameDrawingStore.shared,
        mindMeldCache: any MindMeldCaching = FileMindMeldCache.shared,
        consensioCache: any ConsensioCaching = FileConsensioCache.shared,
        guessMySpotCache: any GuessMySpotCaching = FileGuessMySpotCache.shared,
        guessMySpotPhotos: any GuessMySpotPhotoStoring = FileGuessMySpotPhotoStore.shared,
        lookBackCache: any LookBackCaching = FileLookBackCache.shared,
        heartsCache: any HeartsCaching = FileHeartsCache.shared,
        coupleDatesCache: any CoupleDatesCaching = FileCoupleDatesCache.shared,
        visitsCache: any VisitsCaching = FileVisitsCache.shared,
        favoritesCache: any FavoritesCaching = FileFavoritesCache.shared,
        storiesCache: any StoriesCaching = FileStoriesCache.shared,
        mailCache: any MailCaching = FileMailCache.shared,
        reactionsCache: any ReactionsCaching = FileReactionsCache.shared,
        topicsCache: any TopicsCaching = FileTopicsCache.shared,
        profilePhotoDiskCache: any ProfilePhotoImageCaching = FileProfilePhotoImageCache.live(),
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.widgetSync = widgetSync
        self.widgetCanvas = widgetCanvas
        self.partnerAvatar = partnerAvatar
        self.dailyAnswerMediaCache = dailyAnswerMediaCache
        self.memoryMediaCache = memoryMediaCache
        self.profilePhotoCache = profilePhotoCache
        self.dailyAnswerMediaDraftStore = dailyAnswerMediaDraftStore
        self.dailyChallengeSnapshotCache = dailyChallengeSnapshotCache
        self.threadChatCache = threadChatCache
        self.gamesCache = gamesCache
        self.storyChainCache = storyChainCache
        self.exquisiteCorpseCache = exquisiteCorpseCache
        self.boardGamesCache = boardGamesCache
        self.gameDrawingStore = gameDrawingStore
        self.mindMeldCache = mindMeldCache
        self.consensioCache = consensioCache
        self.guessMySpotCache = guessMySpotCache
        self.guessMySpotPhotos = guessMySpotPhotos
        self.lookBackCache = lookBackCache
        self.heartsCache = heartsCache
        self.coupleDatesCache = coupleDatesCache
        self.visitsCache = visitsCache
        self.favoritesCache = favoritesCache
        self.storiesCache = storiesCache
        self.mailCache = mailCache
        self.reactionsCache = reactionsCache
        self.topicsCache = topicsCache
        self.profilePhotoDiskCache = profilePhotoDiskCache
        self.temporaryDirectory = temporaryDirectory
    }

    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) async {
        let savedDrawing = await widgetCanvas.loadSavedDrawing()
        let keepsFirstDayUpload = Self.keepsUnsentFirstDayDrawing(
            scope: scope,
            pending: WidgetPendingUploadStore.shared.pendingSnapshot,
            savedDrawing: savedDrawing
        )
        await purgeWidgetsAndMediaCaches(scope: scope, keepsSavedDrawing: keepsFirstDayUpload)
        await purgeContentCaches(scope: scope)

        WidgetSyncIdentityStore.shared.clear()
        WidgetCanvasSyncService.clearPersistedState()
        // Delivered alerts name the partner and point into this relationship.
        DeliveredNotifications.clearAll()

        let shouldPurgeOwnedContent = scope != .relationshipAccessHidden
        if shouldPurgeOwnedContent {
            FileThreadChatVoiceDraftStore.shared.clearAll()
            FileThreadChatPhotoDraftStore.shared.clearAll()
            dailyAnswerMediaDraftStore.clearAll()
            await mailCache.clearDrafts()
            Self.removeTemporaryVoiceFiles(in: temporaryDirectory)
            MemoryPhotoInbox.clearAll()
            if !keepsFirstDayUpload {
                WidgetPendingUploadStore.shared.clearAll()
            }
        }

        await MainActor.run {
            // Location updates while closed belong to this account and couple.
            LocationUpdateController.shared.resetUpdatesWhileClosed()
            LatestWidgetDrawing.shared.clear()
            if shouldPurgeOwnedContent {
                UserDefaultsDailyChallengeDraftStore.shared.clearDrafts(for: ownerUserID)
                LocalMemoryDraftStore.shared.clearDraft(for: ownerUserID)
                FileWidgetDrawingDraftStore.shared.clearDraft(for: ownerUserID)
                UserDefaultsPairingCelebrationStore.shared.clearAll()
            }
            if scope == .departingUser {
                UserDefaultsPairingInviteStore.shared.clearInvite(
                    for: ownerUserID.uuidString
                )
                UserDefaultsPairingJoinInviteStore.shared.clearInviteCode()
                PushRegistrationFingerprintStore.resetAll()
                // A sign-in token for the account that is leaving.
                ConvexTokenStore.clear()
                ReactionPalette.shared.clearAll()
                // The next person on this phone starts without the lock.
                AppLockModel.shared.reset()
                // First day text belongs to no couple, so only sign-out clears it.
                UserDefaultsFirstDayAnswerDraftStore.shared.clearAll(for: ownerUserID)
            }
        }
    }

    /// An ended relationship purges again on each access check while its row lasts on
    /// the server. The inviter's first drawing that has not reached the server yet belongs
    /// to no couple and was never shared, so that purge keeps it on this phone with its
    /// "not sent yet" marker, and it can still go out. The widget files go as usual.
    /// Sign-out clears it.
    nonisolated static func keepsUnsentFirstDayDrawing(
        scope: LocalPrivacyPurgeScope,
        pending: WidgetPendingUploadSnapshot?,
        savedDrawing: Data?
    ) -> Bool {
        guard case .relationshipContentPurged = scope,
              let pending, pending.isFirstDay,
              let savedDrawing
        else {
            return false
        }
        return WidgetCanvasUploadService.sha256Hex(of: savedDrawing) == pending.contentHash
    }

    /// `keepsSavedDrawing` removes only what the widget shows, like a hide.
    private func purgeWidgetsAndMediaCaches(scope: LocalPrivacyPurgeScope, keepsSavedDrawing: Bool) async {
        if scope == .relationshipAccessHidden || keepsSavedDrawing {
            await widgetSync.hideForPrivacy()
            await widgetCanvas.hideForPrivacy()
        } else {
            await widgetSync.clearForPrivacy()
            await widgetCanvas.clearForPrivacy()
        }
        await partnerAvatar?.clear()
        await dailyAnswerMediaCache?.clearAll()
        await memoryMediaCache?.clearAll()
        await profilePhotoCache?.clearAll()
    }

    private func purgeContentCaches(scope: LocalPrivacyPurgeScope) async {
        dailyChallengeSnapshotCache.clearAll()
        await threadChatCache.clearAll()
        await gamesCache.clearAll()
        await storyChainCache.clearAll()
        await mindMeldCache.clearAll()
        await PiccanteCache.shared.clearAll()
        await consensioCache.clearAll()
        await guessMySpotCache.clearAll()
        // These are owned unsent photos and drafts, not a shared-media cache.
        // A temporary access hide must allow the same send to resume later.
        if scope != .relationshipAccessHidden { guessMySpotPhotos.clearAll() }
        await heartsCache.clearAll()
        await coupleDatesCache.clearAll()
        await visitsCache.clearAll()
        await favoritesCache.clearAll()
        await storiesCache.clearAll()
        await mailCache.clearAll()
        await reactionsCache.clearAll()
        await topicsCache.clearAll()
        await exquisiteCorpseCache.clearAll()
        await boardGamesCache.clearAll()
        lookBackCache.clearAll()
        BoardMarkRenderer.removeAll()
        MemoryImageDecoding.removeAll()
        gameDrawingStore.purge(for: scope)
    }

    func removePrivateFiles() async throws {
        // Earlier builds sent backend calls and media downloads through URLSession.shared,
        // which kept the responses here on disk.
        URLCache.shared.removeAllCachedResponses()
        var urls = [DailyAnswerMediaImageService.defaultDirectoryURL(), MemoryMediaImageService.defaultDirectoryURL()]
        if let containerURL = PaeoniaAppGroup.containerURL {
            urls.append(containerURL.appendingPathComponent(PaeoniaAppGroup.communicationPartnerAvatarPath))
        }
        var failure: (any Error)?
        do {
            try await profilePhotoDiskCache.removeAllProfilePhotoData()
        } catch {
            failure = error
        }
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
    }

    nonisolated static func removeTemporaryVoiceFiles(in temporaryDirectory: URL) {
        let prefixes = ["daily-voice-", "daily-voice-play-"]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls where prefixes.contains(where: url.lastPathComponent.hasPrefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
