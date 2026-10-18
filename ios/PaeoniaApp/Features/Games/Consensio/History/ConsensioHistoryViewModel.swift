import Foundation
import Observation

/// "What we know": every guessed round, newest first, and each partner's record
/// as a guesser. It shows what the Consensio cache holds first, so the screen
/// opens offline, then reads the server.
@MainActor
@Observable
final class ConsensioHistoryViewModel {
    private(set) var rounds: [RemoteConsensioRound] = []
    private(set) var records: RemoteConsensioRecords?
    private(set) var isLoading = true
    private(set) var loadFailure: PaeoniaFailure?
    private(set) var loadMoreFailed = false
    private(set) var hasMore = false
    private(set) var me: GamePlayer
    private(set) var partner: GamePlayer

    nonisolated static let defaultPageSize = 30
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
        pageSize: Int = ConsensioHistoryViewModel.defaultPageSize
    ) {
        self.dependencies = dependencies
        self.participants = participants
        self.pageSize = pageSize
        (me, partner) = participants.players
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    var partnerName: String {
        partner.name
    }

    func round(_ id: UUID) -> RemoteConsensioRound? {
        rounds.first { $0.id == id }
    }

    func configure(participants newParticipants: GameParticipants) {
        let identityChanged = participants.currentUserID != newParticipants.currentUserID
            || participants.coupleID != newParticipants.coupleID
        participants = newParticipants
        (me, partner) = newParticipants.players
        if identityChanged {
            rounds = []
            records = nil
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

    /// Shows the cache, then reads the first page. A failed read keeps what is on screen.
    func load() async {
        guard let userID = currentUserID else { return }
        await readCache(for: userID)
        do {
            let page = try await dependencies.consensioGateway.loadConsensioHistory(
                beforeRoundNumber: nil,
                limit: pageSize
            )
            guard !Task.isCancelled, currentUserID == userID else { return }
            refresh(with: page)
            await dependencies.consensioCache.saveHistoryFirstPage(page, ownerUserID: userID)
        } catch {
            guard !error.isCancellation, currentUserID == userID else { return }
            loadFailure = rounds.isEmpty ? PaeoniaFailure(error) : nil
        }
        isLoading = false
    }

    private func readCache(for userID: UUID) async {
        guard !hasReadCache else { return }
        hasReadCache = true
        let page = await dependencies.consensioCache.document(ownerUserID: userID).history
        guard currentUserID == userID, !hasLoaded, let page else { return }
        refresh(with: page)
        isLoading = false
    }

    /// Takes the first page of a fresh read. A list scrolled past its first page
    /// keeps its older rounds when the new page reaches them.
    private func refresh(with page: RemoteConsensioHistoryPage) {
        let wasPaged = rounds.count > pageSize
        if wasPaged, page.nextBeforeRoundNumber != nil, let oldest = page.rounds.last?.roundNumber,
           let newestKnown = rounds.first?.roundNumber, oldest <= newestKnown {
            rounds = page.rounds + rounds.filter { $0.roundNumber < oldest }
        } else {
            rounds = page.rounds
            nextCursor = page.nextBeforeRoundNumber
        }
        hasMore = nextCursor != nil
        records = page.records
        hasLoaded = true
        loadFailure = nil
    }

    // MARK: - Paging

    func loadMoreIfNeeded(after round: RemoteConsensioRound) async {
        guard !loadMoreFailed,
              let index = rounds.firstIndex(where: { $0.id == round.id }),
              index >= rounds.count - Self.loadMoreDistance
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
            let page = try await dependencies.consensioGateway.loadConsensioHistory(
                beforeRoundNumber: cursor,
                limit: pageSize
            )
            guard currentUserID == userID, nextCursor == cursor else { return }
            let known = Set(rounds.map(\.id))
            rounds += page.rounds.filter { !known.contains($0.id) }
            nextCursor = page.nextBeforeRoundNumber
            hasMore = nextCursor != nil
            records = page.records
        } catch {
            guard currentUserID == userID else { return }
            loadMoreFailed = !error.isCancellation
        }
    }
}
