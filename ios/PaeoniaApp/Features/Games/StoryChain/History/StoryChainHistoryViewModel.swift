import Foundation
import Observation

/// The stories of one filter ("All" or "Starred") that the screen has loaded so
/// far, newest first, and where the next page starts.
nonisolated struct StoryChainHistoryListing: Equatable, Sendable {
    var items: [RemoteStoryChainHistoryItem] = []
    /// The cursor for the next page. Nil when there are no more stories.
    var nextCursor: Int?
    /// The cache or the server has answered, even if the answer is no stories.
    var hasLoaded = false
    /// Why the last try to load the first page failed. Nil after a good read.
    var failure: PaeoniaFailure?
    var isLoadingMore = false
    var loadMoreFailed = false

    var hasMore: Bool {
        nextCursor != nil
    }

    /// Takes the first page of a fresh read. A listing that was never paged past
    /// its first page is replaced. One the person scrolled further keeps the
    /// older stories it has, so a refresh does not throw away their place. That
    /// only works when the new page reaches the stories already here. After many
    /// new stories there would be a gap the cursor never comes back to, so the
    /// listing starts over from the new page.
    mutating func refresh(with page: RemoteStoryChainHistoryPage, pageSize: Int) {
        let wasPaged = items.count > pageSize
        if wasPaged, page.nextBeforeStoryNumber != nil, let oldest = page.stories.last?.storyNumber,
           let newestKnown = items.first?.storyNumber, oldest <= newestKnown {
            let older = items.filter { $0.storyNumber < oldest }
            items = page.stories + older
        } else {
            items = page.stories
            nextCursor = page.nextBeforeStoryNumber
        }
        hasLoaded = true
        failure = nil
    }

    /// Adds an older page. A story that is already here is not added twice.
    mutating func append(_ page: RemoteStoryChainHistoryPage) {
        let known = Set(items.map(\.id))
        items += page.stories.filter { !known.contains($0.id) }
        nextCursor = page.nextBeforeStoryNumber
        loadMoreFailed = false
    }
}

/// "Our stories": every finished story with the "All" and "Starred" filters. It
/// shows what the Story Chain cache holds first, so the screen opens offline,
/// then reads the server.
@MainActor
@Observable
final class StoryChainHistoryViewModel {
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

    let stars: StoryChainStars

    nonisolated static let defaultPageSize = 30
    /// A row this close to the end of the list loads the next page.
    nonisolated static let loadMoreDistance = 6

    @ObservationIgnored private let dependencies: GamesDependencies
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var participants: GameParticipants
    @ObservationIgnored private var hasReadCache = false
    private var listings: [Filter: StoryChainHistoryListing] = [:]

    init(
        dependencies: GamesDependencies,
        stars: StoryChainStars,
        participants: GameParticipants = GameParticipants(),
        pageSize: Int = StoryChainHistoryViewModel.defaultPageSize
    ) {
        self.dependencies = dependencies
        self.stars = stars
        self.participants = participants
        self.pageSize = pageSize
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

    private func listing(_ filter: Filter) -> StoryChainHistoryListing {
        listings[filter] ?? StoryChainHistoryListing()
    }

    /// The stories of `filter`, newest first. "Starred" shows the stories this
    /// person starred, with unsent changes applied: a story that was just
    /// unstarred leaves the list, and one that was just starred joins it.
    func items(for filter: Filter) -> [RemoteStoryChainHistoryItem] {
        switch filter {
        case .all:
            return listing(.all).items
        case .starred:
            var byID: [UUID: RemoteStoryChainHistoryItem] = [:]
            for item in listing(.all).items + listing(.starred).items {
                byID[item.id] = item
            }
            return byID.values
                .filter { stars.isStarred($0.id) }
                .sorted { $0.storyNumber > $1.storyNumber }
        }
    }

    /// The stories of the selected filter.
    var visibleItems: [RemoteStoryChainHistoryItem] {
        items(for: filter)
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
        phase == .loaded && visibleItems.isEmpty && !hasMore
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

    /// The couple has no finished story at all, as far as this phone knows.
    var hasNoStories: Bool {
        let all = listing(.all)
        return all.hasLoaded && all.items.isEmpty
    }

    func item(withID storyID: UUID) -> RemoteStoryChainHistoryItem? {
        (listing(.all).items + listing(.starred).items).first { $0.id == storyID }
    }

    // MARK: - Reading

    /// Shows the cache, then reads the first page of the selected filter from
    /// the server. A failed read keeps what is on screen.
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
        let document = await dependencies.storyChainCache.document(ownerUserID: userID)
        guard currentUserID == userID else { return }
        if let page = document.historyFirstPage, !listing(.all).hasLoaded {
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
            let page = try await dependencies.storyChainGateway.loadStoryChainHistory(
                starredOnly: filter == .starred,
                beforeStoryNumber: nil,
                limit: pageSize
            )
            guard !Task.isCancelled, currentUserID == userID else { return }
            var fresh = listing(filter)
            fresh.refresh(with: page, pageSize: pageSize)
            listings[filter] = fresh
            if filter == .all {
                await dependencies.storyChainCache.saveHistoryFirstPage(page, ownerUserID: userID)
            }
            await stars.applyServerStars(page.starValues, readSince: mark)
        } catch {
            guard !Self.isCancellation(error), currentUserID == userID else { return }
            // A failed read keeps the list that is on screen. Only a screen with
            // nothing to show says the read failed.
            listings[filter, default: StoryChainHistoryListing()].failure = PaeoniaFailure(error)
        }
    }

    // MARK: - Paging

    /// Loads the next page when `item` is among the last ones shown.
    func loadMoreIfNeeded(after item: RemoteStoryChainHistoryItem) async {
        guard !loadMoreFailed else { return }
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == item.id }),
              index >= visible.count - Self.loadMoreDistance
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
            let page = try await dependencies.storyChainGateway.loadStoryChainHistory(
                starredOnly: filter == .starred,
                beforeStoryNumber: cursor,
                limit: pageSize
            )
            guard currentUserID == userID else { return }
            listings[filter, default: StoryChainHistoryListing()].append(page)
            listings[filter]?.isLoadingMore = false
            await stars.applyServerStars(page.starValues, readSince: mark)
        } catch {
            guard currentUserID == userID else { return }
            listings[filter]?.isLoadingMore = false
            // A cancelled read says nothing about the network. The next row that
            // appears asks again.
            listings[filter]?.loadMoreFailed = !Self.isCancellation(error)
        }
    }

    // MARK: - One story

    /// A finished story for the detail screen: from the cached state when it
    /// holds the story, otherwise from the server. Nil when the couple has no such
    /// story. Throws when the story is not cached and the read failed.
    func loadStory(id: UUID) async throws -> RemoteStoryChainStory? {
        guard let userID = currentUserID else { return nil }
        let document = await dependencies.storyChainCache.document(ownerUserID: userID)
        let cached = [document.state?.currentStory, document.state?.previousStory]
            .compactMap(\.self)
            .first { $0.id == id && $0.state == .finished }
        if let cached {
            await stars.reload()
            return cached
        }
        let mark = stars.changeMark
        guard let story = try await dependencies.storyChainGateway.loadStory(id: id),
              !Task.isCancelled, currentUserID == userID
        else { return nil }
        if story.state == .finished {
            await stars.applyServerStars([story.id: story.starredByMe], readSince: mark)
        }
        return story
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
