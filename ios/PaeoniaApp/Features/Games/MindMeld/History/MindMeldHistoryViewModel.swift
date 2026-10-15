import Foundation
import Observation

/// "Our melds": the couple's numbers and every finished game, newest first. It
/// shows what the Mind Meld cache holds first, so the screen opens offline, then
/// reads the server.
@MainActor
@Observable
final class MindMeldHistoryViewModel {
    /// Finished games, newest first.
    private(set) var games: [RemoteMindMeldHistoryGame] = []
    private(set) var stats: RemoteMindMeldStats?
    /// The first read is under way and there is nothing to show yet.
    private(set) var isLoading = true
    /// Why the first read failed, while there is nothing to show.
    private(set) var loadFailure: PaeoniaFailure?
    var loadFailed: Bool {
        loadFailure != nil
    }
    private(set) var loadMoreFailed = false
    /// There are older games to load.
    private(set) var hasMore = false
    private(set) var me: MindMeldPlayer
    private(set) var partner: MindMeldPlayer

    nonisolated static let defaultPageSize = 30
    /// A row this close to the end of the list loads the next page.
    nonisolated static let loadMoreDistance = 6

    @ObservationIgnored private let dependencies: GamesDependencies
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var participants: GameParticipants
    @ObservationIgnored private var hasReadCache = false
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var nextCursor: Int?
    @ObservationIgnored private var isLoadingMore = false

    init(
        dependencies: GamesDependencies,
        participants: GameParticipants = GameParticipants(),
        pageSize: Int = MindMeldHistoryViewModel.defaultPageSize
    ) {
        self.dependencies = dependencies
        self.participants = participants
        self.pageSize = pageSize
        (me, partner) = participants.mindMeldPlayers
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    var partnerName: String {
        partner.name
    }

    /// Names who is playing. Safe to call again when the names load. A change of
    /// user or couple clears what was loaded.
    func configure(participants newParticipants: GameParticipants) {
        let identityChanged = participants.currentUserID != newParticipants.currentUserID
            || participants.coupleID != newParticipants.coupleID
        participants = newParticipants
        (me, partner) = newParticipants.mindMeldPlayers
        if identityChanged {
            games = []
            stats = nil
            isLoading = true
            loadFailure = nil
            loadMoreFailed = false
            hasMore = false
            hasReadCache = false
            hasLoaded = false
            nextCursor = nil
        }
    }

    // MARK: - Reading

    /// Shows the cache, then reads the first page from the server. A failed read
    /// keeps what is on screen.
    func load() async {
        guard let userID = currentUserID else { return }
        await readCache(for: userID)
        do {
            let page = try await dependencies.mindMeldGateway.loadMindMeldHistory(
                beforeGameNumber: nil,
                limit: pageSize
            )
            guard !Task.isCancelled, currentUserID == userID else { return }
            refresh(with: page)
            await dependencies.mindMeldCache.saveHistoryFirstPage(page, ownerUserID: userID)
        } catch {
            guard !error.isCancellation, currentUserID == userID else { return }
            // Only a screen with nothing to show says the read failed.
            loadFailure = games.isEmpty ? PaeoniaFailure(error) : nil
        }
        isLoading = false
    }

    private func readCache(for userID: UUID) async {
        guard !hasReadCache else { return }
        hasReadCache = true
        let page = await dependencies.mindMeldCache.document(ownerUserID: userID).history
        guard currentUserID == userID, !hasLoaded, let page else { return }
        refresh(with: page)
        isLoading = false
    }

    /// Takes the first page of a fresh read. A list that was never paged past its
    /// first page is replaced. One the person scrolled further keeps the older
    /// games it has, so a refresh does not throw away their place. That only works
    /// when the new page reaches the games already here. After many new games there
    /// would be a gap the cursor never comes back to, so the list starts over.
    private func refresh(with page: RemoteMindMeldHistoryPage) {
        let wasPaged = games.count > pageSize
        if wasPaged, page.nextBeforeGameNumber != nil, let oldest = page.games.last?.gameNumber,
           let newestKnown = games.first?.gameNumber, oldest <= newestKnown {
            games = page.games + games.filter { $0.gameNumber < oldest }
        } else {
            games = page.games
            nextCursor = page.nextBeforeGameNumber
        }
        hasMore = nextCursor != nil
        stats = page.stats
        hasLoaded = true
        loadFailure = nil
    }

    // MARK: - Paging

    /// Loads the next page when `game` is among the last ones shown.
    func loadMoreIfNeeded(after game: RemoteMindMeldHistoryGame) async {
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
        guard let userID = currentUserID, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            let page = try await dependencies.mindMeldGateway.loadMindMeldHistory(
                beforeGameNumber: cursor,
                limit: pageSize
            )
            // A refresh that replaced the list meanwhile set its own cursor, and
            // this page would skip the games between the two.
            guard currentUserID == userID, nextCursor == cursor else { return }
            let known = Set(games.map(\.id))
            games += page.games.filter { !known.contains($0.id) }
            nextCursor = page.nextBeforeGameNumber
            hasMore = nextCursor != nil
            stats = page.stats
        } catch {
            guard currentUserID == userID else { return }
            // A cancelled read says nothing about the network. The next row that
            // appears asks again.
            loadMoreFailed = !error.isCancellation
        }
    }
}
