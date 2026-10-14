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
        beginObserving()
        beginTicking()
        if isActive {
            beginHeartbeat()
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
        endHeartbeat()
        stopLive()
        saveDraftNow()
    }

    /// The app moved to the background or came back while the screen is open.
    func scenePhaseChanged(isActive newValue: Bool) {
        guard isRunning, newValue != isActive else { return }
        isActive = newValue
        if newValue {
            beginHeartbeat()
            startLive()
            recompute()
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in await self?.refresh() }
        } else {
            heartbeatTask?.cancel()
            heartbeatTask = nil
            sendPresence(false)
            stopLive()
            saveDraftNow()
        }
    }

    func cancelTasks() {
        for task in [observationTask, tickTask, startTask, refreshTask] {
            task?.cancel()
        }
        observationTask = nil
        tickTask = nil
        startTask = nil
        refreshTask = nil
    }

    func beginObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await change in LocalStoreChanges.changes(in: .games, .pendingOperations) {
                guard !Task.isCancelled, let self else { return }
                guard change.ownerUserID == nil || change.ownerUserID == currentUserID else { continue }
                await reload()
            }
        }
    }

    /// Re-runs `recompute()` so presence, the invite button and a stale live draft
    /// follow the clock.
    func beginTicking() {
        tickTask?.cancel()
        let interval = tickInterval
        let sleep = sleep
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await sleep(interval)
                guard !Task.isCancelled, let self else { return }
                recompute()
            }
        }
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
        startFailed = false
        defer { isStartingGame = false }
        do {
            _ = try await storyGateway.ensureStoryChainGame()
            await refresh()
        } catch {
            startFailed = true
            notice = .couldNotStartGame
        }
    }
}
