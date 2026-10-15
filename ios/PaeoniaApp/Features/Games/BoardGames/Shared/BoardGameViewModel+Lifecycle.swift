import Foundation

// Starting and stopping: the screen appeared or went away, and the app moved to
// the background.
extension BoardGameViewModel {
    /// The board screen appeared. Reads the cache, follows changes, and tells
    /// the partner this game is open.
    func start(prefersReducedMotion: Bool) async {
        self.prefersReducedMotion = prefersReducedMotion
        guard !isRunning else { return }
        isRunning = true
        isActive = true
        await reload()
        guard isRunning, !Task.isCancelled else { return }
        beginObserving()
        beginTicking()
        beginHeartbeat()
        // The live feed keeps the cache current. This read covers the first
        // launch, when the cache is empty.
        await refresh()
        if phase != .game, isRunning {
            await startGame()
        }
    }

    /// The board screen went away. The board starts fresh next time, from where
    /// this phone left the game.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        for task in [observationTask, tickTask] {
            task?.cancel()
        }
        observationTask = nil
        tickTask = nil
        pauseDisplay()
        endHeartbeat()
    }

    /// Stops the board where it is and remembers how far it showed the game.
    /// The next time the board shows, it carries on from there: a replay or a
    /// missed ending resumes, and an outcome already played shows settled.
    func pauseDisplay() {
        replayTask?.cancel()
        replayTask = nil
        isReplaying = false
        outcomeTask?.cancel()
        outcomeTask = nil
        markShown()
        hasDisplay = false
        isShowingMissedEnding = false
        showsOutcome = false
        result = nil
        isResultCollapsed = false
        stagedOutcomeGame = nil
        lastMove = nil
    }

    /// The app moved to the background or came back while the screen is open.
    func scenePhaseChanged(isActive newValue: Bool) {
        guard isRunning, newValue != isActive else { return }
        isActive = newValue
        if newValue {
            beginHeartbeat()
            recompute()
            Task { [weak self] in await self?.refresh() }
        } else {
            // Nothing counts as shown while the app is in the background.
            pauseDisplay()
            endHeartbeat()
        }
    }

    private func beginObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await change in LocalStoreChanges.changes(in: .games, .pendingOperations) {
                guard !Task.isCancelled, let self else { return }
                guard change.ownerUserID == nil || change.ownerUserID == currentUserID else { continue }
                await reload()
            }
        }
    }

    private func beginTicking() {
        tickTask?.cancel()
        let interval = tickInterval
        let sleep = sleep
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await sleep(interval)
                guard !Task.isCancelled, let self else { return }
                now = dependencies.now()
                updatePresence()
            }
        }
    }

    private func beginHeartbeat() {
        heartbeatTask?.cancel()
        let gateway = dependencies.gateway
        let kind = kind
        let interval = heartbeatInterval
        let sleep = sleep
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await gateway.setPresence(kind, isPresent: true)
                try? await sleep(interval)
            }
        }
    }

    private func endHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        let gateway = dependencies.gateway
        let kind = kind
        Task { try? await gateway.setPresence(kind, isPresent: false) }
    }
}

/// A problem to tell the person about on the board screen, through the shared
/// top banner. The copy says what happened and what to do next.
nonisolated enum BoardGamesNotice: Equatable, Sendable {
    /// The server refused a move for good. The board shows the game as it is.
    case moveRejected
    /// Saving a move on the phone failed.
    case couldNotSaveMove
    case couldNotSendInvite(PaeoniaFailure)

    @MainActor
    var banner: PaeoniaBannerContent {
        switch self {
        case .moveRejected:
            .error(
                title: String(localized: .boardGamesNoticeMoveRejectedTitle),
                message: String(localized: .boardGamesNoticeMoveRejectedMessage)
            )
        case .couldNotSaveMove:
            .error(
                title: String(localized: .gamesNoticeMoveFailedTitle),
                message: String(localized: .gamesNoticeMoveFailedMessage)
            )
        case .couldNotSendInvite(let failure):
            .error(
                title: String(localized: .gamesNoticeInviteFailedTitle),
                message: String(
                    localized: failure == .offline ? .gamesNoticeInviteFailedMessage : .commonActionFailedMessage
                )
            )
        }
    }
}

/// What a board game's hub card shows. It follows the game, not the board on
/// screen, which can trail it during a replay.
nonisolated struct BoardGameHubSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The couple has never opened this game.
        case notStarted
        case yourTurn
        case partnerTurn
        case youWon
        case partnerWon
        case draw
    }

    let status: Status
    let score: BoardGameScore?

    var isYourTurn: Bool {
        status == .yourTurn
    }
}
