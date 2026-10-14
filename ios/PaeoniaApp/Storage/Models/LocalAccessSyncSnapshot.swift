import Foundation
import SwiftData

@Model
final class LocalAccessSyncSnapshot {
    @Attribute(.unique) var ownerUserID: UUID
    var userEntitlementData: Data?
    var coupleEntitlementData: Data?
    var relationshipStateData: Data?
    var isBanned: Bool = false
    var refreshedAt: Date

    init(
        ownerUserID: UUID,
        userEntitlementData: Data? = nil,
        coupleEntitlementData: Data? = nil,
        relationshipStateData: Data? = nil,
        isBanned: Bool = false,
        refreshedAt: Date = Date()
    ) {
        self.ownerUserID = ownerUserID
        self.userEntitlementData = userEntitlementData
        self.coupleEntitlementData = coupleEntitlementData
        self.relationshipStateData = relationshipStateData
        self.isBanned = isBanned
        self.refreshedAt = refreshedAt
    }
}
