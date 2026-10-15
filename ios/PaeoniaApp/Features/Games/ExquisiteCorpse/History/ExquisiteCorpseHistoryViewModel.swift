import Foundation
import Observation

/// "Our creatures": every finished creature, with the "All" and "Starred"
/// filters. It shows what the Exquisite corpse cache holds first, so the screen
/// opens offline, then reads the server.
@MainActor
@Observable
final class ExquisiteCorpseHistoryViewModel {
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

    let stars: GameStars
    let drawings: GameHistoryDrawings

    nonisolated static let defaultPageSize = 30
    /// A cell this close to the end of the list loads the next page.
    nonisolated static let loadMoreDistance = 6

    @ObservationIgnored private let dependencies: GamesDependencies
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var participants: GameParticipants
    @ObservationIgnored private var hasReadCache = false
    private var listings: [Filter: ExquisiteCorpseHistoryListing] = [:]

    init(
        dependencies: GamesDependencies,
        stars: GameStars,
        participants: GameParticipants = GameParticipants(),
        pageSize: Int = ExquisiteCorpseHistoryViewModel.defaultPageSize
    ) {
        self.dependencies = dependencies
        self.stars = stars
        self.participants = participants
        self.pageSize = pageSize
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
        if identityChanged {
            listings = [:]
            hasReadCache = false
        }
    }

    // MARK: - What the screen shows

    private func listing(_ filter: Filter) -> ExquisiteCorpseHistoryListing {
        listings[filter] ?? ExquisiteCorpseHistoryListing()
    }

    /// The creatures of the selected filter, newest first. "Starred" shows the
    /// creatures this person starred, with unsent changes applied: one that was
    /// just unstarred leaves the list, and one that was just starred joins it.
    var visibleFigures: [RemoteExquisiteCorpseFigure] {
        switch filter {
        case .all:
            return listing(.all).figures
        case .starred:
            var byID: [UUID: RemoteExquisiteCorpseFigure] = [:]
            for figure in listing(.all).figures + listing(.starred).figures {
                byID[figure.id] = figure
            }
            return byID.values
                .filter { stars.isStarred($0.id) }
                .sorted { $0.number > $1.number }
        }
    }

    var phase: Phase {
        let current = listing(filter)
        if current.hasLoaded {
            return .loaded
        }
        // The starred read failed, but the cached "All" list still tells which are starred.
        if filter == .starred, current.failure != nil, listing(.all).hasLoaded {
            return .loaded
        }
        return current.failure.map(Phase.failed) ?? .loading
    }

    var isEmpty: Bool {
        phase == .loaded && visibleFigures.isEmpty && !hasMore
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

    /// The couple has no finished creature, as far as this phone knows.
    var hasNoCreatures: Bool {
        let all = listing(.all)
        return all.hasLoaded && all.figures.isEmpty
    }

    /// How many creatures the couple has finished. Creatures are numbered from 1 in
    /// the order they finish, so the newest number is the count. Zero until the
    /// list has loaded.
    var creatureCount: Int {
        listing(.all).figures.first?.number ?? 0
    }

    func figure(withID figureID: UUID) -> RemoteExquisiteCorpseFigure? {
        (listing(.all).figures + listing(.starred).figures).first { $0.id == figureID }
    }

    func makeDetail(figureID: UUID) -> ExquisiteCorpseHistoryDetailViewModel? {
        figure(withID: figureID).map {
            ExquisiteCorpseHistoryDetailViewModel(
                figure: $0,
                participants: participants,
                stars: stars,
                drawings: drawings
            )
        }
    }

    // MARK: - Reading

    /// Shows the cache, then reads the first page of the selected filter from the
    /// server. A failed read keeps what is on screen.
    func refresh() async {
        await readCache()
        await fetchFirstPage(filter)
    }

    func retry() async {
        await refresh()
    }

    private func readCache() async {
        guard !hasReadCache, let userID = currentUserID else { return }
        hasReadCache = true
        let document = await dependencies.exquisiteCorpseCache.document(ownerUserID: userID)
        guard currentUserID == userID else { return }
        if let page = document.history, !listing(.all).hasLoaded {
            var cached = listing(.all)
            cached.refresh(with: page, pageSize: pageSize)
            listings[.all] = cached
        }
        await stars.reload()
    }

    private func fetchFirstPage(_ filter: Filter) async {
        guard let userID = currentUserID else { return }
        let mark = stars.changeMark
        do {
            let page = try await dependencies.exquisiteCorpseGateway.loadExquisiteCorpseHistory(
                starredOnly: filter == .starred,
                beforeFigureNumber: nil,
                limit: pageSize
            )
            guard !Task.isCancelled, currentUserID == userID else { return }
            var fresh = listing(filter)
            fresh.refresh(with: page, pageSize: pageSize)
            listings[filter] = fresh
            if filter == .all {
                await dependencies.exquisiteCorpseCache.saveHistoryFirstPage(page, ownerUserID: userID)
            }
            await stars.applyServerStars(page.starValues, readSince: mark)
        } catch {
            guard !error.isCancellation, currentUserID == userID else { return }
            // A failed read keeps the list that is on screen. Only a screen with
            // nothing to show says the read failed.
            listings[filter, default: ExquisiteCorpseHistoryListing()].failure = PaeoniaFailure(error)
        }
    }

    // MARK: - Paging

    /// Loads the next page when `figure` is among the last ones shown.
    func loadMoreIfNeeded(after figure: RemoteExquisiteCorpseFigure) async {
        guard !loadMoreFailed else { return }
        let figures = visibleFigures
        guard let index = figures.firstIndex(where: { $0.id == figure.id }),
              index >= figures.count - Self.loadMoreDistance
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
        let mark = stars.changeMark
        do {
            let page = try await dependencies.exquisiteCorpseGateway.loadExquisiteCorpseHistory(
                starredOnly: filter == .starred,
                beforeFigureNumber: cursor,
                limit: pageSize
            )
            guard currentUserID == userID else { return }
            listings[filter, default: ExquisiteCorpseHistoryListing()].append(page)
            listings[filter]?.isLoadingMore = false
            await stars.applyServerStars(page.starValues, readSince: mark)
        } catch {
            guard currentUserID == userID else { return }
            listings[filter]?.isLoadingMore = false
            // A cancelled read says nothing about the network. The next cell that
            // appears asks again.
            listings[filter]?.loadMoreFailed = !error.isCancellation
        }
    }
}
