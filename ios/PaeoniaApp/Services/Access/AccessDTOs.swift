import Foundation

nonisolated struct RemoteAccessSnapshot: Codable, Equatable, Sendable {
    let userEntitlement: RemoteUserEntitlement?
    let coupleEntitlement: RemoteCoupleEntitlement?
    let relationshipState: RemoteRelationshipState?
    /// A banned account gets `.banned` and nothing else.
    var accountStatus: RemoteAccountStatus = .active

    enum CodingKeys: String, CodingKey {
        case userEntitlement = "user_entitlement"
        case coupleEntitlement = "couple_entitlement"
        case relationshipState = "relationship_state"
        case accountStatus = "account_status"
    }

    var isBanned: Bool {
        accountStatus == .banned
    }
}

nonisolated enum RemoteAccountStatus: String, Codable, Equatable, Sendable {
    case active
    case banned
}

nonisolated struct RemoteUserEntitlement: Codable, Equatable, Sendable {
    let userID: UUID
    let isEntitled: Bool
    let source: String?
    let status: String?
    let productID: UUID?
    /// "monthly" or "yearly" for an App Store subscription. Nil for other access.
    let billingPeriod: String?
    let currentPeriodEnd: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case isEntitled = "is_entitled"
        case source
        case status
        case productID = "product_id"
        case billingPeriod = "billing_period"
        case currentPeriodEnd = "current_period_end"
        case updatedAt = "updated_at"
    }
}

nonisolated struct RemoteCoupleEntitlement: Codable, Equatable, Sendable {
    let coupleID: UUID
    let isEntitled: Bool
    let coveringUserID: UUID?
    let source: String?
    let status: String?
    let productID: UUID?
    /// "monthly" or "yearly" for an App Store subscription. Nil for other access.
    let billingPeriod: String?
    let currentPeriodEnd: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case isEntitled = "is_entitled"
        case coveringUserID = "covering_user_id"
        case source
        case status
        case productID = "product_id"
        case billingPeriod = "billing_period"
        case currentPeriodEnd = "current_period_end"
        case updatedAt = "updated_at"
    }
}

nonisolated struct RemoteRelationshipState: Codable, Equatable, Sendable {
    let coupleID: UUID
    let pairID: UUID
    let relationshipStatus: RemoteRelationshipStatus
    let memberStatus: RemoteRelationshipMemberStatus
    /// This person joined with the partner's invite code.
    let acceptedInvite: Bool
    let partnerUserID: UUID?
    /// The partner's own name. Read the name to show through `partnerName`, which applies this
    /// person's nickname for the partner.
    let partnerAccountName: String?
    /// What this person calls their partner. The server sends it only to them.
    var partnerNickname: String?
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
        case acceptedInvite = "accepted_invite"
        case partnerUserID = "partner_user_id"
        case partnerAccountName = "partner_account_name"
        case partnerNickname = "partner_nickname"
        case partnerProfilePhotoAssetID = "partner_profile_photo_asset_id"
        case startedOn = "started_on"
        case endedAt = "ended_at"
        case deleteAfter = "delete_after"
        case endedNoticeSeenAt = "ended_notice_seen_at"
    }

    /// What this person calls their partner. The one way to get a partner's name for display.
    var partnerName: PartnerName {
        PartnerName(accountName: partnerAccountName, nickname: partnerNickname)
    }

    var isActiveRelationship: Bool {
        relationshipStatus == .active && memberStatus == .active
    }

    var needsEndedNotice: Bool {
        relationshipStatus == .ended && memberStatus == .endedNoticePending
    }

    func replacingStartedOn(_ startedOn: String?) -> Self {
        Self(
            coupleID: coupleID,
            pairID: pairID,
            relationshipStatus: relationshipStatus,
            memberStatus: memberStatus,
            acceptedInvite: acceptedInvite,
            partnerUserID: partnerUserID,
            partnerAccountName: partnerAccountName,
            partnerNickname: partnerNickname,
            partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
            startedOn: startedOn,
            endedAt: endedAt,
            deleteAfter: deleteAfter,
            endedNoticeSeenAt: endedNoticeSeenAt
        )
    }
}

nonisolated struct RemoteRelationshipSyncEvent: Codable, Equatable, Sendable {
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

nonisolated enum RemoteRelationshipStatus: Codable, Equatable, Sendable {
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

nonisolated enum RemoteRelationshipMemberStatus: Codable, Equatable, Sendable {
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
