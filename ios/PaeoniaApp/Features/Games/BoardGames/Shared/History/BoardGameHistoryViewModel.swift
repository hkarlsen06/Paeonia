import Foundation
import Observation

/// "Past games" of one board game: every finished game, newest first, read from
/// the server a page at a time.
@MainActor
@Observable
final class BoardGameHistoryViewModel {
    let kind: GameKind
    /// Finished games, newest first.
    private(set) var games: [RemoteBoardGameHistoryGame] = []
    /// The first read is under way and there is nothing to show yet.
    private(set) var isLoading = true
    /// The first read failed and there is nothing to show.
    private(set) var loadFailed = false
    private(set) var loadMoreFailed = false
    /// There are older games to load.
    private(set) var hasMore = false

    nonisolated static let defaultPageSize = 30
    /// A row this close to the end of the list loads the next page.
    nonisolated static let loadMoreDistance = 6

    @ObservationIgnored private let gateway: any BoardGamesGateway
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var userID: UUID?
    @ObservationIgnored private var nextCursor: Int?
    @ObservationIgnored private var isLoadingMore = false

    init(kind: GameKind, gateway: any BoardGamesGateway, pageSize: Int = BoardGameHistoryViewModel.defaultPageSize) {
        self.kind = kind
        self.gateway = gateway
        self.pageSize = pageSize
    }

    /// A change of user clears what was loaded.
    func configure(userID newUserID: UUID?) {
        guard newUserID != userID else { return }
        userID = newUserID
        games = []
        isLoading = true
        loadFailed = false
        loadMoreFailed = false
        hasMore = false
        nextCursor = nil
    }

    func game(numbered gameNumber: Int) -> RemoteBoardGameHistoryGame? {
        games.first { $0.gameNumber == gameNumber }
    }

    // MARK: - Reading

    /// Reads the first page. A failed read keeps what is on screen.
    func load() async {
        guard let userID else { return }
        do {
            let page = try await gateway.loadHistory(kind, beforeGameNumber: nil, limit: pageSize)
            guard !Task.isCancelled, self.userID == userID else { return }
            refresh(with: page)
        } catch {
            guard !Self.isCancellation(error), self.userID == userID else { return }
            // Only a screen with nothing to show says it is offline.
            loadFailed = games.isEmpty
        }
        isLoading = false
    }

    /// Takes the first page of a fresh read. A list scrolled past its first page
    /// keeps its older games when the new page reaches them. Otherwise the list
    /// starts over, so there is never a gap the cursor skips.
    private func refresh(with page: RemoteBoardGameHistoryPage) {
        let wasPaged = games.count > pageSize
        if wasPaged, page.nextBeforeGameNumber != nil, let oldest = page.games.last?.gameNumber,
           let newestKnown = games.first?.gameNumber, oldest <= newestKnown {
            games = page.games + games.filter { $0.gameNumber < oldest }
        } else {
            games = page.games
            nextCursor = page.nextBeforeGameNumber
        }
        hasMore = nextCursor != nil
        loadFailed = false
    }

    // MARK: - Paging

    /// Loads the next page when `game` is among the last ones shown.
    func loadMoreIfNeeded(after game: RemoteBoardGameHistoryGame) async {
        guard !loadMoreFailed,
              let index = games.firstIndex(where: { $0.id == game.id }),
              index >= games.count - Self.loadMoreDistance
        else { return }
        await loadMore()
    }

    func retryLoadMore() async {
        await loadMore()
    }

    private func loadMore() async {
        guard let userID, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            let page = try await gateway.loadHistory(kind, beforeGameNumber: cursor, limit: pageSize)
            // A refresh that replaced the list meanwhile set its own cursor, and
            // this page would skip the games between the two.
            guard self.userID == userID, nextCursor == cursor else { return }
            let known = Set(games.map(\.id))
            games += page.games.filter { !known.contains($0.id) }
            nextCursor = page.nextBeforeGameNumber
            hasMore = nextCursor != nil
        } catch {
            guard self.userID == userID else { return }
            // A cancelled read says nothing about the network. The next row that
            // appears asks again.
            loadMoreFailed = !Self.isCancellation(error)
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
