import Foundation
import Observation

/// "Our drawings": the records of both partners and every finished drawing,
/// with the "All" and "Starred" filters. It shows what the Games cache holds
/// first, so the screen opens offline, then reads the server.
@MainActor
@Observable
final class DrawAndGuessHistoryViewModel {
    enum Filter: Hashable, CaseIterable {
        case all
        case starred
    }

    enum Phase: Equatable {
        /// Nothing to show yet and the first read has not finished.
        case loading
        case loaded
        /// Nothing cached and the first read failed.
        case failed(PaeoniaFailure)
    }

    var filter: Filter = .all
    private(set) var records: RemoteDrawAndGuessRecords?
    private(set) var me: GamePlayer
    private(set) var partner: GamePlayer

    let drawings: GameHistoryDrawings

    nonisolated static let defaultPageSize = 30
    /// A cell this close to the end of the list loads the next page.
    nonisolated static let loadMoreDistance = 6

    @ObservationIgnored private let dependencies: GamesDependencies
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var participants: GameParticipants
    @ObservationIgnored private var hasReadCache = false
    private var listings: [Filter: DrawAndGuessHistoryListing] = [:]

    init(
        dependencies: GamesDependencies,
        participants: GameParticipants = GameParticipants(),
        pageSize: Int = DrawAndGuessHistoryViewModel.defaultPageSize
    ) {
        self.dependencies = dependencies
        self.participants = participants
        self.pageSize = pageSize
        (me, partner) = participants.players
        drawings = GameHistoryDrawings(store: dependencies.drawingStore, transfer: dependencies.drawingTransfer)
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    var partnerName: String {
        participants.partnerName
    }

    /// Names who is playing. Safe to call again when the names load. A change of
    /// user or couple clears what was loaded.
    func configure(participants newParticipants: GameParticipants) {
        let identityChanged = participants.currentUserID != newParticipants.currentUserID
            || participants.coupleID != newParticipants.coupleID
        participants = newParticipants
        (me, partner) = newParticipants.players
        if identityChanged {
            listings = [:]
            records = nil
            hasReadCache = false
        }
    }

    // MARK: - What the screen shows

    private func listing(_ filter: Filter) -> DrawAndGuessHistoryListing {
        listings[filter] ?? DrawAndGuessHistoryListing()
    }

    /// The drawings of the selected filter, newest first. "Starred" shows the
    /// rounds this person favorited, with unsent changes applied: a drawing that was
    /// just unstarred leaves the list, and one that was just starred joins it.
    var visibleRounds: [RemoteDrawAndGuessHistoryRound] {
        switch filter {
        case .all:
            return listing(.all).rounds
        case .starred:
            var byID: [UUID: RemoteDrawAndGuessHistoryRound] = [:]
            for round in listing(.all).rounds + listing(.starred).rounds {
                byID[round.id] = round
            }
            return byID.values
                .filter { isFavorite($0) }
                .sorted { $0.roundNumber > $1.roundNumber }
        }
    }

    /// Whether this person starred the drawing, with their unsent changes applied.
    func isFavorite(_ round: RemoteDrawAndGuessHistoryRound) -> Bool {
        dependencies.favorites.isFavorite(.gameRound(round.id))
    }

    var phase: Phase {
        let current = listing(filter)
        if current.hasLoaded {
            return .loaded
        }
        // The starred read failed, but the cached "All" list and the favorites still tell which are starred.
        if filter == .starred, current.failure != nil, listing(.all).hasLoaded {
            return .loaded
        }
        return current.failure.map(Phase.failed) ?? .loading
    }

    var isEmpty: Bool {
        phase == .loaded && visibleRounds.isEmpty && !hasMore
    }

    var hasMore: Bool {
        listing(filter).hasMore
    }

    var isLoadingMore: Bool {
        listing(filter).isLoadingMore
    }

    var loadMoreFailed: Bool {
        listing(filter).loadMoreFailed
    }

    /// The couple has no drawing at all, as far as this phone knows.
    var hasNoDrawings: Bool {
        let all = listing(.all)
        return all.hasLoaded && all.rounds.isEmpty
    }

    var myRecords: RemoteDrawAndGuessPlayerRecords? {
        records?.records(for: currentUserID)
    }

    var partnerRecords: RemoteDrawAndGuessPlayerRecords? {
        records?.partnerRecords(besides: currentUserID)
    }

    func round(withID roundID: UUID) -> RemoteDrawAndGuessHistoryRound? {
        (listing(.all).rounds + listing(.starred).rounds).first { $0.id == roundID }
    }

    /// Who drew the round, as the cell says it: the partner's name, or "you".
    func drawerName(of round: RemoteDrawAndGuessHistoryRound) -> String {
        round.drawerUserID == currentUserID ? String(localized: .gamesDrawAndGuessHistoryWhoYou) : partnerName
    }

    func makeDetail(roundID: UUID) -> DrawAndGuessHistoryDetailViewModel? {
        round(withID: roundID).map(makeDetail(round:))
    }

    func makeDetail(round: RemoteDrawAndGuessHistoryRound) -> DrawAndGuessHistoryDetailViewModel {
        DrawAndGuessHistoryDetailViewModel(round: round, participants: participants, drawings: drawings)
    }

    /// A finished round for the detail screen: from the loaded lists or the cache when they
    /// hold it, otherwise from the server. A saved or searched drawing may not be in either,
    /// for example right after a launch. Nil when the couple has no such round. Throws when
    /// the round is not on the phone and the read failed.
    func loadRound(id roundID: UUID) async throws -> RemoteDrawAndGuessHistoryRound? {
        if let known = round(withID: roundID) { return known }
        await readCache()
        if let cached = round(withID: roundID) { return cached }
        guard let userID = currentUserID else { return nil }
        let fetched = try await dependencies.gateway.loadDrawAndGuessHistoryRound(roundID: roundID)
        guard !Task.isCancelled, currentUserID == userID else { return nil }
        return fetched
    }

    // MARK: - Reading

    /// Shows the cache, then reads the first page of the selected filter and the
    /// records from the server. A failed read keeps what is on screen.
    func refresh() async {
        await readCache()
        async let records: Void = fetchRecords()
        await fetchFirstPage(filter)
        await records
    }

    func retry() async {
        await refresh()
    }

    private func readCache() async {
        guard !hasReadCache, let userID = currentUserID else { return }
        hasReadCache = true
        let document = await dependencies.cache.document(ownerUserID: userID)
        guard currentUserID == userID else { return }
        if let page = document.drawings?.firstPage, !listing(.all).hasLoaded {
            var cached = listing(.all)
            cached.refresh(with: page, pageSize: pageSize)
            listings[.all] = cached
        }
        if records == nil {
            records = document.drawings?.records
        }
    }

    private func fetchRecords() async {
        guard let userID = currentUserID,
              let fresh = try? await dependencies.gateway.loadDrawAndGuessRecords(),
              !Task.isCancelled, currentUserID == userID
        else { return }
        records = fresh
        await dependencies.cache.saveRecords(fresh, ownerUserID: userID)
    }

    private func fetchFirstPage(_ filter: Filter) async {
        guard let userID = currentUserID else { return }
        do {
            let page = try await dependencies.gateway.loadDrawAndGuessHistory(
                starredOnly: filter == .starred,
                beforeRoundNumber: nil,
                limit: pageSize
            )
            guard !Task.isCancelled, currentUserID == userID else { return }
            var fresh = listing(filter)
            fresh.refresh(with: page, pageSize: pageSize)
            listings[filter] = fresh
            if filter == .all {
                await dependencies.cache.saveHistoryFirstPage(page, ownerUserID: userID)
            }
        } catch {
            guard !error.isCancellation, currentUserID == userID else { return }
            // A failed read keeps the list that is on screen. Only a screen with
            // nothing to show says the read failed.
            listings[filter, default: DrawAndGuessHistoryListing()].failure = PaeoniaFailure(error)
        }
    }

    // MARK: - Paging

    /// Loads the next page when `round` is among the last ones shown.
    func loadMoreIfNeeded(after round: RemoteDrawAndGuessHistoryRound) async {
        guard !loadMoreFailed else { return }
        let rounds = visibleRounds
        guard let index = rounds.firstIndex(where: { $0.id == round.id }),
              index >= rounds.count - Self.loadMoreDistance
        else { return }
        await loadMore()
    }

    func retryLoadMore() async {
        await loadMore()
    }

    private func loadMore() async {
        let filter = filter
        guard let userID = currentUserID else { return }
        var current = listing(filter)
        guard let cursor = current.nextCursor, !current.isLoadingMore else { return }
        current.isLoadingMore = true
        current.loadMoreFailed = false
        listings[filter] = current
        do {
            let page = try await dependencies.gateway.loadDrawAndGuessHistory(
                starredOnly: filter == .starred,
                beforeRoundNumber: cursor,
                limit: pageSize
            )
            guard currentUserID == userID else { return }
            listings[filter, default: DrawAndGuessHistoryListing()].append(page)
            listings[filter]?.isLoadingMore = false
        } catch {
            guard currentUserID == userID else { return }
            listings[filter]?.isLoadingMore = false
            // A cancelled read says nothing about the network. The next cell that
            // appears asks again.
            listings[filter]?.loadMoreFailed = !error.isCancellation
        }
    }
}
