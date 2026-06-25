import Foundation
import SwiftData

@Model
final class LocalAccessSyncSnapshot {
    @Attribute(.unique) var ownerUserID: UUID
    var userEntitlementData: Data?
    var coupleEntitlementData: Data?
    var relationshipStateData: Data?
    var refreshedAt: Date

    init(
        ownerUserID: UUID,
        userEntitlementData: Data? = nil,
        coupleEntitlementData: Data? = nil,
        relationshipStateData: Data? = nil,
        refreshedAt: Date = Date()
    ) {
        self.ownerUserID = ownerUserID
        self.userEntitlementData = userEntitlementData
        self.coupleEntitlementData = coupleEntitlementData
        self.relationshipStateData = relationshipStateData
        self.refreshedAt = refreshedAt
    }
}
