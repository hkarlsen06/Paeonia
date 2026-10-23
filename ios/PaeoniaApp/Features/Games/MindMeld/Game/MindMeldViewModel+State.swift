import Foundation

// Reading the cache and the queue, working out the phase, and starting a game.
extension MindMeldViewModel {
    // MARK: - Reading

    /// Re-reads the cache and the queue, then works out the phase.
    func reload() async {
        guard let userID = currentUserID else { return }
        let reloadTicket = reloadGate.begin()
        let document = await cache.document(ownerUserID: userID)
        let overview = await dependencies.cache.document(ownerUserID: userID).overview
        let work = await MindMeldPendingWork.load(from: dependencies.pendingOperationStore, ownerUserID: userID)
        // Kept here before the check below, so a newer reload still shows them.
        let refused = await cache.takeRefusedWords(ownerUserID: userID)
        refusedWords.append(contentsOf: refused)
        guard currentUserID == userID, reloadGate.apply(reloadTicket) else { return }

        state = document.state
        self.overview = overview
        if document.state != nil {
            hasLoaded = true
        }
        if let work {
            pending = work
        }
        now = dependencies.now()
        recompute()
        showRefusedWords()
    }

    /// Reads the server's state once and caches it.
    func refresh() async {
        guard let userID = currentUserID else { return }
        do {
            guard try await cache.fetchState(from: gateway, ownerUserID: userID), !Task.isCancelled else { return }
        } catch {
            // With nothing to show, the screen offers a retry.
            // Each failed read records its own reason, so an old "offline" never outlives the outage.
            if state == nil, !Task.isCancelled {
                startFailure = PaeoniaFailure(error)
            }
            return
        }
        hasLoaded = true
        startFailure = nil
        await reload()
    }

    /// Starts the couple's first game when the read says there is none.
    func startGameIfNeeded() async {
        guard phase == .starting, !isStartingGame else { return }
        await runStarting(isAutomatic: true) {
            _ = try await self.gateway.startMindMeldGame()
        }
    }

    /// "Try again" on the failed state: reads again, then starts a game if there is none.
    func retryStart() async {
        startFailure = nil
        if phase == .loading {
            await refresh()
        }
        await startGameIfNeeded()
    }

    /// Shows the starting phase while `create` runs, then reads the new game.
    /// A failed automatic start sets `startFailed`. Any other failure shows a notice.
    func runStarting(isAutomatic: Bool, _ create: () async throws -> Void) async {
        isStartingGame = true
        recompute()
        do {
            try await create()
            await refresh()
        } catch {
            if isAutomatic {
                startFailure = PaeoniaFailure(error)
            } else {
                notice = .couldNotStartGame(PaeoniaFailure(error))
            }
        }
        isStartingGame = false
        recompute()
    }

    // MARK: - Working out the screen

    /// Combines the server's state and the unsent moves into the observable
    /// state, then runs the effects a new state needs.
    func recompute() {
        guard let userID = currentUserID else { return }
        var work = pending
        work.isStarting = isStartingGame
        for (roundID, word) in unsavedLocks {
            work.lockedWords[roundID] = word
        }
        let resolver = MindMeldResolver(userID: userID)
        let resolved = resolver.resolve(state: state, hasLoaded: hasLoaded, pending: work)
        if resolution != resolved {
            resolution = resolved
        }
        if phase != resolved.phase {
            phase = resolved.phase
        }
        if stats != state?.stats {
            stats = state?.stats
        }
        let isHeld = phase == .waiting(isQueued: true) && pending.hasFailedMoveAttempt
        if isHeldOnPhone != isHeld {
            isHeldOnPhone = isHeld
        }
        followDraftRound()
        updatePartnerStatus()
        runEffects()
        if state != nil {
            attentionCue.update(resolver.attention(state: state, pending: work), isActive: isRunning && isActive)
        }
    }

    /// A new round starts with an empty field. The same round keeps what was typed.
    func followDraftRound() {
        if let openID = openRound?.id, openID != draftRoundID {
            draftRoundID = openID
            if !draft.isEmpty {
                draft = ""
            }
        }
        revalidateDraft()
    }

    func revalidateDraft() {
        let issue = MindMeldWord.validate(draft, used: usedWords)
        if draftIssue != issue {
            draftIssue = issue
        }
    }

    func draftChanged() {
        revalidateDraft()
        updateTyping()
    }

    /// Puts the word of a lock-in the server refused back in the field, once, and tells the person.
    func showRefusedWords() {
        guard !refusedWords.isEmpty else { return }
        for refused in refusedWords where refused.roundID == openRound?.id && draft.isEmpty {
            draft = refused.word
        }
        refusedWords = []
        notice = .moveRejected
    }

    /// Effects that depend on the new state. Each one guards against repeating.
    func runEffects() {
        guard !isStopped else { return }
        followPartnerRestart()
        if phase == .starting, !isStartingGame, !startFailed, startTask == nil {
            startTask = Task { [weak self] in
                await self?.startGameIfNeeded()
                self?.startTask = nil
            }
        }
    }

    /// The partner started over, so this game's ending is seen by now. Shows the
    /// note for good, and queues the mark once.
    func followPartnerRestart() {
        guard let gameID = resolution.partnerRestartedGameID else { return }
        showsPartnerRestartedNote = true
        guard queuedEndSeen.insert(gameID).inserted else { return }
        queueMove { [self] in
            let saved = await enqueue(
                .markMindMeldEndSeen,
                scope: "mind-meld-end-seen:\(gameID.uuidString.lowercased())",
                payload: MindMeldEndSeenPayload(gameID: gameID, createdAt: dependencies.now())
            )
            if !saved {
                queuedEndSeen.remove(gameID)
            }
        }
    }
}
