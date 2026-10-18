import Foundation

// Reading the cache and the queue, working out the phase, and making the game.
extension ConsensioViewModel {
    // MARK: - Reading

    /// Re-reads the cache, the queue and the marks, then works out the phase.
    func reload() async {
        guard let userID = currentUserID else { return }
        let ticket = reloadGate.begin()
        let document = await cache.document(ownerUserID: userID)
        let overview = await dependencies.cache.document(ownerUserID: userID).overview
        let work = await ConsensioPendingWork.load(from: dependencies.pendingOperationStore, ownerUserID: userID)
        let refused = await cache.takeRefusedMoves(ownerUserID: userID)
        refusedMoves.append(contentsOf: refused)
        let marks = await dependencies.boardGamesCache.document(ownerUserID: userID).marks
        let images = await renderedMarks(marks, userID: userID, partnerID: document.state?.partnerUserID)
        guard currentUserID == userID, reloadGate.apply(ticket) else { return }

        state = document.state
        self.overview = overview
        if document.state != nil {
            hasLoaded = true
        }
        if let work {
            pending = work
        }
        markImages = images
        updateStyles()
        now = dependencies.now()
        recompute()
        showRefusedMoves()
    }

    /// Reads the server's state once and caches it, and the marks the first time.
    func refresh() async {
        guard let userID = currentUserID else { return }
        if !hasFetchedMarks {
            hasFetchedMarks = true
            _ = try? await dependencies.boardGamesCache.fetchMarks(
                from: dependencies.boardGamesGateway,
                ownerUserID: userID
            )
        }
        do {
            guard try await cache.fetchState(from: gateway, ownerUserID: userID), !Task.isCancelled else { return }
        } catch {
            if state == nil, !Task.isCancelled {
                startFailure = PaeoniaFailure(error)
            }
            return
        }
        hasLoaded = true
        startFailure = nil
        await reload()
    }

    /// Makes the couple's game when the read says there is none.
    func startGameIfNeeded() async {
        guard phase == .starting, !isStartingGame, state != nil else { return }
        isStartingGame = true
        recompute()
        do {
            _ = try await gateway.ensureConsensioGame()
            await refresh()
        } catch {
            startFailure = PaeoniaFailure(error)
        }
        isStartingGame = false
        recompute()
    }

    /// "Try again" on the failed state.
    func retryStart() async {
        startFailure = nil
        if state == nil {
            await refresh()
        }
        await startGameIfNeeded()
    }

    // MARK: - Working out the screen

    func recompute() {
        guard let userID = currentUserID else { return }
        var work = pending
        let queuedIDs = Set(work.placements.map(\.roundID))
        work.placements += unsavedPlacements.filter { !queuedIDs.contains($0.roundID) }
        work.guesses.merge(unsavedGuesses) { kept, _ in kept }
        work.seenReveals.formUnion(unsavedSeen)
        let resolved = ConsensioResolver(userID: userID).resolve(
            state: state,
            hasLoaded: hasLoaded,
            isStarting: isStartingGame,
            pending: work,
            deferredReveals: deferredReveals
        )
        if resolution != resolved {
            resolution = resolved
        }
        if phase != resolved.phase {
            phase = resolved.phase
        }
        if game != state?.game {
            game = state?.game
        }
        let isHeld = (phase == .waitingForGuess(isQueued: true) || phase == .reveal(isHeld: true))
            && pending.hasFailedMoveAttempt
        if isHeldOnPhone != isHeld {
            isHeldOnPhone = isHeld
        }
        let isFailing = isHeld && pending.lastSendFailedWhileOnline
        if isSendFailing != isFailing {
            isSendFailing = isFailing
        }
        followMarkerRound()
        updatePartnerStatus()
        syncLiveRole()
        runEffects()
    }

    /// A new guess starts with the marker in the middle. Leaving the guess phase
    /// takes it off the line, unless the place phase is showing its own.
    func followMarkerRound() {
        let roundID = phase == .guess ? round?.id : nil
        if roundID != markerRoundID {
            markerRoundID = roundID
            if roundID != nil {
                marker = ConsensioRules.middle
            } else if !showsPlacing, marker != nil {
                marker = nil
            }
        }
        if phase != .choose, placingTopic != nil {
            placingTopic = nil
        }
    }

    /// Puts a placement the server refused back on the line, once, and tells the person.
    /// A refusal arrives just before its operation leaves the queue, so each one
    /// waits until the move is gone from the queue and the screen shows the turn again.
    func showRefusedMoves() {
        guard !refusedMoves.isEmpty else { return }
        var waiting: [ConsensioRefusedMove] = []
        var shown = false
        for refused in refusedMoves {
            let stillQueued = pending.placements.contains { $0.roundID == refused.roundID }
                || pending.guesses[refused.roundID] != nil
            if stillQueued {
                waiting.append(refused)
                continue
            }
            if let topic = refused.topic, phase == .choose, placingTopic == nil {
                placingTopic = topic
                marker = refused.spot
            }
            shown = true
        }
        refusedMoves = waiting
        if shown {
            notice = .moveRejected
        }
    }

    func runEffects() {
        guard !isStopped else { return }
        if phase == .starting, !isStartingGame, startFailure == nil, startTask == nil {
            startTask = Task { [weak self] in
                await self?.startGameIfNeeded()
                self?.startTask = nil
            }
        }
    }
}
