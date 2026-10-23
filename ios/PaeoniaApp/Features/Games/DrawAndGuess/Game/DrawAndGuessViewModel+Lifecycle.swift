import Foundation
import QuartzCore

// Starting and stopping: the screen appeared or went away, and the app moved to
// the background.
extension DrawAndGuessViewModel {
    // MARK: - Lifecycle

    /// The game screen appeared. Reads the cache, follows changes, and tells the
    /// partner this screen is open.
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        isStopped = false
        isActive = true
        await reload()
        // The screen may have gone away, or the app to the background, while the
        // cache was read. Opening presence and sockets now would leave them open.
        guard isRunning, !Task.isCancelled else { return }
        loops.beginObserving(
            currentUserID: { [weak self] in self?.currentUserID },
            reload: { [weak self] in await self?.reload() }
        )
        loops.beginTicking(every: tickInterval) { [weak self] in
            guard let self else { return }
            now = dependencies.now()
            recompute()
        }
        if isActive {
            loops.beginHeartbeat()
            startLive()
        }
        // The live feed keeps the cache current. This read covers a build without
        // it and the first launch, when the cache is empty.
        await refresh()
    }

    /// The game screen went away.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        isStopped = true
        attentionCue.reset()
        cancelTasks()
        loops.endHeartbeat()
        stopLive()
        saveDraftNow()
    }

    /// The app moved to the background or came back while the screen is open.
    func scenePhaseChanged(isActive newValue: Bool) {
        guard isRunning, newValue != isActive else { return }
        isActive = newValue
        if newValue {
            loops.beginHeartbeat()
            startLive()
            // A replay or a first look that waited for the screen starts now.
            recompute()
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in await self?.refresh() }
        } else {
            loops.endHeartbeat()
            stopLive()
            saveDraftNow()
        }
    }

    func cancelTasks() {
        loops.cancelFollowing()
        for task in [wrongGuessTask, draftTask, startTask, refreshTask] {
            task?.cancel()
        }
        cancelDrawingLoad()
        wrongGuessTask = nil
        draftTask = nil
        startTask = nil
        refreshTask = nil
        // The wrong word's animation stopped halfway. The slots open again, so
        // the same round can be guessed when the screen comes back.
        if isShowingWrongGuess {
            slots.clear()
            isShowingWrongGuess = false
        }
    }

    func resetForNewIdentity() {
        attentionCue.reset()
        state = nil
        pending = .none
        persistedHints = [:]
        phase = .loading
        round = nil
        live?.stop()
        live = nil
        liveGuessChannel = nil
        lastSentGuessScreen = nil
        receivedGuessScreen = nil
        partnerGuess = nil
        partnerReplayTimelineCache = nil
        tilesRoundID = nil
        boardRoundID = nil
        boardSentRoundID = nil
        board.reset()
        resetReplay()
        liveSnapshots = [:]
    }
}

// Reading the server and creating the game.
extension DrawAndGuessViewModel {
    /// Reads the server's state once and caches it.
    func refresh() async {
        guard let userID = currentUserID else { return }
        do {
            guard try await dependencies.cache.fetchState(from: gateway, ownerUserID: userID),
                  !Task.isCancelled
            else { return }
            refreshFailure = nil
        } catch {
            if !Task.isCancelled {
                refreshFailure = PaeoniaFailure(error)
            }
            return
        }
        await reload()
    }

    /// Creates the couple's game when setup is done and no game exists yet. The
    /// person who gets here first draws first.
    func startGameIfNeeded() async {
        guard phase == .preparing, !isStartingGame else { return }
        isStartingGame = true
        startFailure = nil
        defer { isStartingGame = false }
        do {
            _ = try await gateway.ensureDrawAndGuessGame()
            await refresh()
        } catch {
            startFailure = PaeoniaFailure(error)
            notice = .couldNotStartGame(PaeoniaFailure(error))
        }
    }

    func retryStart() async {
        await startGameIfNeeded()
    }
}
