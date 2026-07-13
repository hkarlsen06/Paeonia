import Foundation

nonisolated enum LocalPrivacyPurgeScope: Equatable, Sendable {
    case departingUser
    case relationshipAccessHidden
    case relationshipContentPurged(clearAccessSnapshot: Bool)
}

nonisolated protocol LocalPrivacyPurging: Sendable {
    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) async
}

nonisolated protocol LocalPrivateContentPurging: Sendable {
    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) async
}

actor LocalPrivacyPurgeService: LocalPrivacyPurging {
    private let recordStore: any LocalPrivacyRecordPurging
    private let privateContentPurger: any LocalPrivateContentPurging

    init(
        recordStore: any LocalPrivacyRecordPurging,
        privateContentPurger: any LocalPrivateContentPurging = LiveLocalPrivateContentPurger()
    ) {
        self.recordStore = recordStore
        self.privateContentPurger = privateContentPurger
    }

    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) async {
        do {
            switch scope {
            case .departingUser:
                try await recordStore.purgeDepartingUser(ownerUserID: ownerUserID)
            case .relationshipAccessHidden:
                try await recordStore.hideRelationshipAccess(ownerUserID: ownerUserID)
            case let .relationshipContentPurged(clearAccessSnapshot):
                try await recordStore.purgeRelationshipContent(
                    ownerUserID: ownerUserID,
                    clearAccessSnapshot: clearAccessSnapshot
                )
            }
        } catch {
            // File/App Group cleanup still has to run when one SwiftData store
            // operation fails. The API is idempotent, so the coordinator can
            // safely invoke it again on a later privacy transition.
        }

        await privateContentPurger.purge(ownerUserID: ownerUserID, scope: scope)
    }
}

actor NoOpLocalPrivacyPurger: LocalPrivacyPurging {
    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) {}
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
