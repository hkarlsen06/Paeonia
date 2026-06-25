import Foundation
import SwiftData

@Model
final class LocalRelationshipSyncEvent {
    @Attribute(.unique) var id: UUID
    var ownerUserID: UUID
    var coupleID: UUID
    var initiatedByUserID: UUID?
    var eventKind: String
    var reason: String?
    var occurredAt: Date
    var relationshipStatus: String
    var memberStatus: String
    var endedAt: Date?
    var deleteAfter: Date?
    var localPurgeScopeData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(event: SupabaseRelationshipSyncEvent, localPurgeScopeData: Data?) {
        self.id = event.id
        self.ownerUserID = event.userID
        self.coupleID = event.coupleID
        self.initiatedByUserID = event.initiatedByUserID
        self.eventKind = event.eventKind
        self.reason = event.reason
        self.occurredAt = event.occurredAt
        self.relationshipStatus = event.relationshipStatus
        self.memberStatus = event.memberStatus
        self.endedAt = event.endedAt
        self.deleteAfter = event.deleteAfter
        self.localPurgeScopeData = localPurgeScopeData
        self.createdAt = event.createdAt
        self.updatedAt = event.updatedAt
    }

    func update(from event: SupabaseRelationshipSyncEvent, localPurgeScopeData: Data?) {
        ownerUserID = event.userID
        coupleID = event.coupleID
        initiatedByUserID = event.initiatedByUserID
        eventKind = event.eventKind
        reason = event.reason
        occurredAt = event.occurredAt
        relationshipStatus = event.relationshipStatus
        memberStatus = event.memberStatus
        endedAt = event.endedAt
        deleteAfter = event.deleteAfter
        self.localPurgeScopeData = localPurgeScopeData
        createdAt = event.createdAt
        updatedAt = event.updatedAt
    }
}
