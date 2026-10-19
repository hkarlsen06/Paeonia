import Foundation
@testable import PaeoniaApp

// Test doubles for the admin tests.

nonisolated enum AdminFakeError: Error {
    case failed
}

nonisolated struct AdminSearchCall: Equatable, Sendable {
    let query: String?
    let bannedOnly: Bool
}

nonisolated struct AdminBanCall: Equatable, Sendable {
    let userID: UUID
    let reason: String
}

/// Holds a gateway call until the test lets it go, so a test can cancel the task
/// that made the call while it waits.
actor AdminGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

// The gateway protocol is async, and these answer at once.
// swiftlint:disable async_without_await

/// Records every admin call. A class with a lock, like the other scripted
/// gateways, so tests read its record without `await`.
final class AdminFakeGateway: AdminGateway, @unchecked Sendable {
    private struct State {
        var isAdmin: Bool
        var users: [AdminUserSummary]
        var detail: AdminUserDetail?
        /// What `loadUser` returns after a ban or unban went through.
        var detailAfterChange: AdminUserDetail?
        var auditEntries: [AdminAuditEntry]
        var auditEntriesAfterChange: [AdminAuditEntry]
        var error: (any Error)?
        var changeError: (any Error)?
        var searchGate: AdminGate?
        var searches = [AdminSearchCall]()
        var bans = [AdminBanCall]()
    }

    private let lock = NSLock()
    private var state: State

    init(
        isAdmin: Bool = true,
        users: [AdminUserSummary] = [],
        detail: AdminUserDetail? = nil,
        detailAfterChange: AdminUserDetail? = nil,
        auditEntries: [AdminAuditEntry] = [],
        auditEntriesAfterChange: [AdminAuditEntry] = [],
        error: (any Error)? = nil,
        changeError: (any Error)? = nil
    ) {
        state = State(
            isAdmin: isAdmin,
            users: users,
            detail: detail,
            detailAfterChange: detailAfterChange,
            auditEntries: auditEntries,
            auditEntriesAfterChange: auditEntriesAfterChange,
            error: error,
            changeError: changeError
        )
    }

    var searches: [AdminSearchCall] { locked { $0.searches } }
    var bans: [AdminBanCall] { locked { $0.bans } }

    func holdSearches(with gate: AdminGate) {
        locked { $0.searchGate = gate }
    }

    func loadIsAdmin() async throws -> Bool {
        try locked { state in
            if let error = state.error {
                throw error
            }
            return state.isAdmin
        }
    }

    func searchUsers(query: String?, bannedOnly: Bool) async throws -> [AdminUserSummary] {
        let gate = locked { state in
            state.searches.append(AdminSearchCall(query: query, bannedOnly: bannedOnly))
            return state.searchGate
        }
        if let gate {
            await gate.wait()
        }
        return try locked { state in
            if let error = state.error {
                throw error
            }
            return state.users
        }
    }

    func loadUser(id: UUID) async throws -> AdminUserDetail? {
        try locked { state in
            if let error = state.error {
                throw error
            }
            return state.detail
        }
    }

    func banUser(id: UUID, reason: String) async throws {
        try locked { state in
            state.bans.append(AdminBanCall(userID: id, reason: reason))
            try Self.applyChange(&state)
        }
    }

    func unbanUser(id: UUID) async throws {
        try locked { state in
            try Self.applyChange(&state)
        }
    }

    func loadAuditLog(targetUserID: UUID?) async throws -> [AdminAuditEntry] {
        try locked { state in
            if let error = state.error {
                throw error
            }
            return state.auditEntries
        }
    }

    private static func applyChange(_ state: inout State) throws {
        if let changeError = state.changeError {
            throw changeError
        }
        state.detail = state.detailAfterChange
        state.auditEntries = state.auditEntriesAfterChange
    }

    private func locked<T>(_ body: (inout State) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
// swiftlint:enable async_without_await

/// A counter the detail view model's `onChanged` callback bumps.
@MainActor
final class AdminChangeCounter {
    private(set) var calls = 0

    func bump() {
        calls += 1
    }
}

nonisolated enum AdminFixtures {
    static let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    static let adminID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
    static let bannedAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func summary(
        id: UUID = UUID(),
        name: String? = "Maja",
        isAdmin: Bool = false,
        bannedAt: Date? = nil
    ) -> AdminUserSummary {
        AdminUserSummary(
            userID: id,
            displayName: name,
            authProvider: .apple,
            createdAt: Date(timeIntervalSince1970: 1_690_000_000),
            isAdmin: isAdmin,
            bannedAt: bannedAt
        )
    }

    static func detail(
        id: UUID = userID,
        isSelf: Bool = false,
        isAdmin: Bool = false,
        bannedAt: Date? = nil
    ) -> AdminUserDetail {
        AdminUserDetail(
            userID: id,
            displayName: "Maja",
            authProvider: .apple,
            createdAt: Date(timeIntervalSince1970: 1_690_000_000),
            isAdmin: isAdmin,
            bannedAt: bannedAt,
            isSelf: isSelf,
            banReason: bannedAt == nil ? nil : "Harassing messages",
            bannedByDisplayName: bannedAt == nil ? nil : "Hjalmar",
            onboardingCompletedAt: nil,
            timeZoneID: "Europe/Oslo",
            isEntitled: true,
            coupleID: nil,
            pairedSince: nil,
            partnerUserID: nil,
            partnerDisplayName: nil,
            reportsAgainstCount: 0,
            reportsByCount: 0
        )
    }

    static func entry(action: AdminAuditEntry.Action = .userBanned) -> AdminAuditEntry {
        AdminAuditEntry(
            id: UUID(),
            action: action,
            adminUserID: adminID,
            adminDisplayName: "Hjalmar",
            operatorIdentifier: nil,
            targetUserID: userID,
            targetDisplayName: "Maja",
            reason: action == .userBanned ? "Harassing messages" : nil,
            createdAt: bannedAt
        )
    }

    static func serverError(_ message: String, code: String = "42501") -> PaeoniaConvexError {
        .server(code: code, message: message)
    }
}
