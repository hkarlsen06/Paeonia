import Foundation

/// The admin backend functions (`backend/convex/admin.ts`). The server checks admin
/// access on every call except `loadIsAdmin`, which only decides whether the app
/// shows the Admin row.
nonisolated protocol AdminGateway: Sendable {
    func loadIsAdmin() async throws -> Bool
    /// Up to 50 users. A nil or empty `query` lists the newest users, and a full
    /// user ID finds that user. `bannedOnly` lists banned users and ignores `query`.
    func searchUsers(query: String?, bannedOnly: Bool) async throws -> [AdminUserSummary]
    /// Nil when the user does not exist.
    func loadUser(id: UUID) async throws -> AdminUserDetail?
    func banUser(id: UUID, reason: String) async throws
    func unbanUser(id: UUID) async throws
    /// Newest first, up to 100. Pass a user to see only the actions about them.
    func loadAuditLog(targetUserID: UUID?) async throws -> [AdminAuditEntry]
}

nonisolated struct LiveAdminGateway: AdminGateway {
    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    func loadIsAdmin() async throws -> Bool {
        let status: AdminStatus = try await client.query("admin:get_admin_status")
        return status.isAdmin
    }

    func searchUsers(query: String?, bannedOnly: Bool) async throws -> [AdminUserSummary] {
        try await client.query(
            "admin:search_users",
            args: SearchUsersRequest(query: query, bannedOnly: bannedOnly)
        )
    }

    func loadUser(id: UUID) async throws -> AdminUserDetail? {
        try await client.query("admin:get_user", args: UserRequest(userID: id))
    }

    func banUser(id: UUID, reason: String) async throws {
        try await client.mutation("admin:ban_user", args: BanUserRequest(userID: id, reason: reason))
    }

    func unbanUser(id: UUID) async throws {
        try await client.mutation("admin:unban_user", args: UserRequest(userID: id))
    }

    func loadAuditLog(targetUserID: UUID?) async throws -> [AdminAuditEntry] {
        try await client.query(
            "admin:get_audit_log",
            args: AuditLogRequest(targetUserID: targetUserID)
        )
    }
}

nonisolated enum AdminGatewayFactory {
    static func makeDefault() -> (any AdminGateway)? {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return nil
        }
        return LiveAdminGateway(client: client)
    }
}

// MARK: - Request bodies

nonisolated private struct SearchUsersRequest: Encodable {
    let query: String?
    let bannedOnly: Bool

    enum CodingKeys: String, CodingKey {
        case query = "p_query"
        case bannedOnly = "p_banned_only"
    }
}

nonisolated private struct UserRequest: Encodable {
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "p_user_id"
    }
}

nonisolated private struct BanUserRequest: Encodable {
    let userID: UUID
    let reason: String

    enum CodingKeys: String, CodingKey {
        case userID = "p_user_id"
        case reason = "p_reason"
    }
}

nonisolated private struct AuditLogRequest: Encodable {
    let targetUserID: UUID?

    enum CodingKeys: String, CodingKey {
        case targetUserID = "p_target_user_id"
    }
}
