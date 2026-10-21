import Foundation
import Observation

/// This person's private favorites, for every screen that shows a star or lists the saved
/// items: the question page, the drawings, the games' histories and result screens, and
/// Search. One store covers every kind. `FavoriteKind` names what can be saved.
///
/// The value shown for an item is the server's value with this phone's unsent changes
/// on top. The server's value is the cache, which the live feed and the finished writes
/// keep current. The unsent changes are the queued `setFavorite` writes, so a star shows
/// at once, survives a relaunch, and is sent when the phone is online. The last write of
/// an item wins.
@MainActor
@Observable
final class FavoritesStore {
    /// The store the app uses. Tests and previews build their own.
    static let shared = FavoritesStore.live()

    /// What the server says this person saved, newest first.
    private(set) var serverFavorites: [FavoriteRef] = []
    /// Unsent changes by item: the value the person last chose.
    private(set) var pendingChanges: [FavoriteTarget: Change] = [:]
    /// Show it through the banner center, then call `clearNotice()`.
    var notice: FavoritesNotice?

    /// A favorite or an unfavorite this person made on this phone.
    struct Change: Equatable, Sendable {
        let favorited: Bool
        let createdAt: Date
    }

    @ObservationIgnored private let cache: any FavoritesCaching
    @ObservationIgnored private let pendingOperationStore: any PendingSyncOperationPersisting
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var ownerUserID: UUID?
    @ObservationIgnored private var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?
    /// Changes the person made while their write was still being saved in the queue.
    @ObservationIgnored private var savingChanges: [FavoriteTarget: Change] = [:]
    @ObservationIgnored private var reloadGate = GameReloadGate()
    @ObservationIgnored private var serverTargets: Set<FavoriteTarget> = []

    init(
        cache: any FavoritesCaching,
        pendingOperationStore: any PendingSyncOperationPersisting,
        operationProvider: any SyncClientOperationProviding,
        now: @escaping @Sendable () -> Date = { Date() },
        defaults: UserDefaults = .standard
    ) {
        self.cache = cache
        self.pendingOperationStore = pendingOperationStore
        self.operationProvider = operationProvider
        self.now = now
        self.defaults = defaults
    }

    /// Remembers that the person was told once that favorites are private.
    private static let privacyHintKey = "favorites.privacyHintShown"

    static func live() -> FavoritesStore {
        let pendingStore: any PendingSyncOperationPersisting
        if let localStore = PaeoniaLocalStore.shared {
            pendingStore = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        } else {
            pendingStore = InMemoryPendingSyncOperationRepository()
        }
        return FavoritesStore(
            cache: FileFavoritesCache.shared,
            pendingOperationStore: pendingStore,
            operationProvider: SyncClientOperationFactory.shared
        )
    }

    /// A store that keeps everything in memory, for previews, tests and the developer scenarios.
    static func inMemory(
        pendingOperationStore: any PendingSyncOperationPersisting = InMemoryPendingSyncOperationRepository(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> FavoritesStore {
        FavoritesStore(
            cache: InMemoryFavoritesCache(),
            pendingOperationStore: pendingOperationStore,
            operationProvider: SyncClientOperationFactory.shared,
            now: now
        )
    }

    /// A store that keeps everything in memory and already holds these favorites for this
    /// person, for the developer scenarios and tests.
    static func preloaded(
        ownerUserID: UUID,
        favorites: [FavoriteRef],
        pendingOperationStore: any PendingSyncOperationPersisting = InMemoryPendingSyncOperationRepository(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> FavoritesStore {
        let store = FavoritesStore(
            cache: InMemoryFavoritesCache(seed: [ownerUserID: favorites]),
            pendingOperationStore: pendingOperationStore,
            operationProvider: SyncClientOperationFactory.shared,
            now: now
        )
        store.ownerUserID = ownerUserID
        store.serverFavorites = favorites
        store.serverTargets = Set(favorites.map(\.target))
        return store
    }

    // MARK: - Setup

    /// Follows the signed-in person. A different person starts from nothing.
    func configure(ownerUserID: UUID?) async {
        if self.ownerUserID != ownerUserID {
            serverFavorites = []
            serverTargets = []
            pendingChanges = [:]
            savingChanges = [:]
        }
        self.ownerUserID = ownerUserID
        await reload()
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        syncAfterLocalChange = handler
    }

    func clearNotice() {
        notice = nil
    }

    /// Follows the live feed and the queue: a favorite from the other device, a confirmed
    /// send, or a write the server refused for good, which then drops out of the overlay.
    func observeStoreChanges() async {
        for await change in LocalStoreChanges.changes(in: .favorites, .pendingOperations) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == ownerUserID else { continue }
            await reload()
        }
    }

    // MARK: - What the screens use

    /// Whether this person saved the item, with their unsent changes applied.
    func isFavorite(_ target: FavoriteTarget) -> Bool {
        pendingChanges[target]?.favorited ?? serverTargets.contains(target)
    }

    /// Every favorite, newest first, with the unsent changes applied. A favorite the server
    /// has not heard of yet comes first, because the person just made it.
    var allFavorites: [FavoriteRef] {
        let added = pendingChanges
            .filter { $0.value.favorited && !serverTargets.contains($0.key) }
            .map { FavoriteRef(target: $0.key, createdAt: $0.value.createdAt) }
            .sorted { $0.createdAt > $1.createdAt }
        let kept = serverFavorites.filter { pendingChanges[$0.target]?.favorited ?? true }
        return added + kept
    }

    /// Saves or unsaves the item. The new value shows at once. The write is saved on the
    /// phone first and sent in the background, and the partner is never told.
    func setFavorite(_ favorited: Bool, target: FavoriteTarget) async {
        guard let userID = ownerUserID, isFavorite(target) != favorited else { return }
        let change = Change(favorited: favorited, createdAt: now())
        savingChanges[target] = change
        pendingChanges[target] = change
        defer { savingChanges[target] = nil }
        do {
            try await pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: userID,
                    operation: operationProvider.makeOperation(),
                    operationKind: .setFavorite,
                    idempotencyScope: FavoriteWritePayload.scope(for: target),
                    requestData: try JSONEncoder().encode(
                        FavoriteWritePayload(target: target, favorited: favorited, createdAt: change.createdAt)
                    )
                )
            )
        } catch {
            pendingChanges[target] = nil
            notice = .couldNotSave
            return
        }
        savingChanges[target] = nil
        if favorited, !defaults.bool(forKey: Self.privacyHintKey) {
            defaults.set(true, forKey: Self.privacyHintKey)
            notice = .privateToYou
        }
        await reload()
        if let sync = syncAfterLocalChange {
            Task { await sync() }
        }
    }

    /// Flips the item.
    func toggle(_ target: FavoriteTarget) async {
        await setFavorite(!isFavorite(target), target: target)
    }

    // MARK: - Reading

    /// Re-reads the cache and the queue.
    func reload() async {
        guard let userID = ownerUserID else {
            serverFavorites = []
            serverTargets = []
            pendingChanges = [:]
            return
        }
        // A favorite the server refused for good is already out of the queue. Say so once.
        if await cache.takeRefusalCount(ownerUserID: userID) > 0, ownerUserID == userID {
            notice = .refused
        }
        let ticket = reloadGate.begin()
        let stored = await cache.favorites(ownerUserID: userID)
        let queued = await Self.queuedChanges(from: pendingOperationStore, ownerUserID: userID)
        guard ownerUserID == userID, reloadGate.apply(ticket) else { return }
        serverFavorites = stored
        serverTargets = Set(stored.map(\.target))
        // A write the queue read could not see yet still counts.
        pendingChanges = (queued ?? pendingChanges).merging(savingChanges) { _, saving in saving }
    }

    /// The changes waiting in the queue, the last one of an item winning. Nil when the queue could not be read.
    nonisolated static func queuedChanges(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> [FavoriteTarget: Change]? {
        guard let operations = try? await store.inFlightOperations(ownerUserID: ownerUserID, kind: .setFavorite)
        else { return nil }
        var changes: [FavoriteTarget: Change] = [:]
        let decoder = JSONDecoder()
        for operation in operations.sorted(by: { $0.operation.clientSequence < $1.operation.clientSequence }) {
            let payload = operation.requestData.flatMap { try? decoder.decode(FavoriteWritePayload.self, from: $0) }
            guard let payload else { continue }
            changes[payload.target] = Change(favorited: payload.favorited, createdAt: payload.createdAt)
        }
        return changes
    }
}

/// Something the person should hear about a favorite.
nonisolated enum FavoritesNotice: Equatable, Sendable {
    /// The favorite could not be saved on the phone, so it is back as it was.
    case couldNotSave
    /// The server would not save the item, for example because it was deleted. It is back as it was.
    case refused
    /// Shown once, with the first favorite: only this person sees their favorites.
    case privateToYou

    @MainActor
    var banner: PaeoniaBannerContent {
        switch self {
        case .couldNotSave:
            .error(message: String(localized: .favoritesNoticeCouldNotSave))
        case .refused:
            .error(message: String(localized: .favoritesNoticeRefused))
        case .privateToYou:
            .info(message: String(localized: .favoritesPrivacyHint), systemImage: "star.fill")
        }
    }
}
