import Foundation
import Observation

/// This person's private stars on finished rounds or figures, for every screen
/// of a game that shows or changes one: its history, the detail screen, and the
/// result screens. `GameStarSource` holds what differs per game.
///
/// The value shown for an item is the server's value with this phone's unsent
/// changes on top. The server's value is the game's cache, which the history
/// pages and the star writes keep current. The unsent changes are the queued star
/// writes, so a star shows at once, survives a relaunch, and is sent when the
/// phone is online. The last write of an item wins.
///
/// It keys by id only, so a round that just ended and is not in the history
/// list yet can be starred too.
@MainActor
@Observable
final class GameStars {
    /// Ids the server says this person starred.
    private(set) var serverStars: Set<UUID> = []
    /// Unsent changes by id: the value the person last chose.
    private(set) var pendingStars: [UUID: Bool] = [:]
    /// Show it through the banner center, then call `clearNotice()`.
    var notice: GamesNotice?

    @ObservationIgnored private let dependencies: GamesDependencies
    @ObservationIgnored private let source: GameStarSource
    @ObservationIgnored private let currentUserID: @MainActor () -> UUID?
    @ObservationIgnored private var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?
    /// Changes the person made while their write was still being saved in the queue.
    @ObservationIgnored private var savingStars: [UUID: Bool] = [:]
    @ObservationIgnored private var reloadGate = GameReloadGate()
    /// Counts this person's star changes, so a server read can tell which items
    /// changed after it started.
    @ObservationIgnored private var changeCount = 0
    @ObservationIgnored private var lastChange: [UUID: Int] = [:]

    init(
        source: GameStarSource,
        dependencies: GamesDependencies,
        currentUserID: @escaping @MainActor () -> UUID?
    ) {
        self.dependencies = dependencies
        self.source = source
        self.currentUserID = currentUserID
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        syncAfterLocalChange = handler
    }

    func clearNotice() {
        notice = nil
    }

    /// Take this before a server read and pass it to `applyServerStars`.
    var changeMark: Int {
        changeCount
    }

    // MARK: - What the screens use

    /// Whether this person starred the round or figure, with their unsent changes applied.
    func isStarred(_ id: UUID) -> Bool {
        pendingStars[id] ?? serverStars.contains(id)
    }

    /// Stars or unstars the round or figure. The new value shows at once. The
    /// write is saved on the phone first and sent in the background, and the
    /// partner is never told.
    func setStarred(_ isStarred: Bool, id: UUID) async {
        guard let userID = currentUserID(), self.isStarred(id) != isStarred else { return }
        savingStars[id] = isStarred
        pendingStars[id] = isStarred
        changeCount += 1
        lastChange[id] = changeCount
        defer { savingStars[id] = nil }
        do {
            try await dependencies.pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: userID,
                    operation: dependencies.operationProvider.makeOperation(),
                    operationKind: source.operationKind,
                    idempotencyScope: source.scope(id),
                    requestData: try source.payload(id, isStarred, dependencies.now())
                )
            )
        } catch {
            pendingStars[id] = nil
            notice = .couldNotSaveMove
            return
        }
        savingStars[id] = nil
        await reload()
        if let sync = syncAfterLocalChange {
            Task { await sync() }
        }
    }

    /// Flips the star of the round or figure.
    func toggle(id: UUID) async {
        await setStarred(!isStarred(id), id: id)
    }

    // MARK: - Reading

    /// Re-reads the cache and the queue.
    func reload() async {
        guard let userID = currentUserID() else { return }
        let reloadTicket = reloadGate.begin()
        let server = await source.serverStars(userID)
        let queued = await Self.queuedStars(
            from: dependencies.pendingOperationStore,
            ownerUserID: userID,
            source: source
        )
        guard currentUserID() == userID, reloadGate.apply(reloadTicket) else { return }
        serverStars = server
        // A write the queue read could not see yet still counts.
        pendingStars = (queued ?? pendingStars).merging(savingStars) { _, saving in saving }
    }

    /// Keeps what the server said about these ids, such as a page of the
    /// history. An id the person changed after the read started (`mark`, from
    /// `changeMark`) keeps their choice, even when that change was already sent,
    /// because the page may have been read before the change arrived. So does an
    /// id with a change that is not sent yet.
    func applyServerStars(_ values: [UUID: Bool], readSince mark: Int) async {
        guard let userID = currentUserID() else { return }
        let settled = values.filter { star in
            pendingStars[star.key] == nil && savingStars[star.key] == nil
                && (lastChange[star.key] ?? 0) <= mark
        }
        guard !settled.isEmpty else { return }
        await source.saveServerStars(settled, userID)
        await reload()
    }

    /// The changes waiting in the queue, the last one of an id winning. Nil
    /// when the queue could not be read.
    static func queuedStars(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID,
        source: GameStarSource
    ) async -> [UUID: Bool]? {
        guard let operations = try? await store.inFlightOperations(ownerUserID: ownerUserID, kind: source.operationKind)
        else { return nil }
        var stars: [UUID: Bool] = [:]
        for operation in operations {
            guard let queued = operation.requestData.flatMap(source.queued) else { continue }
            stars[queued.id] = queued.starred
        }
        return stars
    }
}
