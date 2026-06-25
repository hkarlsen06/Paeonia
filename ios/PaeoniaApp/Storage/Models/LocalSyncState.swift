import Foundation
import SwiftData

@Model
final class LocalSyncState {
    @Attribute(.unique) var key: String
    private(set) var ownerUserID: UUID
    private(set) var scopeKindRawValue: String
    private(set) var scopeID: UUID?
    private(set) var streamKeyRawValue: String
    var lastUpdatedAt: Date?
    var lastTieID: UUID?
    var lastSuccessfulSyncAt: Date?
    var lastSyncAttemptAt: Date?
    var lastSyncError: String?

    init(
        ownerUserID: UUID,
        scopeKind: SyncScopeKind,
        scopeID: UUID? = nil,
        streamKey: SyncStreamKey,
        cursor: SyncCursor = SyncCursor(),
        lastSuccessfulSyncAt: Date? = nil,
        lastSyncAttemptAt: Date? = nil,
        lastSyncError: String? = nil
    ) {
        self.key = Self.makeKey(
            ownerUserID: ownerUserID,
            scopeKind: scopeKind,
            scopeID: scopeID,
            streamKey: streamKey
        )
        self.ownerUserID = ownerUserID
        self.scopeKindRawValue = scopeKind.rawValue
        self.scopeID = scopeID
        self.streamKeyRawValue = streamKey.rawValue
        self.lastUpdatedAt = cursor.updatedAt
        self.lastTieID = cursor.tieID
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastSyncAttemptAt = lastSyncAttemptAt
        self.lastSyncError = lastSyncError
    }

    var scopeKind: SyncScopeKind {
        SyncScopeKind(rawValue: scopeKindRawValue) ?? .user
    }

    var streamKey: SyncStreamKey {
        SyncStreamKey(rawValue: streamKeyRawValue) ?? .relationship
    }

    var cursor: SyncCursor {
        SyncCursor(updatedAt: lastUpdatedAt, tieID: lastTieID)
    }

    func markAttempted(at date: Date = Date()) {
        lastSyncAttemptAt = date
    }

    func markSucceeded(cursor: SyncCursor? = nil, at date: Date = Date()) {
        if let cursor {
            lastUpdatedAt = cursor.updatedAt
            lastTieID = cursor.tieID
        }

        lastSuccessfulSyncAt = date
        lastSyncAttemptAt = date
        lastSyncError = nil
    }

    func markFailed(_ errorDescription: String, at date: Date = Date()) {
        lastSyncAttemptAt = date
        lastSyncError = errorDescription
    }

    static func makeKey(
        ownerUserID: UUID,
        scopeKind: SyncScopeKind,
        scopeID: UUID?,
        streamKey: SyncStreamKey
    ) -> String {
        [
            ownerUserID.uuidString.lowercased(),
            scopeKind.rawValue,
            scopeID?.uuidString.lowercased() ?? "none",
            streamKey.rawValue
        ].joined(separator: "|")
    }
}
