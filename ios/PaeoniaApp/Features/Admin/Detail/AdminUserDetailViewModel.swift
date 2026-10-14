import Foundation
import Observation

@MainActor
@Observable
final class AdminUserDetailViewModel {
    /// The server accepts a ban reason of 1 to 500 characters, counted as Unicode
    /// code points, after trimming.
    static let reasonLengthLimit = 500

    let userID: UUID
    private(set) var user: AdminUserDetail?
    /// The admin log entries about this user, newest first.
    private(set) var history = [AdminAuditEntry]()
    /// True once the first load finished, whether or not it worked.
    private(set) var hasLoaded = false
    private(set) var isWorking = false
    private(set) var notice: AdminNotice?

    private let gateway: any AdminGateway
    /// Runs after a ban or unban, so the list behind this screen shows the change.
    private let onChanged: @MainActor () async -> Void

    init(
        userID: UUID,
        gateway: any AdminGateway,
        onChanged: @escaping @MainActor () async -> Void = {}
    ) {
        self.userID = userID
        self.gateway = gateway
        self.onChanged = onChanged
    }

    /// Whether `reason` is one the server accepts.
    static func isValidReason(_ reason: String) -> Bool {
        let count = reason.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        return (1...reasonLengthLimit).contains(count)
    }

    func load() async {
        do {
            let loadedUser = try await gateway.loadUser(id: userID)
            let entries = try await gateway.loadAuditLog(targetUserID: userID)
            guard !Task.isCancelled else {
                return
            }
            user = loadedUser
            history = entries
            hasLoaded = true
            if loadedUser == nil {
                notice = .userNotFound
            }
        } catch {
            guard !Task.isCancelled, let failure = AdminNotice(loadError: error) else {
                return
            }
            notice = failure
            hasLoaded = true
        }
    }

    /// Returns true when the ban went through.
    @discardableResult
    func ban(reason: String) async -> Bool {
        guard !isWorking, user?.canBan == true else {
            return false
        }
        guard Self.isValidReason(reason) else {
            notice = .reasonInvalid
            return false
        }
        isWorking = true
        defer { isWorking = false }

        do {
            try await gateway.banUser(
                id: userID,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            notice = AdminNotice(banError: error)
            return false
        }
        await refreshAfterChange(success: .banned)
        return true
    }

    /// Returns true when the ban was lifted.
    @discardableResult
    func unban() async -> Bool {
        guard !isWorking, user?.canUnban == true else {
            return false
        }
        isWorking = true
        defer { isWorking = false }

        do {
            try await gateway.unbanUser(id: userID)
        } catch {
            notice = AdminNotice(unbanError: error)
            return false
        }
        await refreshAfterChange(success: .unbanned)
        return true
    }

    func dismissNotice() {
        notice = nil
    }

    /// Reloads this screen, then the list. A failed reload shows its own notice
    /// instead of the success one, because the screen may now be out of date.
    private func refreshAfterChange(success: AdminNotice) async {
        notice = nil
        await load()
        if notice == nil {
            notice = success
        }
        await onChanged()
    }
}
