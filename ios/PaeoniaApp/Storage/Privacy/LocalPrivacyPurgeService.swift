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
}

actor LocalPrivacyPurgeService: LocalPrivacyPurging {
    private let recordStore: any LocalPrivacyRecordPurging
    private let privateContentPurger: any LocalPrivateContentPurging
    private let retryStore: any LocalPrivacyPurgeRetryStoring
    private let retryDelay: Duration
    private let automaticallyRetry: Bool
    private var scheduledRetry: Task<Void, Never>?
    private var volatileRetryRequests: [UUID: LocalPrivacyPurgeRequest] = [:]

    init(
        recordStore: any LocalPrivacyRecordPurging,
        privateContentPurger: any LocalPrivateContentPurging = LiveLocalPrivateContentPurger(),
        retryStore: any LocalPrivacyPurgeRetryStoring = UserDefaultsLocalPrivacyPurgeRetryStore(),
        retryDelay: Duration = .seconds(30),
        automaticallyRetry: Bool = true
    ) {
        self.recordStore = recordStore
        self.privateContentPurger = privateContentPurger
        self.retryStore = retryStore
        self.retryDelay = retryDelay
        self.automaticallyRetry = automaticallyRetry
    }

    @discardableResult
    func purge(
        ownerUserID: UUID,
        scope: LocalPrivacyPurgeScope
    ) async -> LocalPrivacyPurgeResult {
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
                try await purgeRecords(for: request)
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
                try await purgeRecords(for: request)
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
                try await purgeRecords(for: request)
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

    private func purgeRecords(for request: LocalPrivacyPurgeRequest) async throws {
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
        self.profilePhotoDiskCache = profilePhotoDiskCache
        self.temporaryDirectory = temporaryDirectory
    }

    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) async {
        if scope == .relationshipAccessHidden {
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

        dailyChallengeSnapshotCache.clearAll()
        try? await profilePhotoDiskCache.removeAllProfilePhotoData()
        removeDirectoryIfPresent(DailyAnswerMediaImageService.defaultDirectoryURL())
        removeDirectoryIfPresent(MemoryMediaImageService.defaultDirectoryURL())
        removePartnerAvatarIfPresent()

        WidgetSyncIdentityStore.shared.clear()
        WidgetCanvasSyncService.clearPersistedState()

        let shouldPurgeOwnedContent = scope != .relationshipAccessHidden
        if shouldPurgeOwnedContent {
            dailyAnswerMediaDraftStore.clearAll()
            removeTemporaryVoiceFiles()
            WidgetPendingUploadStore.shared.clearAll()
        }

        await MainActor.run {
            if shouldPurgeOwnedContent {
                UserDefaultsDailyChallengeDraftStore.shared.clearDrafts(for: ownerUserID)
                FileWidgetDrawingDraftStore.shared.clearDraft(for: ownerUserID)
                UserDefaultsPairingCelebrationStore.shared.clearAll()
            }
            if scope == .departingUser {
                UserDefaultsPairingInviteStore.shared.clearInvite(
                    for: ownerUserID.uuidString
                )
                UserDefaultsPairingJoinInviteStore.shared.clearInviteCode()
                PushRegistrationFingerprintStore.resetAll()
            }
        }
    }

    private func removeDirectoryIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func removePartnerAvatarIfPresent() {
        guard let containerURL = PaeoniaAppGroup.containerURL else {
            return
        }
        let avatarURL = containerURL.appendingPathComponent(
            PaeoniaAppGroup.communicationPartnerAvatarPath
        )
        guard FileManager.default.fileExists(atPath: avatarURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: avatarURL)
    }

    private func removeTemporaryVoiceFiles() {
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
