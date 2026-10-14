import Foundation

/// One row of the admin user list (`admin:search_users`).
nonisolated struct AdminUserSummary: Decodable, Equatable, Identifiable, Sendable {
    let userID: UUID
    let displayName: String?
    let authProvider: AuthProvider
    let createdAt: Date
    let isAdmin: Bool
    let bannedAt: Date?

    var id: UUID { userID }
    var isBanned: Bool { bannedAt != nil }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case authProvider = "auth_provider"
        case createdAt = "created_at"
        case isAdmin = "is_admin"
        case bannedAt = "banned_at"
    }
}

/// One user for the admin detail screen (`admin:get_user`). Account facts only.
nonisolated struct AdminUserDetail: Decodable, Equatable, Identifiable, Sendable {
    let userID: UUID
    let displayName: String?
    let authProvider: AuthProvider
    let createdAt: Date
    let isAdmin: Bool
    let bannedAt: Date?
    let isSelf: Bool
    let banReason: String?
    let bannedByDisplayName: String?
    let onboardingCompletedAt: Date?
    let timeZoneID: String?
    let isEntitled: Bool
    let coupleID: UUID?
    /// A date (`yyyy-MM-dd`) or an ISO timestamp, depending on how the couple started.
    let pairedSince: String?
    let partnerUserID: UUID?
    let partnerDisplayName: String?
    let reportsAgainstCount: Int
    let reportsByCount: Int

    var id: UUID { userID }
    var isBanned: Bool { bannedAt != nil }

    /// The server refuses to ban yourself or an admin, so the screen offers no ban
    /// for them. Someone who is already banned is not banned again.
    var canBan: Bool { !isSelf && !isAdmin && !isBanned }
    /// A banned person can always be unbanned.
    var canUnban: Bool { isBanned }

    var pairedSinceDate: Date? {
        guard let pairedSince else {
            return nil
        }
        if let day = try? PairingStartDate(rawValue: pairedSince) {
            return day.date()
        }
        return try? Date(pairedSince, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case authProvider = "auth_provider"
        case createdAt = "created_at"
        case isAdmin = "is_admin"
        case bannedAt = "banned_at"
        case isSelf = "is_self"
        case banReason = "ban_reason"
        case bannedByDisplayName = "banned_by_display_name"
        case onboardingCompletedAt = "onboarding_completed_at"
        case timeZoneID = "time_zone_id"
        case isEntitled = "is_entitled"
        case coupleID = "couple_id"
        case pairedSince = "paired_since"
        case partnerUserID = "partner_user_id"
        case partnerDisplayName = "partner_display_name"
        case reportsAgainstCount = "reports_against_count"
        case reportsByCount = "reports_by_count"
    }
}

/// One admin action (`admin:get_audit_log`). Either an admin or a command-line
/// operator did it.
nonisolated struct AdminAuditEntry: Decodable, Equatable, Identifiable, Sendable {
    enum Action: String, Decodable, Equatable, Sendable {
        case userBanned = "user_banned"
        case userUnbanned = "user_unbanned"
        /// An action this app version does not know.
        case other

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: raw) ?? .other
        }
    }

    let id: UUID
    let action: Action
    let adminUserID: UUID?
    let adminDisplayName: String?
    let operatorIdentifier: String?
    let targetUserID: UUID
    let targetDisplayName: String?
    let reason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case action
        case adminUserID = "admin_user_id"
        case adminDisplayName = "admin_display_name"
        case operatorIdentifier = "operator_identifier"
        case targetUserID = "target_user_id"
        case targetDisplayName = "target_display_name"
        case reason
        case createdAt = "created_at"
    }
}

nonisolated struct AdminStatus: Decodable, Equatable, Sendable {
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case isAdmin = "is_admin"
    }
}
