import Foundation

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
