import Foundation
import Observation

/// The starred list in Search. It reads the ids from `FavoritesStore`, newest first, and asks
/// the server what to show for them a page at a time. Taking a star back drops the row at
/// once, because the rows are filtered through the store.
@MainActor
@Observable
final class SavedFavoritesViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(PaeoniaFailure)
    }

    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false

    /// Summaries in the order the server listed the favorites.
    private var loaded: [FavoriteSummary] = []
    /// How many favorites from the front of the list were asked for. Items that came back
    /// empty (deleted since) are counted too, so they are not asked for again.
    private var requested = 0

    @ObservationIgnored private let store: FavoritesStore
    @ObservationIgnored private let gateway: any FavoritesGateway
    @ObservationIgnored private let pageSize: Int

    static let defaultPageSize = 40

    init(
        store: FavoritesStore = .shared,
        gateway: any FavoritesGateway,
        pageSize: Int = SavedFavoritesViewModel.defaultPageSize
    ) {
        self.store = store
        self.gateway = gateway
        self.pageSize = pageSize
    }

    static func live() -> SavedFavoritesViewModel {
        let gateway: any FavoritesGateway = (try? PaeoniaConvexClientProvider.shared.client())
            .map { LiveFavoritesGateway(client: $0) } ?? UnavailableFavoritesGateway()
        return SavedFavoritesViewModel(gateway: gateway)
    }

    /// What the summaries depend on. When it changes, `load()` should run again: a star the
    /// phone just learned about, a star taken back, or a queued star the server has now
    /// received. The server only resolves items it knows are saved, so a queued star has no
    /// summary until its write is sent.
    struct RefreshKey: Equatable {
        let targets: [FavoriteTarget]
        let unsent: Set<FavoriteTarget>
    }

    var refreshKey: RefreshKey {
        RefreshKey(targets: store.allFavorites.map(\.target), unsent: Set(store.pendingChanges.keys))
    }

    /// The starred items that are still starred, newest first.
    var summaries: [FavoriteSummary] {
        loaded.filter { store.isFavorite($0.target) }
    }

    /// The same as Search rows.
    func results(people: StoryPeople, locale: Locale = .current) -> [SearchResult] {
        summaries.compactMap { SearchResult(favorite: $0, people: people, locale: locale) }
    }

    func summary(for target: FavoriteTarget) -> FavoriteSummary? {
        loaded.first { $0.target == target }
    }

    /// More stars are waiting past the rows loaded so far.
    var hasMore: Bool {
        requested < store.allFavorites.count
    }

    /// Reads the first page. Rows already on screen stay while it reads.
    func load() async {
        if loaded.isEmpty { phase = .loading }
        let targets = Array(store.allFavorites.prefix(pageSize).map(\.target))
        do {
            let page = try await gateway.summaries(of: targets)
            guard !Task.isCancelled else { return }
            loaded = page
            requested = targets.count
            phase = .loaded
        } catch {
            guard !error.isCancellation else { return }
            // A failed read keeps the rows that are showing.
            phase = loaded.isEmpty ? .failed(PaeoniaFailure(error)) : .loaded
        }
    }

    /// Reads the next page when the last row comes into view.
    func loadMore() async {
        guard phase == .loaded, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let targets = Array(store.allFavorites.dropFirst(requested).prefix(pageSize).map(\.target))
        guard !targets.isEmpty, let page = try? await gateway.summaries(of: targets), !Task.isCancelled else { return }
        loaded += page.filter { new in !loaded.contains { $0.target == new.target } }
        requested += targets.count
    }
}
