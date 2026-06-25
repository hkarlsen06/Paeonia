import Foundation

nonisolated struct SupabaseUserEntitlement: Codable, Equatable, Sendable {
    let userID: UUID
    let isEntitled: Bool
    let source: String?
    let status: String?
    let productID: UUID?
    let currentPeriodEnd: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case isEntitled = "is_entitled"
        case source
        case status
        case productID = "product_id"
        case currentPeriodEnd = "current_period_end"
        case updatedAt = "updated_at"
    }
}

nonisolated struct SupabaseCoupleEntitlement: Codable, Equatable, Sendable {
    let coupleID: UUID
    let isEntitled: Bool
    let coveringUserID: UUID?
    let source: String?
    let status: String?
    let productID: UUID?
    let currentPeriodEnd: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case isEntitled = "is_entitled"
        case coveringUserID = "covering_user_id"
        case source
        case status
        case productID = "product_id"
        case currentPeriodEnd = "current_period_end"
        case updatedAt = "updated_at"
    }
}

nonisolated struct SupabaseRelationshipState: Codable, Equatable, Sendable {
    let coupleID: UUID
    let pairID: UUID
    let relationshipStatus: SupabaseRelationshipStatus
    let memberStatus: SupabaseRelationshipMemberStatus
    let partnerUserID: UUID?
    let partnerDisplayName: String?
    let partnerProfilePhotoAssetID: UUID?
    let startedOn: String?
    let endedAt: Date?
    let deleteAfter: Date?
    let endedNoticeSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case pairID = "pair_id"
        case relationshipStatus = "relationship_status"
        case memberStatus = "member_status"
        case partnerUserID = "partner_user_id"
        case partnerDisplayName = "partner_display_name"
        case partnerProfilePhotoAssetID = "partner_profile_photo_asset_id"
        case startedOn = "started_on"
        case endedAt = "ended_at"
        case deleteAfter = "delete_after"
        case endedNoticeSeenAt = "ended_notice_seen_at"
    }

    var isActiveRelationship: Bool {
        relationshipStatus == .active && memberStatus == .active
    }

    var needsEndedNotice: Bool {
        relationshipStatus == .ended && memberStatus == .endedNoticePending
    }
}

nonisolated struct SupabaseRelationshipSyncEvent: Codable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let coupleID: UUID
    let initiatedByUserID: UUID?
    let eventKind: String
    let reason: String?
    let occurredAt: Date
    let relationshipStatus: String
    let memberStatus: String
    let endedAt: Date?
    let deleteAfter: Date?
    let localPurgeScope: [String: String]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case coupleID = "couple_id"
        case initiatedByUserID = "initiated_by_user_id"
        case eventKind = "event_kind"
        case reason
        case occurredAt = "occurred_at"
        case relationshipStatus = "relationship_status"
        case memberStatus = "member_status"
        case endedAt = "ended_at"
        case deleteAfter = "delete_after"
        case localPurgeScope = "local_purge_scope"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated enum SupabaseRelationshipStatus: Codable, Equatable, Sendable {
    case active
    case ended
    case deleted
    case unknown(String)

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(rawValue: String) {
        switch rawValue {
        case "active":
            self = .active
        case "ended":
            self = .ended
        case "deleted":
            self = .deleted
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .active:
            "active"
        case .ended:
            "ended"
        case .deleted:
            "deleted"
        case let .unknown(rawValue):
            rawValue
        }
    }
}

nonisolated enum SupabaseRelationshipMemberStatus: Codable, Equatable, Sendable {
    case active
    case left
    case endedNoticePending
    case endedNoticeSeen
    case unknown(String)

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(rawValue: String) {
        switch rawValue {
        case "active":
            self = .active
        case "left":
            self = .left
        case "ended_notice_pending":
            self = .endedNoticePending
        case "ended_notice_seen":
            self = .endedNoticeSeen
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .active:
            "active"
        case .left:
            "left"
        case .endedNoticePending:
            "ended_notice_pending"
        case .endedNoticeSeen:
            "ended_notice_seen"
        case let .unknown(rawValue):
            rawValue
        }
    }
}
