import Foundation
import Observation

/// The users list, or the banned users list. Typing is debounced by the screen's
/// `.task(id: searchText)`, which calls `search()` for each change and cancels the
/// call before it.
@MainActor
@Observable
final class AdminUsersViewModel {
    /// Searches start at this many characters. Empty text lists the newest users.
    static let minimumSearchLength = 2
    static let debounce = Duration.milliseconds(300)

    let bannedOnly: Bool
    var searchText = ""
    private(set) var users = [AdminUserSummary]()
    /// True once the first load finished, whether or not it worked.
    private(set) var hasLoaded = false
    private(set) var notice: AdminNotice?

    private let gateway: any AdminGateway
    private let sleep: @Sendable (Duration) async throws -> Void
    /// The text behind `users`, so a screen coming back from a detail reloads
    /// without waiting out the debounce.
    private var loadedQuery: String?

    init(
        bannedOnly: Bool,
        gateway: any AdminGateway,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.bannedOnly = bannedOnly
        self.gateway = gateway
        self.sleep = sleep
    }

    /// True while the text is one character, too short to search.
    var isSearchTooShort: Bool {
        !bannedOnly && trimmedSearch.count < Self.minimumSearchLength && !trimmedSearch.isEmpty
    }

    /// Loads for the current text. Waits out the debounce first when the text
    /// changed since the last load, and drops its result when cancelled.
    func search() async {
        guard !isSearchTooShort else {
            return
        }
        let query = currentQuery
        if hasLoaded, query != loadedQuery {
            do {
                try await sleep(Self.debounce)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
        }
        await load(query: query)
    }

    /// Pull to refresh, and after a ban or unban changed a row.
    func refresh() async {
        await load(query: isSearchTooShort ? loadedQuery : currentQuery)
    }

    func dismissNotice() {
        notice = nil
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentQuery: String? {
        guard !bannedOnly, !trimmedSearch.isEmpty else {
            return nil
        }
        return trimmedSearch
    }

    private func load(query: String?) async {
        do {
            let result = try await gateway.searchUsers(query: query, bannedOnly: bannedOnly)
            guard !Task.isCancelled else {
                return
            }
            users = result
            loadedQuery = query
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, let failure = AdminNotice(loadError: error) else {
                return
            }
            notice = failure
            hasLoaded = true
        }
    }
}
