import Foundation
import Observation

/// This person's private stars on finished rounds, for every screen that shows
/// or changes one: "Our drawings", its detail screen, and the result screens.
///
/// The value shown for a round is the server's value with this phone's unsent
/// changes on top. The server's value is the cache (`GamesHistoryCache`), which
/// the history pages and the star writes keep current. The unsent changes are
/// the queued `setGameRoundStar` writes, so a star shows at once, survives a
/// relaunch, and is sent when the phone is online. The last write of a round
/// wins.
///
/// It keys by round id only, so a round that just ended and is not in the
/// history list yet can be starred too.
@MainActor
@Observable
final class DrawAndGuessStars {
    /// Rounds the server says this person starred.
    private(set) var serverStars: Set<UUID> = []
    /// Unsent changes by round id: the value the person last chose.
    private(set) var pendingStars: [UUID: Bool] = [:]
    /// Show it through the banner center, then call `clearNotice()`.
    var notice: GamesNotice?

    @ObservationIgnored private let dependencies: GamesDependencies
    @ObservationIgnored private let currentUserID: @MainActor () -> UUID?
    @ObservationIgnored private var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?
    /// Changes the person made while their write was still being saved in the queue.
    @ObservationIgnored private var savingStars: [UUID: Bool] = [:]
    @ObservationIgnored private var reloadGeneration = 0
    /// Counts this person's star changes, so a server read can tell which rounds
    /// changed after it started.
    @ObservationIgnored private var changeCount = 0
    @ObservationIgnored private var lastChange: [UUID: Int] = [:]

    init(dependencies: GamesDependencies, currentUserID: @escaping @MainActor () -> UUID?) {
        self.dependencies = dependencies
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

    /// Whether this person starred the round, with their unsent changes applied.
    func isStarred(_ roundID: UUID) -> Bool {
        pendingStars[roundID] ?? serverStars.contains(roundID)
    }

    /// Stars or unstars the round. The new value shows at once. The write is
    /// saved on the phone first and sent in the background, and the partner is
    /// never told.
    func setStarred(_ isStarred: Bool, roundID: UUID) async {
        guard let userID = currentUserID(), self.isStarred(roundID) != isStarred else { return }
        savingStars[roundID] = isStarred
        pendingStars[roundID] = isStarred
        changeCount += 1
        lastChange[roundID] = changeCount
        defer { savingStars[roundID] = nil }
        do {
            try await dependencies.pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: userID,
                    operation: dependencies.operationProvider.makeOperation(),
                    operationKind: .setGameRoundStar,
                    idempotencyScope: "game-star:\(roundID.uuidString.lowercased())",
                    requestData: try JSONEncoder().encode(
                        GameStarPayload(roundID: roundID, starred: isStarred, createdAt: dependencies.now())
                    )
                )
            )
        } catch {
            pendingStars[roundID] = nil
            notice = .couldNotSaveMove
            return
        }
        savingStars[roundID] = nil
        await reload()
        if let sync = syncAfterLocalChange {
            Task { await sync() }
        }
    }

    /// Flips the star of the round.
    func toggle(roundID: UUID) async {
        await setStarred(!isStarred(roundID), roundID: roundID)
    }

    // MARK: - Reading

    /// Re-reads the cache and the queue.
    func reload() async {
        guard let userID = currentUserID() else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        let document = await dependencies.cache.document(ownerUserID: userID)
        let queued = await Self.queuedStars(from: dependencies.pendingOperationStore, ownerUserID: userID)
        // A newer reload started while this one waited. It has newer data.
        guard generation == reloadGeneration, currentUserID() == userID else { return }
        // The game state is the freshest answer for its own rounds. The cached list
        // covers the older ones.
        var stars = Set(document.drawings?.starredRoundIDs ?? [])
        for (roundID, isStarred) in document.state?.starValues ?? [:] {
            if isStarred { stars.insert(roundID) } else { stars.remove(roundID) }
        }
        serverStars = stars
        // A write the queue read could not see yet still counts.
        pendingStars = (queued ?? pendingStars).merging(savingStars) { _, saving in saving }
    }

    /// Keeps what the server said about these rounds, such as a page of the
    /// history. A round the person changed after the read started (`mark`, from
    /// `changeMark`) keeps their choice, even when that change was already sent,
    /// because the page may have been read before the change arrived. So does a
    /// round with a change that is not sent yet.
    func applyServerStars(_ values: [UUID: Bool], readSince mark: Int) async {
        guard let userID = currentUserID() else { return }
        let settled = values.filter { round in
            pendingStars[round.key] == nil && savingStars[round.key] == nil
                && (lastChange[round.key] ?? 0) <= mark
        }
        guard !settled.isEmpty else { return }
        await dependencies.cache.saveStars(settled, ownerUserID: userID)
        await reload()
    }

    /// The changes waiting in the queue, the last one of a round winning. Nil
    /// when the queue could not be read.
    static func queuedStars(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> [UUID: Bool]? {
        guard let operations = try? await store.inFlightOperations(ownerUserID: ownerUserID, kind: .setGameRoundStar)
        else { return nil }
        var stars: [UUID: Bool] = [:]
        let decoder = JSONDecoder()
        for operation in operations {
            guard let payload = operation.requestData.flatMap({ try? decoder.decode(GameStarPayload.self, from: $0) })
            else { continue }
            stars[payload.roundID] = payload.starred
        }
        return stars
    }
}
