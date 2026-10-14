import Foundation

/// The creatures of one filter ("All" or "Starred") that the screen has loaded so
/// far, newest first, and where the next page starts.
nonisolated struct ExquisiteCorpseHistoryListing: Equatable, Sendable {
    var figures: [RemoteExquisiteCorpseFigure] = []
    /// The cursor for the next page. Nil when there are no more creatures.
    var nextCursor: Int?
    /// The cache or the server has answered, even if the answer is no creatures.
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
    /// older creatures it has, so a refresh does not throw away their place. That
    /// only works when the new page reaches the creatures already here. After many
    /// new creatures there would be a gap the cursor never comes back to, so the
    /// listing starts over from the new page.
    mutating func refresh(with page: RemoteExquisiteCorpseHistoryPage, pageSize: Int) {
        let wasPaged = figures.count > pageSize
        if wasPaged, page.nextBeforeFigureNumber != nil, let oldest = page.figures.last?.number,
           let newestKnown = figures.first?.number, oldest <= newestKnown {
            let older = figures.filter { $0.number < oldest }
            figures = page.figures + older
        } else {
            figures = page.figures
            nextCursor = page.nextBeforeFigureNumber
        }
        hasLoaded = true
        didFail = false
    }

    /// Adds an older page. A creature that is already here is not added twice.
    mutating func append(_ page: RemoteExquisiteCorpseHistoryPage) {
        let known = Set(figures.map(\.id))
        figures += page.figures.filter { !known.contains($0.id) }
        nextCursor = page.nextBeforeFigureNumber
        loadMoreFailed = false
    }
}
