import Foundation

// Starting and stopping: the screen appeared or went away, and the app moved to
// the background.
extension StoryChainViewModel {
    // MARK: - Lifecycle

    /// The game screen appeared. Reads the caches, follows changes, and tells the
    /// partner this screen is open.
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        mayRestoreSavedDraft = true
        isActive = true
        hasEnsuredGame = false
        await reload()
        // The screen may have gone away, or the app to the background, while the
        // cache was read. Opening presence and sockets now would leave them open.
        guard isRunning, !Task.isCancelled else { return }
        loops.beginObserving(
            currentUserID: { [weak self] in self?.currentUserID },
            reload: { [weak self] in await self?.reload() }
        )
        // Re-runs `recompute()` so presence, the invite button and a stale live draft
        // follow the clock.
        loops.beginTicking(every: tickInterval) { [weak self] in
            self?.recompute()
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
        // The page that was writing a line in is gone. The line is on the page
        // the next time.
        arrivingLineID = nil
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
        for task in [startTask, refreshTask] {
            task?.cancel()
        }
        startTask = nil
        refreshTask = nil
    }

    func resetForNewIdentity() {
        state = nil
        settings = nil
        overviewPresence = nil
        pending = .none
        clearDisplayedState()
        revealedStoryID = nil
        isNamingInFlight = false
        localFinishedDates = [:]
        animatedLineIDs = []
        arrivingLineID = nil
        selectedOpening = nil
        titleDraft = ""
        namingStoryID = nil
        resetComposer()
        writingKey = nil
        localInviteSentAt = nil
        partnerMessage = nil
        liveSentKey = nil
        live?.stop()
        live = nil
        liveChannel = nil
        liveWindowTask?.cancel()
        liveWindowTask = nil
    }

    // MARK: - Creating the game

    /// Creates the couple's game when setup is done and no game exists yet. The
    /// person who gets here first starts the first story.
    func startGameIfNeeded() {
        guard phase == .preparing, isRunning, !startFailed, !hasEnsuredGame, startTask == nil else { return }
        hasEnsuredGame = true
        startTask = Task { [weak self] in
            await self?.ensureGame()
            self?.startTask = nil
        }
    }

    func retryStart() async {
        guard phase == .preparing, !isStartingGame else { return }
        await ensureGame()
    }

    private func ensureGame() async {
        guard !isStartingGame else { return }
        isStartingGame = true
        startFailure = nil
        defer { isStartingGame = false }
        do {
            _ = try await storyGateway.ensureStoryChainGame()
            await refresh()
        } catch {
            startFailure = PaeoniaFailure(error)
            notice = .couldNotStartGame(PaeoniaFailure(error))
        }
    }
}
