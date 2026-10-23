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
        loops.beginObserving(
            currentUserID: { [weak self] in self?.currentUserID },
            reload: { [weak self] in await self?.reload() }
        )
        loops.beginTicking(every: tickInterval) { [weak self] in
            guard let self else { return }
            now = dependencies.now()
            updatePresence()
        }
        loops.beginHeartbeat()
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
        attentionCue.reset()
        loops.cancelFollowing()
        pauseDisplay()
        loops.endHeartbeat()
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
        lastMoveSettles = nil
    }

    /// The app moved to the background or came back while the screen is open.
    func scenePhaseChanged(isActive newValue: Bool) {
        guard isRunning, newValue != isActive else { return }
        isActive = newValue
        if newValue {
            loops.beginHeartbeat()
            recompute()
            Task { [weak self] in await self?.refresh() }
        } else {
            // Nothing counts as shown while the app is in the background.
            pauseDisplay()
            loops.endHeartbeat()
        }
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
