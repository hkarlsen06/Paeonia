import Foundation
import Observation

/// This person's private stars on finished stories, for every screen that shows
/// or changes one: "Our stories", its detail screen, and the finished story.
///
/// The value shown for a story is the server's value with this phone's unsent
/// changes on top. The server's value comes from the Story Chain cache: the
/// state's two stories, the stars the star writes and the history pages kept,
/// and the first page of "Our stories". The unsent changes are the queued
/// `storyChainSetStar` writes, so a star shows at once, survives a relaunch, and
/// is sent when the phone is online. The last write of a story wins.
///
/// It keys by story id only, so a story that just finished and is not in the
/// history list yet can be starred too.
@MainActor
@Observable
final class StoryChainStars {
    /// Stories the server says this person starred.
    private(set) var serverStars: Set<UUID> = []
    /// Unsent changes by story id: the value the person last chose.
    private(set) var pendingStars: [UUID: Bool] = [:]
    /// Show it through the banner center, then call `clearNotice()`.
    var notice: GamesNotice?

    @ObservationIgnored private let dependencies: GamesDependencies
    @ObservationIgnored private let currentUserID: @MainActor () -> UUID?
    @ObservationIgnored private var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?
    /// Changes the person made while their write was still being saved in the queue.
    @ObservationIgnored private var savingStars: [UUID: Bool] = [:]
    @ObservationIgnored private var reloadGate = GameReloadGate()
    /// Counts this person's star changes, so a server read can tell which stories
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

    /// Whether this person starred the story, with their unsent changes applied.
    func isStarred(_ storyID: UUID) -> Bool {
        pendingStars[storyID] ?? serverStars.contains(storyID)
    }

    /// Stars or unstars the story. The new value shows at once. The write is
    /// saved on the phone first and sent in the background, and the partner is
    /// never told.
    func setStarred(_ isStarred: Bool, storyID: UUID) async {
        guard let userID = currentUserID(), self.isStarred(storyID) != isStarred else { return }
        savingStars[storyID] = isStarred
        pendingStars[storyID] = isStarred
        changeCount += 1
        lastChange[storyID] = changeCount
        defer { savingStars[storyID] = nil }
        do {
            try await dependencies.pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: userID,
                    operation: dependencies.operationProvider.makeOperation(),
                    operationKind: .storyChainSetStar,
                    idempotencyScope: "story-chain-star:\(storyID.uuidString.lowercased())",
                    requestData: try JSONEncoder().encode(
                        StoryChainStarPayload(storyID: storyID, starred: isStarred, createdAt: dependencies.now())
                    )
                )
            )
        } catch {
            pendingStars[storyID] = nil
            notice = .couldNotSaveMove
            return
        }
        savingStars[storyID] = nil
        await reload()
        if let sync = syncAfterLocalChange {
            Task { await sync() }
        }
    }

    /// Flips the star of the story.
    func toggle(storyID: UUID) async {
        await setStarred(!isStarred(storyID), storyID: storyID)
    }

    // MARK: - Reading

    /// Re-reads the cache and the queue.
    func reload() async {
        guard let userID = currentUserID() else { return }
        let reloadTicket = reloadGate.begin()
        let document = await dependencies.storyChainCache.document(ownerUserID: userID)
        let queued = await Self.queuedStars(from: dependencies.pendingOperationStore, ownerUserID: userID)
        guard currentUserID() == userID, reloadGate.apply(reloadTicket) else { return }
        // The oldest answer first: the first page, then the stars kept from star
        // writes and pages, then the state, which is the freshest for its own stories.
        var values = document.historyFirstPage?.starValues ?? [:]
        values.merge(document.stars) { _, newer in newer }
        values.merge(document.state?.starValues ?? [:]) { _, newer in newer }
        serverStars = Set(values.filter { $0.value }.keys)
        // A write the queue read could not see yet still counts.
        pendingStars = (queued ?? pendingStars).merging(savingStars) { _, saving in saving }
    }

    /// Keeps what the server said about these stories, such as a page of the
    /// history. A story the person changed after the read started (`mark`, from
    /// `changeMark`) keeps their choice, even when that change was already sent,
    /// because the page may have been read before the change arrived. So does a
    /// story with a change that is not sent yet.
    func applyServerStars(_ values: [UUID: Bool], readSince mark: Int) async {
        guard let userID = currentUserID() else { return }
        let settled = values.filter { story in
            pendingStars[story.key] == nil && savingStars[story.key] == nil
                && (lastChange[story.key] ?? 0) <= mark
        }
        guard !settled.isEmpty else { return }
        await dependencies.storyChainCache.saveStars(settled, ownerUserID: userID)
        await reload()
    }

    /// The changes waiting in the queue, the last one of a story winning. Nil
    /// when the queue could not be read.
    static func queuedStars(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> [UUID: Bool]? {
        guard let operations = try? await store.inFlightOperations(ownerUserID: ownerUserID, kind: .storyChainSetStar)
        else { return nil }
        var stars: [UUID: Bool] = [:]
        let decoder = JSONDecoder()
        for operation in operations {
            let payload = operation.requestData.flatMap { try? decoder.decode(StoryChainStarPayload.self, from: $0) }
            guard let payload else { continue }
            stars[payload.storyID] = payload.starred
        }
        return stars
    }
}
