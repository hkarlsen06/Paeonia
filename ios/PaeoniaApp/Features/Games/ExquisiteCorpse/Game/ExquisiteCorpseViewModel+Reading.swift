import PencilKit
import SwiftUI

// Reading the cache and the queue, working out the screen from them, and saving
// a move in the queue.
extension ExquisiteCorpseViewModel {
    // MARK: - Reading

    /// Re-reads the cache and the queue, then works out the phase.
    func reload() async {
        guard let userID = currentUserID else { return }
        let reloadTicket = reloadGate.begin()
        let document = await cache.document(ownerUserID: userID)
        let sharedOverview = await dependencies.cache.document(ownerUserID: userID).overview
        let work = await ExquisiteCorpsePendingWork.load(
            from: dependencies.pendingOperationStore,
            ownerUserID: userID
        )
        // Taking the notices forgets them, so they are shown even when a newer
        // reload started meanwhile.
        let notices = await cache.takeNotices(ownerUserID: userID)
        guard currentUserID == userID else { return }
        if let stored = notices.last {
            notice = GamesNotice(stored)
        }
        guard reloadGate.apply(reloadTicket) else { return }

        state = document.state
        overview = sharedOverview
        savedIdeaIDs = document.ideas
        if let work {
            pending = work
        }
        now = dependencies.now()
        recompute()
        await stars.reload()
    }

    /// Reads the server's state and the shared overview once and caches them.
    func refresh() async {
        guard let userID = currentUserID else { return }
        let overviewLoaded = (try? await dependencies.cache.fetchOverview(
            from: dependencies.gateway,
            ownerUserID: userID
        )) == true
        let stateLoaded = (try? await cache.fetchState(from: gateway, ownerUserID: userID)) == true
        guard overviewLoaded || stateLoaded, !Task.isCancelled else { return }
        await reload()
    }

    /// Creates the couple's game when setup is done and no game exists yet. The
    /// person who gets here first draws the first head.
    func startGameIfNeeded() async {
        guard phase == .preparing, !isStartingGame else { return }
        isStartingGame = true
        startFailure = nil
        defer { isStartingGame = false }
        do {
            _ = try await gateway.ensureExquisiteCorpseGame()
            await refresh()
        } catch {
            startFailure = PaeoniaFailure(error)
            notice = .couldNotStartGame(PaeoniaFailure(error))
        }
    }

    func retryStart() async {
        await startGameIfNeeded()
    }

    // MARK: - Working out the screen

    /// Combines the server's state and the unsent moves into the observable
    /// state, then runs the effects a new state needs.
    func recompute() {
        guard let userID = currentUserID else { return }
        let resolution = resolve(for: userID)
        phase = resolution.phase
        part = resolution.part
        figure = resolution.figure
        figureNumber = state?.game?.figureNumber ?? figureNumber
        figuresFinished = state?.game?.figuresFinished ?? 0
        isWaitingToSend = resolution.isWaitingToSend
        isHeldOnPhone = isWaitingToSend && pending.hasFailedMoveAttempt
        isSendFailing = pending.lastSendFailedWhileOnline
        settings = overview?.settings
        if phase == .preparing || phase == .needsSetup {
            if phase != .preparing {
                startFailure = nil
            }
        }

        updatePresenceState()
        updateWatching(partnerPartID: partnerPartID(for: resolution))
        keepUnsentBoard()
        syncBoard()
        updateStrip()
        updateReveal(resolution)
        runEffects()
    }

    /// Works out the phase. A partner who tapped Done on the part watched here
    /// still counts as drawing, so the watcher keeps the folded paper until the
    /// server moves the turn.
    private func resolve(for userID: UUID) -> ExquisiteCorpseResolution {
        let resolver = ExquisiteCorpseResolver(userID: userID)
        // The shared overview carries the settings. Until it has loaded, the
        // game is still loading and not waiting for setup.
        let visibleState = overview == nil ? nil : state
        let hasSettings = overview?.settings != nil
        let resolution = resolver.resolve(
            state: visibleState,
            hasSettings: hasSettings,
            pending: pending,
            isPartnerDrawingLive: live?.partnerActivity == .drawing
        )
        if resolution.phase == .waiting, let finished = partnerFinishedPartID,
           finished == partnerPartID(for: resolution) {
            return resolver.resolve(
                state: visibleState,
                hasSettings: hasSettings,
                pending: pending,
                isPartnerDrawingLive: true
            )
        }
        return resolution
    }

    /// The id of the part the partner draws, while this person waits or watches.
    func partnerPartID(for resolution: ExquisiteCorpseResolution) -> UUID? {
        guard resolution.phase == .waiting || resolution.phase == .watching,
              let part = resolution.part, let game = state?.game, let partnerID = partnerUserID
        else { return nil }
        return ExquisiteCorpseIDs.part(
            gameID: game.id,
            figureNumber: game.figureNumber,
            partIndex: part.rawValue,
            drawerID: partnerID
        )
    }

    /// The id of the part this person draws, while drawing.
    var ownPartID: UUID? {
        guard phase == .drawing, let part, let game = state?.game, let userID = currentUserID else { return nil }
        return ExquisiteCorpseIDs.part(
            gameID: game.id,
            figureNumber: game.figureNumber,
            partIndex: part.rawValue,
            drawerID: userID
        )
    }

    /// The figure and part ids a send needs. The figure id is the server's for a
    /// body or legs, and the one both phones work out for a new head.
    var figureIDToSend: UUID? {
        guard let game = state?.game else { return nil }
        return game.figureID ?? ExquisiteCorpseIDs.figure(gameID: game.id, number: game.figureNumber)
    }

    /// Effects that depend on the new state. Each one guards against repeating.
    private func runEffects() {
        syncLiveRole()
        guard !isStopped else { return }
        loadStripIfNeeded()
        loadRevealDrawingsIfNeeded()
        if phase == .preparing, !startFailed, startTask == nil {
            startTask = Task { [weak self] in
                await self?.startGameIfNeeded()
                self?.startTask = nil
            }
        }
    }

    /// The first head of a new game, which carries the only teaching line.
    var isFirstFigure: Bool {
        figureNumber == 1 && part == .head
    }

    /// The part before the one the partner draws is this person's. The waiting
    /// screen then says "Sent to [Name]".
    var didSendPreviousPart: Bool {
        guard let userID = currentUserID, let previous = part?.previous else { return false }
        return figure?.part(at: previous.rawValue)?.drawerUserID == userID
    }

    // MARK: - Queueing

    /// "Try again" on the waiting screen: sends what waits now, then reads the
    /// server's state.
    func retrySending() async {
        await syncAfterLocalChange?()
        await refresh()
    }

    /// Saves a move in the pending operations, shows its effect, and nudges the
    /// sync to send it now.
    @discardableResult
    func enqueue(
        _ kind: SyncPendingOperationKind,
        scope: String,
        payload: some Encodable
    ) async -> Bool {
        guard let userID = currentUserID, let data = try? JSONEncoder().encode(payload) else { return false }
        do {
            try await dependencies.pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: userID,
                    operation: dependencies.operationProvider.makeOperation(),
                    operationKind: kind,
                    idempotencyScope: scope,
                    requestData: data
                )
            )
        } catch {
            notice = .couldNotSaveMove
            return false
        }
        await reload()
        if let sync = syncAfterLocalChange {
            Task { await sync() }
        }
        return true
    }
}

nonisolated extension GamesNotice {
    init(_ stored: ExquisiteCorpseStoredNotice) {
        switch stored {
        case .partRejected: self = .exquisiteCorpsePartRejected
        case .moveRejected: self = .moveRejected
        }
    }
}
