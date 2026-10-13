import Foundation

/// The rounds of one filter ("All" or "Starred") that the screen has loaded so
/// far, newest first, and where the next page starts.
nonisolated struct DrawAndGuessHistoryListing: Equatable, Sendable {
    var rounds: [RemoteDrawAndGuessHistoryRound] = []
    /// The cursor for the next page. Nil when there are no more rounds.
    var nextCursor: Int?
    /// The cache or the server has answered, even if the answer is no rounds.
    var hasLoaded = false
    /// The last try to load the first page failed.
    var didFail = false
    var isLoadingMore = false
    var loadMoreFailed = false

    var hasMore: Bool {
        nextCursor != nil
    }

    /// Takes the first page of a fresh read. A listing that was never paged past
    /// its first page is replaced. One the person scrolled further keeps the
    /// older rounds it has, so a refresh does not throw away their place. That
    /// only works when the new page reaches the rounds already here. After many
    /// new rounds there would be a gap the cursor never comes back to, so the
    /// listing starts over from the new page.
    mutating func refresh(with page: RemoteDrawAndGuessHistoryPage, pageSize: Int) {
        let wasPaged = rounds.count > pageSize
        if wasPaged, page.nextBeforeRoundNumber != nil, let oldest = page.rounds.last?.roundNumber,
           let newestKnown = rounds.first?.roundNumber, oldest <= newestKnown {
            let older = rounds.filter { $0.roundNumber < oldest }
            rounds = page.rounds + older
        } else {
            rounds = page.rounds
            nextCursor = page.nextBeforeRoundNumber
        }
        hasLoaded = true
        didFail = false
    }

    /// Adds an older page. A round that is already here is not added twice.
    mutating func append(_ page: RemoteDrawAndGuessHistoryPage) {
        let known = Set(rounds.map(\.id))
        rounds += page.rounds.filter { !known.contains($0.id) }
        nextCursor = page.nextBeforeRoundNumber
        loadMoreFailed = false
    }
}
