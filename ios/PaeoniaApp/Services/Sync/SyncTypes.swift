import Foundation

nonisolated protocol PaeoniaSyncing: Actor {
    func configure(session: SyncSession?)
    func start()
    func requestSync(reason: SyncRequestReason)
    func runOnce(reason: SyncRequestReason) async -> SyncRunResult
    func stop()
    func resetForUserChange() async
    func purgeRelationshipAccess(ownerUserID: UUID, permanently: Bool) async
}

nonisolated protocol SyncStream: Sendable {
    var streamKey: SyncStreamKey { get }

    func scope(for session: SyncSession) -> SyncStreamScope?
    func pull(context: SyncContext) async throws -> SyncCursor?
    func push(context: SyncContext) async throws
}

nonisolated struct SyncSession: Equatable, Sendable {
    let userID: UUID
    let activeCoupleID: UUID?
    /// Current relationship identity used only to reject stale cross-couple
    /// privacy events. Unlike `activeCoupleID`, this remains populated while a
    /// relationship is paywalled or showing its ended notice.
    let relationshipCoupleID: UUID?

    init(
        userID: UUID,
        activeCoupleID: UUID? = nil,
        relationshipCoupleID: UUID? = nil
    ) {
        self.userID = userID
        self.activeCoupleID = activeCoupleID
        self.relationshipCoupleID = relationshipCoupleID ?? activeCoupleID
    }

    init?(authSession: AuthSession, activeCoupleID: UUID? = nil) {
        guard let userID = UUID(uuidString: authSession.id) else {
            return nil
        }

        self.init(
            userID: userID,
            activeCoupleID: activeCoupleID,
            relationshipCoupleID: activeCoupleID
        )
    }
}

nonisolated struct SyncContext: Sendable {
    let session: SyncSession
    let reason: SyncRequestReason
    let startedAt: Date
    let streamCursor: SyncCursor
    let stateStore: any SyncStatePersisting
    let pendingOperationStore: any PendingSyncOperationPersisting

    init(
        session: SyncSession,
        reason: SyncRequestReason,
        startedAt: Date = Date(),
        streamCursor: SyncCursor = SyncCursor(),
        stateStore: any SyncStatePersisting,
        pendingOperationStore: any PendingSyncOperationPersisting
    ) {
        self.session = session
        self.reason = reason
        self.startedAt = startedAt
        self.streamCursor = streamCursor
        self.stateStore = stateStore
        self.pendingOperationStore = pendingOperationStore
    }
}

nonisolated enum SyncScopeKind: String, Codable, CaseIterable, Sendable {
    case user
    case couple
    case thread
    case widgetCanvas = "widget_canvas"
}

nonisolated enum SyncStreamKey: String, Codable, CaseIterable, Sendable {
    case profile
    case relationship
    case relationshipEvents = "relationship_events"
    case entitlement
    case pendingOperations = "pending_operations"
    case settings
    case notifications
    case devices
    case media
    case daily
    case memories
    case threads
    case widget
    case location
    case reports
    case privacy
}

nonisolated enum SyncRecordStatus: String, Codable, CaseIterable, Sendable {
    case clean
    case dirty
    case pendingDelete = "pending_delete"
    case conflict
}

nonisolated enum SyncPendingOperationKind: String, Codable, CaseIterable, Sendable {
    case createPairingInvite = "create_pairing_invite"
    case acceptPairingInvite = "accept_pairing_invite"
    case setRelationshipStartedOn = "set_relationship_started_on"
    case leaveRelationship = "leave_relationship"
    case submitLeaveAndReport = "submit_leave_and_report"
    case createPendingMediaUpload = "create_pending_media_upload"
    case startDailyChallenge = "start_daily_challenge"
    case submitDailyAnswer = "submit_daily_answer"
    case shuffleDailyQuestion = "shuffle_daily_question"
    case createDailyQuestionThreadWithMessage = "create_daily_question_thread_with_message"
    case createMemoryThreadWithMessage = "create_memory_thread_with_message"
    case sendThreadMessage = "send_thread_message"
    case createMemory = "create_memory"
    case updateMemory = "update_memory"
    case hideMemory = "hide_memory"
    case upsertMemoryNote = "upsert_memory_note"
    case attachMemoryMedia = "attach_memory_media"
    case removeMemoryMedia = "remove_memory_media"
    case finalizeMediaUpload = "finalize_media_upload"
    case submitWidgetDrawingRevision = "submit_widget_drawing_revision"
    case updateLatestPartnerLocation = "update_latest_partner_location"
    case updateLocationSharingPreference = "update_location_sharing_preference"
    case submitContentReport = "submit_content_report"
}

nonisolated enum SyncPendingOperationStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case sending
    case retrying
    case failedRetryable = "failed_retryable"
    case failedTerminal = "failed_terminal"
    case succeeded
}

nonisolated struct SyncRecordMetadata: Codable, Equatable, Sendable {
    var serverUpdatedAt: Date?
    var serverRevision: Int?
    var serverDeletedAt: Date?
    var syncStatus: SyncRecordStatus
    var dirtyFields: Set<String>
    var lastSyncedSnapshot: Data?
    var localUpdatedAt: Date
    var conflictServerSnapshot: Data?

    init(
        serverUpdatedAt: Date? = nil,
        serverRevision: Int? = nil,
        serverDeletedAt: Date? = nil,
        syncStatus: SyncRecordStatus = .clean,
        dirtyFields: Set<String> = [],
        lastSyncedSnapshot: Data? = nil,
        localUpdatedAt: Date = Date(),
        conflictServerSnapshot: Data? = nil
    ) {
        self.serverUpdatedAt = serverUpdatedAt
        self.serverRevision = serverRevision
        self.serverDeletedAt = serverDeletedAt
        self.syncStatus = syncStatus
        self.dirtyFields = dirtyFields
        self.lastSyncedSnapshot = lastSyncedSnapshot
        self.localUpdatedAt = localUpdatedAt
        self.conflictServerSnapshot = conflictServerSnapshot
    }
}

nonisolated struct SyncCursor: Codable, Equatable, Sendable {
    var updatedAt: Date?
    var tieID: UUID?

    init(updatedAt: Date? = nil, tieID: UUID? = nil) {
        self.updatedAt = updatedAt
        self.tieID = tieID
    }
}

nonisolated enum SyncRequestReason: String, Codable, CaseIterable, Sendable {
    case startup
    case foreground
    case localChange = "local_change"
    case manualRefresh = "manual_refresh"
    case remoteNotification = "remote_notification"
}

nonisolated enum SyncRunStatus: Equatable, Sendable {
    case succeeded
    case failed
    case coalesced
    case skippedNoSession
    case skippedInterval
    case cancelled
    case timedOut
}

nonisolated struct SyncRunResult: Equatable, Sendable {
    let status: SyncRunStatus
    let attemptedStreamCount: Int
    let completedStreamCount: Int
    let failedStreamKey: SyncStreamKey?
    let errorDescription: String?

    static func coalesced() -> SyncRunResult {
        SyncRunResult(
            status: .coalesced,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    static func skippedNoSession() -> SyncRunResult {
        SyncRunResult(
            status: .skippedNoSession,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    static func skippedInterval() -> SyncRunResult {
        SyncRunResult(
            status: .skippedInterval,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    static func timedOut() -> SyncRunResult {
        SyncRunResult(
            status: .timedOut,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: "Sync timed out"
        )
    }
}
