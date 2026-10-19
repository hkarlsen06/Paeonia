import Foundation

// Reading the cache and the queue, working out the phase, and making the game.
extension GuessMySpotViewModel {
    // MARK: - Reading

    /// Re-reads the cache, the queue and the marks, then works out the phase.
    func reload() async {
        guard let userID = currentUserID else { return }
        let ticket = reloadGate.begin()
        let document = await cache.document(ownerUserID: userID)
        let overview = await dependencies.cache.document(ownerUserID: userID).overview
        let work = await GuessMySpotPendingWork.load(from: dependencies.pendingOperationStore, ownerUserID: userID)
        let marks = await dependencies.boardGamesCache.document(ownerUserID: userID).marks
        let images = await renderedMarks(marks, userID: userID, partnerID: document.state?.partnerUserID)
        guard currentUserID == userID, reloadGate.apply(ticket) else { return }

        state = document.state
        self.overview = overview
        let style = overview?.settings?.playStyle ?? .together
        if playStyle != style {
            playStyle = style
        }
        if document.state != nil {
            hasLoaded = true
        }
        if let work {
            pending = work
        }
        refusedMoves = document.refusedMoves
        markImages = images
        updateStyles()
        now = dependencies.now()
        recompute()
        await showRefusedMoves()
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
            _ = try await gateway.ensureGuessMySpotGame()
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
        let queuedIDs = Set(work.sends.map(\.roundID))
        work.sends += unsavedSends.filter { !queuedIDs.contains($0.roundID) }
        work.guesses.merge(unsavedGuesses) { kept, _ in kept }
        work.seenReveals.formUnion(unsavedSeen)
        let resolved = GuessMySpotResolver(userID: userID).resolve(
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
        followGuessRound()
        loadRoundPhotoIfNeeded()
        updatePartnerStatus()
        syncLiveRole()
        runEffects()
    }

    /// A new guess starts with no pin on the map.
    func followGuessRound() {
        let roundID = phase == .guess ? round?.id : nil
        if roundID != guessPinRoundID {
            guessPinRoundID = roundID
            guessPin = nil
        }
    }

    /// Tells the person about a refused move, once a visit, and puts a refused send
    /// back on the check when it's their turn to send. A refusal arrives just before
    /// its operation leaves the queue, so each one waits until the move is gone from
    /// the queue. A refused guess, or a send whose photo is gone, is forgotten once told.
    func showRefusedMoves() async {
        guard !refusedMoves.isEmpty, let userID = currentUserID else { return }
        for refused in refusedMoves {
            let stillQueued = pending.sends.contains { $0.roundID == refused.roundID }
                || pending.guesses[refused.roundID] != nil
            guard !stillQueued else { continue }
            if !announcedRefusals.contains(refused.roundID) {
                announcedRefusals.insert(refused.roundID)
                notice = .moveRejected
            }
            guard let send = refused.send else {
                await cache.forgetRefusedMove(roundID: refused.roundID, ownerUserID: userID)
                continue
            }
            if phase == .send, draft == nil {
                await restoreDraft(from: send, ownerUserID: userID)
            }
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
